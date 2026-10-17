const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const WIX = "https://www.wixapis.com";
const ALLOWED_CLASSIFIED_ATTRIBUTES = new Set([
  "brand", "model", "year", "mileage", "energy", "gearbox", "bodyType", "engineCapacity",
  "fiscalPower", "powerHp", "doors", "seats", "color", "size", "material", "dimensions",
  "capacity", "partType", "partReference", "oemReference", "compatibleMake", "compatibleModel",
  "compatibleYearFrom", "compatibleYearTo", "engineCode",
]);
const isAllowedClassifiedAttribute = (key: string) => ALLOWED_CLASSIFIED_ATTRIBUTES.has(key) || (
  /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(key) &&
  !/^(?:_?id|ownerId|accountId|memberId|professionalId|hostId|rentalUnit|createdAt|updatedAt|status|isPublic|isActive|slug|attributesJSON|catalogVersion|classifiedOwner.*|pf.*|imported.*|source.*|stripe.*|payment.*|order.*|purchase.*)$/i.test(key)
);

type WixItem = { id?: string; data?: Record<string, unknown>; [key: string]: unknown };

const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});

function unwrap(item: WixItem): Record<string, unknown> {
  const data = item.data && typeof item.data === "object" ? item.data : item;
  return { ...data, _id: data._id ?? item.id ?? data.id };
}

async function wixRequest<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const result = await fetch(`${WIX}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });
  const raw = await result.text();
  if (!result.ok) throw new Error(`Wix API (${result.status})`);
  return (raw ? JSON.parse(raw) : {}) as T;
}

async function query(
  collection: string,
  filter: Record<string, unknown>,
  fields: string[],
  token: string,
  limit = 100,
): Promise<Record<string, unknown>[]> {
  const result = await wixRequest<{ dataItems?: WixItem[] }>("/wix-data/v2/items/query", token, {
    method: "POST",
    body: JSON.stringify({
      dataCollectionId: collection,
      query: { filter, paging: { limit }, fields },
    }),
  });
  return (result.dataItems ?? []).map(unwrap);
}

// Wix's v2 CMS query uses offset paging. Match the source site's getAllCmsItems
// behavior here so the native demand board does not silently stop at page 1.
async function queryAll(
  collection: string,
  filter: Record<string, unknown>,
  fields: string[],
  token: string,
): Promise<Record<string, unknown>[]> {
  const all: Record<string, unknown>[] = [];
  const limit = 100;
  let offset = 0;
  while (true) {
    const result = await wixRequest<{
      dataItems?: WixItem[];
      pagingMetadata?: { count?: number; offset?: number; total?: number };
    }>("/wix-data/v2/items/query", token, {
      method: "POST",
      body: JSON.stringify({
        dataCollectionId: collection,
        query: { filter, paging: { limit, offset }, ...(fields.length ? { fields } : {}) },
      }),
    });
    const page = (result.dataItems ?? []).map(unwrap);
    all.push(...page);
    if (page.length < limit) break;
    const nextOffset = Number(result.pagingMetadata?.offset ?? offset) + page.length;
    if (!Number.isFinite(nextOffset) || nextOffset <= offset) break;
    offset = nextOffset;
  }
  return all;
}

const privateDemandFieldNames = new Set([
  "name", "firstname", "lastname", "fullname", "displayname", "contactname", "requestername", "sendername",
  "hiddenbyprofessionals", "claimid",
]);
const privateDemandFieldPattern = /(email|phone|telephone|mobile|contact|requester|sender|address|owner|accountid|memberid|profileid|professionalid|proid)/i;

function withoutDemandContact(item: Record<string, unknown>): Record<string, unknown> {
  const stripPrivateFields = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(stripPrivateFields);
    if (!value || typeof value !== "object") return value;
    const safe: Record<string, unknown> = {};
    for (const [key, fieldValue] of Object.entries(value as Record<string, unknown>)) {
      const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, "");
      if (privateDemandFieldNames.has(normalized) || privateDemandFieldPattern.test(normalized)) continue;
      safe[key] = stripPrivateFields(fieldValue);
    }
    return safe;
  };
  return stripPrivateFields(item) as Record<string, unknown>;
}

const first = (items: Record<string, unknown>[]) => items[0] ?? null;
const emailFilter = (email: string) => ({ email: { $eq: email } });
const listingPhotoBucket = "pf-ios-listing-photos";

function departmentFromPostal(value: unknown): string {
  const postal = String(value ?? "").trim().toUpperCase();
  if (postal.startsWith("2A") || postal.startsWith("2B")) return postal.slice(0, 2);
  if (postal.startsWith("20")) return "2A";
  return /^\d{2}/.exec(postal)?.[0] ?? "";
}

function distanceKm(aLat: unknown, aLon: unknown, bLat: unknown, bLon: unknown): number | null {
  const values = [aLat, aLon, bLat, bLon].map(Number);
  if (values.some((value) => !Number.isFinite(value))) return null;
  const [lat1, lon1, lat2, lon2] = values.map((value) => value * Math.PI / 180);
  const dLat = lat2 - lat1;
  const dLon = lon2 - lon1;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function classifyDemand(demand: Record<string, unknown>, profile: Record<string, unknown>): string {
  const postal = String(demand.postalCode ?? "").trim();
  const main = String(profile.mainPostalCode ?? profile.postalCode ?? "").trim();
  const secondaryValue = profile.secondaryPostalCodes ?? profile.coveredPostalCodes;
  const secondary = Array.isArray(secondaryValue)
    ? secondaryValue.map((item) => String(item).trim()).filter(Boolean)
    : String(secondaryValue ?? "").split(/[,;|]/).map((item) => item.trim()).filter(Boolean);
  if (main && postal === main) return "direct";
  const distance = distanceKm(profile.latitude, profile.longitude, demand.latitude, demand.longitude);
  const radius = Number(profile.maxRadiusKm) || 20;
  if (distance !== null && distance <= radius) return "nearby";
  if (postal && secondary.includes(postal)) return "secondary";
  const demandDepartment = departmentFromPostal(demand.department ?? postal);
  const professionalDepartments = new Set(
    [profile.department, profile.departmentCode, main, ...secondary]
      .map(departmentFromPostal)
      .filter(Boolean),
  );
  if (demandDepartment && professionalDepartments.has(demandDepartment)) return "department";
  return "other";
}

function newestFirst(items: Record<string, unknown>[]): Record<string, unknown>[] {
  return items.sort((a, b) => {
    const dateA = new Date(String(a.requestDate ?? a.claimedAt ?? a._createdDate ?? a.createdAt ?? 0)).getTime() || 0;
    const dateB = new Date(String(b.requestDate ?? b.claimedAt ?? b._createdDate ?? b.createdAt ?? 0)).getTime() || 0;
    return dateB - dateA;
  });
}

function getSupabaseSecretKey(): string {
  try {
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
    if (typeof secretKeys.default === "string" && secretKeys.default) return secretKeys.default;
  } catch { /* Fall back to the legacy server-only key when the project has not migrated keys. */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function ownedListingPhotos(value: unknown, role: string, memberID: string, projectURL: string): string[] | null {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > 20 || value.some((photo) => typeof photo !== "string")) return null;
  const base = `${projectURL.replace(/\/$/, "")}/storage/v1/object/public/${listingPhotoBucket}/${role}/${memberID}/`;
  const photos = value.map((photo) => String(photo));
  return photos.every((photo) => photo.startsWith(base) && photo.length <= 2048) ? photos : null;
}

function galleryPhotoURLs(value: unknown): string[] {
  let parsed = value;
  if (typeof parsed === "string") {
    try { parsed = JSON.parse(parsed) as unknown; } catch { return []; }
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.map((entry) => {
    if (typeof entry === "string") return entry;
    if (entry && typeof entry === "object") {
      const photo = entry as Record<string, unknown>;
      return typeof photo.url === "string" ? photo.url : typeof photo.src === "string" ? photo.src : "";
    }
    return "";
  }).filter(Boolean);
}

function listingPhotoURLs(item: Record<string, unknown>, list: string, role: string): string[] {
  const directKeys = list === "classifieds"
    ? ["itemImage", ...Array.from({ length: 19 }, (_, index) => `photo${index + 2}`)]
    : role === "professionnel"
      ? ["mainImageUrl", ...Array.from({ length: 5 }, (_, index) => `photo${index + 1}`)]
      : ["mainImage", ...Array.from({ length: 20 }, (_, index) => `photo${index + 1}`)];
  const values = directKeys.map((key) => item[key]).filter((value): value is string => typeof value === "string" && value.length > 0);
  values.push(...galleryPhotoURLs(item.galleryImages));
  return [...new Set(values)];
}

function profileCategoryEntries(value: unknown): Record<string, unknown>[] {
  let parsed = value;
  if (typeof parsed === "string") {
    try { parsed = JSON.parse(parsed) as unknown; } catch { return []; }
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.filter((entry): entry is Record<string, unknown> => Boolean(entry) && typeof entry === "object" && !Array.isArray(entry));
}

async function loadDashboard(role: string, email: string, memberID: string, token: string) {
  if (role === "particulier") {
    const account = first(await query("privateaccounts", emailFilter(email), ["email", "accountType", "isActive"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const [profiles, properties, classifieds, favorites, savedSearches, buyerMatchings] = await Promise.all([
      query("privateprofiles", { ownerId: { $eq: accountId } }, ["ownerId", "firstName", "lastName", "email", "phone", "city", "postalCode", "isProfileComplete"], token, 2),
      query("privateproperties", { ownerId: { $eq: accountId } }, ["ownerId", "title", "description", "propertyType", "transactionType", "sellingPrice", "estimatedPrice", "surface", "landSurface", "rooms", "bedrooms", "bathrooms", "city", "postalCode", "mainImage", "photo1", "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8", "photo9", "photo10", "photo11", "photo12", "photo13", "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20", "galleryImages", "isPublic", "status", "createdAt", "slug"], token),
      query("classifiedads-1", { ownerId: { $eq: accountId } }, [
        "ownerId", "itemName", "itemPrice", "itemDescription", "itemImage",
        "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8", "photo9", "photo10",
        "photo11", "photo12", "photo13", "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20",
        "category", "subcategory", "adListingType", "itemCondition", "attributesJSON", "city", "postalCode", "status", "createdAt",
      ], token),
      query("favoritelistings", { accountId: { $eq: accountId } }, ["accountId", "listingId", "sourceCollection", "createdAt", "isArchived"], token),
      query("particularbuyersearches", { accountId: { $eq: accountId } }, ["accountId", "searchName", "transactionType", "propertyTypes", "city", "postalCode", "latitude", "longitude", "radius", "minBudget", "maxBudget", "minSurface", "maxSurface", "minLandSurface", "maxLandSurface", "minRooms", "minBedrooms", "minBathrooms", "singleStory", "garage", "garden", "terrace", "pool", "parking", "emailAlertsEnabled", "isActive", "createdAt", "updatedAt"], token),
      query("particularsearchmatchings", { buyerAccountId: { $eq: accountId } }, ["buyerAccountId", "searchId", "propertyId", "propertyTitle", "propertyCity", "propertyPostalCode", "propertyPrice", "propertySurface", "propertyType", "transactionType", "propertyUrl", "propertyImage", "professionalId", "professionalMemberId", "professionalName", "professionalFirstName", "professionalEmail", "professionalPhone", "professionalCity", "professionalNetwork", "professionalPhoto", "professionalSlug", "matchingScore", "status", "dismissedByParticulier", "emailSentToBuyer", "emailSentToProfessional", "createdAt", "notifiedAt"], token),
    ]);
    return {
      role, account: { id: accountId }, profile: first(profiles),
      properties: properties.filter((item) => item.status !== "archived"),
      classifieds: classifieds.filter((item) => item.status !== "archived"),
      favorites, savedSearches, buyerMatchings: buyerMatchings.filter((item) => item.dismissedByParticulier !== true),
    };
  }

  if (role === "professionnel") {
    const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive", "cguAccepted", "cgvAccepted"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profile = first(await query("prosprofiles", { accountId: { $eq: accountId } }, ["accountId", "companyName", "contactName", "phoneNumber", "email", "city", "postalCode", "mainPostalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude", "professionalType", "category", "categories", "description", "logo", "photo", "website", "slug", "isActive", "isVisiblePublicly", "hasActiveSubscription", "subscriptionStatus", "subscriptionStartDate", "subscriptionEndDate"], token, 2));
    const accountSummary = {
      id: accountId,
      cguAccepted: account.cguAccepted === true,
      cgvAccepted: account.cgvAccepted === true,
    };
    if (!profile) return { role, account: accountSummary, profile: null, properties: [], matchings: [], messages: [] };
    // The Wix demand system still keys matching rows to the legacy
    // `professionnels` profile. Native sign-in also creates `prosprofiles`, so
    // prefer the legacy identity whenever it exists and fall back otherwise.
    const legacyProfessional = first(await query("professionnels", { memberId: { $eq: memberID } }, [
      "memberId", "mainPostalCode", "postalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude",
    ], token, 2));
    const matchingProfile = legacyProfessional ?? profile;
    const professionalId = String(matchingProfile._id ?? profile._id ?? "");
    const [properties, matchings, allClaims, allDemands, hiddenDemands, minisiteRequests, estimationRequests, propertyRequests, messages] = await Promise.all([
      // Public Wix listings are linked to the Wix member identity, not the
      // separate prosprofiles item ID. Using professionalId here returned an
      // empty property list for otherwise active professional accounts.
      query("biensprofessionnels", { wixMemberId: { $eq: memberID } }, ["wixMemberId", "professionalId", "title", "description", "propertyType", "transactionType", "price", "surface", "surfaceLand", "landSurface", "rooms", "bedrooms", "bathrooms", "address", "city", "postalCode", "mainImageUrl", "photo1", "photo2", "photo3", "photo4", "photo5", "galleryImages", "status", "commercialStatus", "updatedAt"], token),
      query("matchings", { professionalId: { $eq: professionalId } }, ["professionalId", "propertyId", "acquereurId", "matchingScore", "matchingType", "status", "seen", "createdAt"], token),
      queryAll("demandespromatchings", {}, [], token),
      queryAll("particuliersprives", {}, [], token),
      queryAll("prohiddendemands", { proId: { $eq: professionalId } }, ["proId", "demandId"], token),
      queryAll("demandesminisite", { professionalId: { $eq: professionalId } }, [], token),
      queryAll("demandesestimation", { professionalId: { $eq: professionalId } }, [], token),
      queryAll("propertycontactrequests", { professionalId: { $eq: professionalId } }, [], token),
      query("messages", { receiverId: { $eq: professionalId } }, ["conversationId", "senderId", "receiverId", "content", "createdAt", "isRead", "readAt"], token),
    ]);
    const ownClaims = allClaims.filter((item) => String(item.proId ?? "") === professionalId);
    const ownClaimIds = new Set(ownClaims.map((item) => String(item.demandId ?? "")));
    const claimsByDemand = new Map<string, Record<string, unknown>[]>();
    for (const claim of allClaims) {
      const demandId = String(claim.demandId ?? "");
      if (!demandId) continue;
      claimsByDemand.set(demandId, [...(claimsByDemand.get(demandId) ?? []), claim]);
    }
    const demandById = new Map(allDemands.map((item) => [String(item._id ?? ""), item]));
    const acceptedDemands = ownClaims.flatMap((claim) => {
      const demand = demandById.get(String(claim.demandId ?? ""));
      return demand ? [{ ...demand, ...claim, matchingId: claim._id, claimCount: claimsByDemand.get(String(claim.demandId))?.length ?? 1 }] : [];
    });
    const hiddenIDs = new Set(hiddenDemands.map((item) => String(item.demandId ?? "")));
    const availableDemands = allDemands.flatMap((demand) => {
      const demandId = String(demand._id ?? "");
      const claims = claimsByDemand.get(demandId) ?? [];
      const hiddenBy = String(demand.hiddenByProfessionals ?? "").split(",").map((id) => id.trim());
      if (!demandId || ownClaimIds.has(demandId) || hiddenIDs.has(demandId) || hiddenBy.includes(professionalId) || claims.length >= 3) return [];
      const matchType = classifyDemand(demand, matchingProfile);
      // Wix's ProDemandesPage loads and classifies every visible demand. Keep
      // the same pool in native; postal-code, radius, secondary-code and
      // department matches describe priority rather than restricting access.
      const safeDemand = withoutDemandContact(demand);
      return [{ ...safeDemand, claimCount: claims.length, matchType }];
    });
    return {
      role, account: accountSummary, profile, matchingProfile,
      properties: properties.filter((item) => item.status !== "archived"), matchings,
      demands: newestFirst(acceptedDemands), availableDemands: newestFirst(availableDemands),
      minisiteRequests: newestFirst(minisiteRequests), estimationRequests: newestFirst(estimationRequests),
      propertyRequests: newestFirst(propertyRequests), messages,
    };
  }

  if (role === "courtier") {
    const account = first(await query("brokeraccounts", emailFilter(email), ["email", "isActive", "cguAccepted", "cgvAccepted"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profile = first(await query("brokerprofiles", { accountId: { $eq: accountId } }, ["accountId", "fullName", "professionalTitle", "profilePicture", "bio", "contactEmail", "phoneNumber", "city", "websiteUrl", "yearsOfExperience"], token, 2));
    const messages = profile ? await query("brokermessages", { brokerProfileId: { $eq: String(profile._id ?? "") } }, ["brokerProfileId", "senderName", "senderEmail", "senderPhone", "message", "isRead", "createdAt"], token) : [];
    return { role, account: { id: accountId, cguAccepted: account.cguAccepted === true, cgvAccepted: account.cgvAccepted === true }, profile, messages };
  }

  if (role === "artisan" || role === "diagnostiqueur") {
    const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive", "cguAccepted", "cgvAccepted"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profiles = await query("prosprofiles", { accountId: { $eq: accountId } }, [
      "accountId", "professionalType", "companyName", "contactName", "phoneNumber", "email", "city",
      "postalCode", "mainPostalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude",
      "category", "categories", "description", "logo", "photo", "website", "slug", "isActive",
      "isVisiblePublicly", "isProfileComplete", "hasActiveSubscription", "subscriptionStatus",
      "subscriptionStartDate", "subscriptionEndDate", "profileViews", "contactRequestsCount",
    ], token, 10);
    const profile = profiles.find((item) => {
      const type = String(item.professionalType ?? "").toLowerCase();
      const category = String(item.category ?? "").toLowerCase();
      const categories = String(item.categories ?? "").toLowerCase();
      return role === "artisan"
        ? (type.includes("artisan") || category.includes("artisan") || categories.includes("artisan")) && !categories.includes("diagnostiqueur")
        : type.includes("diagnostiqueur") || category.includes("diagnostiqueur") || categories.includes("diagnostiqueur");
    }) ?? null;
    if (!profile || profile.isActive === false) return null;
    const profileId = String(profile._id ?? "");
    const [messages, subscriptions] = await Promise.all([
      query("artisanmessages", { artisanId: { $eq: profileId } }, [
        "artisanId", "senderName", "senderEmail", "senderPhone", "messageContent", "createdAt", "isRead",
      ], token),
      query("subscriptions", emailFilter(email), [
        "email", "professionalType", "professionalId", "subscriptionStatus", "accessEnabled", "trialActive",
        "subscriptionStartDate", "subscriptionEndDate", "freeAccessUntil", "billingPlan", "cancel_at_period_end",
      ], token, 100),
    ]);
    const subscription = subscriptions.find((item) => {
      const type = String(item.professionalType ?? "").toLowerCase();
      const ownerId = String(item.professionalId ?? "");
      return ownerId === profileId || (role === "artisan"
        ? type.includes("artisan") && !type.includes("diagnost")
        : type.includes("diagnost"));
    }) ?? null;
    return {
      role,
      account: { id: accountId, cguAccepted: account.cguAccepted === true, cgvAccepted: account.cgvAccepted === true },
      profile,
      messages,
      subscription,
    };
  }

  if (role === "prestataire") {
    // Prestataires keep their separate Wix service-provider account collections.
    const accountFields = ["email", "isActive", "firstName", "lastName"];
    let account = first(await query("serviceprovideraccounts-1", emailFilter(email), accountFields, token, 2));
    if (!account) {
      account = first(await query("serviceprovideraccounts", emailFilter(email), accountFields, token, 2));
    }
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const providers = await query("serviceproviders-1", { accountId: { $eq: accountId } }, ["accountId", "businessName", "category", "subcategory", "description", "services", "city", "postalCode", "phone", "email", "website", "photoUrls", "status", "verified"], token, 3);
    const activity = (entry: Record<string, unknown>) => `${String(entry.category ?? "")} ${String(entry.subcategory ?? "")}`;
    const profile = providers.find((entry) => !/artisan|diagnostiqueur/i.test(activity(entry))) ?? null;
    const messages = profile ? await query("artisanmessages", { artisanId: { $eq: String(profile._id ?? "") } }, ["artisanId", "senderName", "senderEmail", "senderPhone", "messageContent", "createdAt", "isRead"], token) : [];
    return { role, account: { id: accountId }, profile, messages };
  }

  if (role === "hebergeur") {
    const profile = first(await query("seasonalhostprofiles", emailFilter(email), ["email", "fullName", "phoneNumber", "profilePicture", "biography", "isVerified"], token, 2));
    if (!profile) return null;
    const hostId = String(profile._id ?? "");
    if (!hostId) return {
      role, profile, accommodations: [], bookingRequests: [], reservations: [], conversations: [],
      calendar: [], externalBookings: [], seasonalRates: [], calendarConnections: [],
    };

    // These are existing Wix CMS collections. Scope every list through the
    // authenticated host profile or an accommodation owned by that profile.
    const [accommodations, reservations, conversations, hostSubscriptions] = await Promise.all([
      queryAll("seasonalaccommodations", { hostId: { $eq: hostId } }, [
        "hostId", "itemName", "itemPrice", "itemDescription", "itemImage", "photo1", "photo2", "photo3",
        "galleryImage2", "galleryImage3", "galleryImage4", "galleryImage5", "photo4", "photo5", "photo6",
        "photo7", "photo8", "photo9", "photo10", "photo11", "photo12", "photo13", "photo14",
        "photo15", "photo16", "photo17", "photo18", "photo19", "photo20", "photo21", "photo22",
        "photo23", "photo24", "photo25", "photo26", "photo27", "photo28", "photo29", "photo30",
        "accommodationType", "locationAddress", "city", "postalCode", "maxGuests", "numberOfBedrooms",
        "amenities", "slug", "status", "latitude", "longitude", "department", "checkInMode",
        "checkInTime", "checkInUntil", "accessMethod", "arrivalInstructions",
      ], token),
      queryAll("seasonalreservations", { hostId: { $eq: hostId } }, [
        "hostId", "accommodationId", "vacationerId", "source", "vacationerName", "vacationerEmail",
        "accommodationTitle", "checkInDate", "checkOutDate", "numberOfGuests", "reservationStatus",
        "paymentStatus", "totalPrice", "bookingDateTime",
      ], token),
      queryAll("seasonalconversations", { hostId: { $eq: hostId } }, [
        "hostId", "vacationerId", "accommodationId", "lastMessageTimestamp", "status",
      ], token),
      queryAll("seasonalhostsubscriptions", { hostProfileId: { $eq: hostId } }, [
        "hostProfileId", "subscriptionTier", "status", "startDate", "endDate", "renewalDate", "lastPaymentDate", "amountPaid", "paymentMethod",
      ], token),
    ]);

    const accommodationNameByID = new Map(accommodations.map((item) => [
      String(item._id ?? ""), String(item.itemName ?? "").trim(),
    ]));
    const conversationCards = conversations.map((conversation) => {
      const accommodationName = accommodationNameByID.get(String(conversation.accommodationId ?? "")) ?? "";
      return {
        ...conversation,
        title: accommodationName ? `Échange · ${accommodationName}` : "Conversation voyageur",
      };
    });

    const accommodationIDs = [...new Set(accommodations.map((item) => String(item._id ?? "")).filter(Boolean))];
    const bookingRequestPages: Record<string, unknown>[][] = [];
    const calendarPages: Record<string, unknown>[][] = [];
    const externalBookingPages: Record<string, unknown>[][] = [];
    const seasonalRatePages: Record<string, unknown>[][] = [];
    const calendarConnectionPages: Record<string, unknown>[][] = [];
    for (let start = 0; start < accommodationIDs.length; start += 3) {
      const accommodationBatch = accommodationIDs.slice(start, start + 3);
      const relatedPages = await Promise.all(accommodationBatch.map(async (accommodationId) => Promise.all([
        queryAll("seasonalbookingrequests", { accommodationId: { $eq: accommodationId } }, [
          "accommodationId", "vacationerId", "vacationerName", "vacationerEmail", "vacationerPhone",
          "checkInDate", "checkOutDate", "proposedCheckInDate", "proposedCheckOutDate", "numberOfNights",
          "numberOfAdults", "numberOfChildren", "numberOfBabies", "petsIncluded", "guestMessage", "status",
          "totalPrice", "hiddenByHost",
        ], token),
        queryAll("seasonalcalendars", { linkedEntityId: { $eq: accommodationId } }, [
          "linkedEntityId", "linkedEntityType", "calendarDate", "availabilityStatus", "pricePerNight",
          "minimumStay", "bookingRequestId", "checkInFrom", "checkInUntil", "checkOutUntil",
        ], token),
        queryAll("seasonalexternalbookings", { accommodationId: { $eq: accommodationId } }, [
          "accommodationId", "sourcePlatform", "startDate", "endDate", "externalBookingReference",
        ], token),
        queryAll("seasonalrates", { accommodationId: { $eq: accommodationId } }, [
          "accommodationId", "seasonName", "startDate", "endDate", "pricePerNight", "minimumStayNights",
        ], token),
        queryAll("seasonalicalconnections", { accommodationId: { $eq: accommodationId } }, [
          "accommodationId", "iCalUrl", "platformName", "lastSyncDate", "syncStatus",
        ], token),
      ])));
      for (const [requests, calendar, externalBookings, seasonalRates, calendarConnections] of relatedPages) {
        bookingRequestPages.push(requests);
        calendarPages.push(calendar);
        externalBookingPages.push(externalBookings);
        seasonalRatePages.push(seasonalRates);
        calendarConnectionPages.push(calendarConnections);
      }
    }
    const bookingRequests = [...new Map(bookingRequestPages.flat()
      .filter((item) => item.hiddenByHost !== true)
      .map((item) => [String(item._id ?? ""), item] as const)
      .filter(([id]) => Boolean(id))).values()];
    const uniqueItems = (pages: Record<string, unknown>[][]) => [...new Map(pages.flat()
      .map((item) => [String(item._id ?? ""), item] as const)
      .filter(([id]) => Boolean(id))).values()];

    return {
      role, profile, accommodations, bookingRequests, reservations, conversations: conversationCards,
      calendar: uniqueItems(calendarPages),
      externalBookings: uniqueItems(externalBookingPages),
      seasonalRates: uniqueItems(seasonalRatePages),
      calendarConnections: uniqueItems(calendarConnectionPages),
      subscription: [...hostSubscriptions].sort((a, b) => String(b.endDate ?? "").localeCompare(String(a.endDate ?? "")))[0] ?? null,
    };
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET" && req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);
  let body: Record<string, unknown> = {};
  if (req.method === "POST") {
    try {
      body = await req.json();
    } catch {
      return response({ error: "Demande invalide." }, 400);
    }
  }
  const role = req.method === "POST"
    ? String(body.role ?? "")
    : new URL(req.url).searchParams.get("role") ?? "";
  if (!["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire", "hebergeur"].includes(role)) {
    return response({ error: "Espace inconnu." }, 400);
  }

  try {
    const result = await wixRequest<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = String(result.member?.loginEmail ?? "").trim().toLowerCase();
    if (!result.member?.id || !email || result.member.loginEmailVerified === false) {
      return response({ error: "Le compte Wix n’est pas vérifié." }, 403);
    }
    if (req.method === "POST") {
      if (body.action === "update_profile") {
        const profileId = String(body.profileId ?? "").trim();
        const fields = body.fields;
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(profileId) || !fields || typeof fields !== "object" || Array.isArray(fields)) {
          return response({ error: "Profil invalide." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const profile = dashboard?.profile as Record<string, unknown> | null | undefined;
        if (!profile || String(profile._id ?? profile.id ?? "") !== profileId) {
          return response({ error: "Ce profil n’est pas associé à votre espace." }, 404);
        }
        const source = fields as Record<string, unknown>;
        const readText = (key: string, max = 500): string | null => {
          const value = source[key];
          if (typeof value !== "string") return null;
          return value.trim().slice(0, max);
        };
        const textValue = (key: string, max = 500, target = key): [string, unknown] | null => {
          const value = readText(key, max);
          return value === null ? null : [target, value];
        };
        const data: Record<string, unknown> = {};
        let collection = "";
        if (role === "particulier") {
          collection = "privateprofiles";
          for (const [key, max] of [["firstName", 80], ["lastName", 80], ["phone", 40], ["city", 100], ["postalCode", 10]] as const) {
            const entry = textValue(key, max);
            if (entry) data[entry[0]] = entry[1];
          }
          if (data.firstName !== undefined && String(data.firstName).length < 2) return response({ error: "Le prénom doit contenir au moins 2 caractères." }, 400);
          if (data.lastName !== undefined && String(data.lastName).length < 2) return response({ error: "Le nom doit contenir au moins 2 caractères." }, 400);
        } else if (role === "professionnel") {
          collection = "prosprofiles";
          for (const [key, max, target] of [["companyName", 140, "companyName"], ["contactName", 140, "contactName"], ["phone", 40, "phoneNumber"], ["city", 100, "city"], ["postalCode", 10, "postalCode"], ["category", 100, "category"], ["description", 8000, "description"], ["website", 500, "website"]] as const) {
            const entry = textValue(key, max, target);
            if (entry) data[entry[0]] = entry[1];
          }
          const type = readText("professionalType", 40);
          if (type !== null) data.professionalType = type;
          const visible = source.isVisiblePublicly;
          if (typeof visible === "boolean") data.isVisiblePublicly = visible;
          if (data.companyName !== undefined && String(data.companyName).length < 2) return response({ error: "Le nom de la société doit contenir au moins 2 caractères." }, 400);
          if (data.category !== undefined && String(data.category).length < 2) return response({ error: "Le métier doit contenir au moins 2 caractères." }, 400);
          if (data.category !== undefined) {
            const existingCategories = profileCategoryEntries(profile.categories);
            const requestedSubcategory = readText("subcategory", 100);
            if (existingCategories.length > 0) {
              const currentSubcategories = existingCategories[0].subCategories ?? existingCategories[0].subcategories;
              const subcategories = requestedSubcategory
                ? [requestedSubcategory]
                : Array.isArray(currentSubcategories) ? currentSubcategories : [];
              existingCategories[0] = { ...existingCategories[0], mainCategory: data.category, subCategories: subcategories };
              data.categories = JSON.stringify(existingCategories);
            } else {
              data.categories = JSON.stringify([{ mainCategory: data.category, subCategories: [requestedSubcategory].filter(Boolean) }]);
            }
          }
          if (data.city !== undefined && String(data.city).length < 2) return response({ error: "La ville doit contenir au moins 2 caractères." }, 400);
          if (data.postalCode !== undefined && !/^\d{4,10}$/.test(String(data.postalCode))) return response({ error: "Le code postal doit contenir entre 4 et 10 chiffres." }, 400);
        } else if (role === "courtier") {
          collection = "brokerprofiles";
          for (const [key, max, target] of [["contactName", 140, "fullName"], ["professionalTitle", 100, "professionalTitle"], ["phone", 40, "phoneNumber"], ["city", 100, "city"], ["website", 500, "websiteUrl"], ["description", 8000, "bio"]] as const) {
            const entry = textValue(key, max, target);
            if (entry) data[entry[0]] = entry[1];
          }
          const years = readText("yearsOfExperience", 3);
          if (years !== null && years !== "") {
            const number = Number(years);
            if (!Number.isInteger(number) || number < 0 || number > 80) return response({ error: "Le nombre d’années d’expérience est invalide." }, 400);
            data.yearsOfExperience = number;
          }
        } else if (role === "artisan" || role === "diagnostiqueur") {
          collection = "prosprofiles";
          for (const [key, max, target] of [["companyName", 140, "companyName"], ["contactName", 140, "contactName"], ["phone", 40, "phoneNumber"], ["city", 100, "city"], ["postalCode", 10, "postalCode"], ["description", 8000, "description"], ["website", 500, "website"]] as const) {
            const entry = textValue(key, max, target);
            if (entry) data[entry[0]] = entry[1];
          }
          const subcategory = readText("subcategory", 100);
          const expectedCategory = role === "artisan" ? "Artisan" : "Diagnostiqueur";
          data.category = expectedCategory;
          data.mainPostalCode = data.postalCode ?? profile.mainPostalCode ?? "";
          if (subcategory !== null) data.categories = JSON.stringify([{ mainCategory: expectedCategory, subCategories: subcategory ? [subcategory] : [] }]);
          if (data.companyName !== undefined && String(data.companyName).length < 2) return response({ error: "Le nom de l’entreprise doit contenir au moins 2 caractères." }, 400);
          if (subcategory !== null && subcategory.length < 2) return response({ error: "La spécialité doit contenir au moins 2 caractères." }, 400);
          if (data.city !== undefined && String(data.city).length < 2) return response({ error: "La ville doit contenir au moins 2 caractères." }, 400);
          if (data.postalCode !== undefined && !/^\d{4,10}$/.test(String(data.postalCode))) return response({ error: "Le code postal doit contenir entre 4 et 10 chiffres." }, 400);
        } else if (role === "prestataire") {
          collection = "serviceproviders-1";
          for (const [key, max, target] of [["companyName", 140, "businessName"], ["category", 100, "category"], ["subcategory", 100, "subcategory"], ["description", 8000, "description"], ["city", 100, "city"], ["postalCode", 10, "postalCode"], ["phone", 40, "phone"], ["website", 500, "website"]] as const) {
            const entry = textValue(key, max, target);
            if (entry) data[entry[0]] = entry[1];
          }
          if (data.businessName !== undefined && String(data.businessName).length < 2) return response({ error: "Le nom de l’entreprise doit contenir au moins 2 caractères." }, 400);
          if (data.category !== undefined && String(data.category).length < 2) return response({ error: "L’activité doit contenir au moins 2 caractères." }, 400);
          if (data.city !== undefined && String(data.city).length < 2) return response({ error: "La ville doit contenir au moins 2 caractères." }, 400);
          if (data.postalCode !== undefined && !/^\d{4,10}$/.test(String(data.postalCode))) return response({ error: "Le code postal doit contenir entre 4 et 10 chiffres." }, 400);
        } else if (role === "hebergeur") {
          collection = "seasonalhostprofiles";
          for (const [key, max, target] of [["companyName", 140, "fullName"], ["phone", 40, "phoneNumber"], ["description", 8000, "biography"]] as const) {
            const entry = textValue(key, max, target);
            if (entry) data[entry[0]] = entry[1];
          }
          if (data.fullName !== undefined && String(data.fullName).length < 2) return response({ error: "Le nom de l’hébergement doit contenir au moins 2 caractères." }, 400);
        }
        if (!collection || Object.keys(data).length === 0) return response({ error: "Aucune modification autorisée à enregistrer." }, 400);
        const fieldModifications = Object.entries(data).map(([fieldPath, value]) => ({
          fieldPath, action: "SET_FIELD", setFieldOptions: { value },
        }));
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(profileId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({ dataCollectionId: collection, patch: { dataItemId: profileId, fieldModifications } }),
        });
        return response({ success: true, role, profileId });
      }
      if (body.action === "claim_demand") {
        if (role !== "professionnel") return response({ error: "Cette action est réservée à l’espace professionnel." }, 403);
        const demandId = String(body.demandId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(demandId)) return response({ error: "Demande invalide." }, 400);
        const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive"], token, 2));
        if (!account || account.isActive === false) return response({ error: "Aucun compte professionnel actif n’est associé à cette adresse." }, 403);
        const accountId = String(account._id ?? "");
        const nativeProfile = first(await query("prosprofiles", { accountId: { $eq: accountId } }, [
          "accountId", "isActive", "mainPostalCode", "postalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude",
        ], token, 2));
        if (!nativeProfile || nativeProfile.isActive === false) return response({ error: "Aucune fiche professionnelle active n’a été trouvée." }, 403);
        const legacyProfile = first(await query("professionnels", { memberId: { $eq: result.member.id } }, [
          "memberId", "mainPostalCode", "postalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude",
        ], token, 2));
        const professionalId = String(legacyProfile?._id ?? nativeProfile._id ?? "");
        if (!professionalId) return response({ error: "Votre profil professionnel est incomplet." }, 403);

        const demand = first(await query("particuliersprives", { _id: { $eq: demandId } }, [], token, 2));
        if (!demand) return response({ error: "Cette demande n’est plus disponible." }, 404);
        const hidden = first(await query("prohiddendemands", {
          proId: { $eq: professionalId }, demandId: { $eq: demandId },
        }, ["proId", "demandId"], token, 2));
        const hiddenBy = String(demand.hiddenByProfessionals ?? "").split(",").map((id) => id.trim());
        if (hidden || hiddenBy.includes(professionalId)) return response({ error: "Cette demande n’est pas disponible dans votre espace." }, 403);

        const claims = await queryAll("demandespromatchings", { demandId: { $eq: demandId } }, ["demandId", "proId"], token);
        if (claims.some((claim) => String(claim.proId ?? "") === professionalId)) {
          return response({ error: "Vous avez déjà accepté cette demande." }, 409);
        }
        if (claims.length >= 3) return response({ error: "Cette demande a déjà été attribuée à 3 professionnels." }, 409);
        const now = new Date().toISOString();
        const inserted = await wixRequest<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, {
          method: "POST",
          body: JSON.stringify({
            dataCollectionId: "demandespromatchings",
            dataItem: { data: {
              demandId, proId: professionalId, status: "claimed", claimedAt: now,
              demandType: String(demand.demandType ?? ""), postalCode: String(demand.postalCode ?? ""), isViewed: true,
            } },
          }),
        });
        const claimId = String(inserted.dataItem?.id ?? "");
        if (!claimId) return response({ error: "Wix n’a pas confirmé l’acceptation de la demande." }, 502);
        // The push uses the same Wix server-side event resolver as the website.
        // Push delivery is secondary and never rolls back a successful claim.
        void fetch("https://www.partenairefoyer.com/api/push-notify-event", {
          method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify({ eventType: "demand_claim", entityId: claimId }),
          signal: AbortSignal.timeout(12_000),
        }).catch((error) => console.warn("[ios-native-dashboard] Claim push unavailable", error));
        return response({ success: true, claimId, demandId, claimCount: claims.length + 1 });
      }

      if (body.action === "hide_booking_request") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const requestId = String(body.requestId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(requestId)) return response({ error: "Demande de réservation invalide." }, 400);
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const requests = (dashboard?.bookingRequests as Record<string, unknown>[] | undefined) ?? [];
        const bookingRequest = requests.find((item) => String(item._id ?? item.id ?? "") === requestId);
        if (!bookingRequest) return response({ error: "Cette demande n’est plus disponible dans votre espace." }, 404);
        const accommodationId = String(bookingRequest.accommodationId ?? "");
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        if (!accommodationId || !accommodations.some((item) => String(item._id ?? item.id ?? "") === accommodationId)) {
          return response({ error: "Cette demande n’est liée à aucun de vos hébergements." }, 403);
        }
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(requestId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({ dataCollectionId: "seasonalbookingrequests", patch: {
            dataItemId: requestId,
            fieldModifications: [{ fieldPath: "hiddenByHost", action: "SET_FIELD", setFieldOptions: { value: true } }],
          } }),
        });
        return response({ success: true, requestId, hiddenByHost: true });
      }

      if (body.action === "transition_booking_request") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const requestId = String(body.requestId ?? "").trim();
        const nextStatus = String(body.status ?? "").trim().toLowerCase();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(requestId) || !["accepted", "rejected"].includes(nextStatus)) {
          return response({ error: "Demande ou statut de réservation invalide." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const requests = (dashboard?.bookingRequests as Record<string, unknown>[] | undefined) ?? [];
        const bookingRequest = requests.find((item) => String(item._id ?? item.id ?? "") === requestId);
        if (!bookingRequest) return response({ error: "Cette demande n’est plus disponible dans votre espace." }, 404);
        const accommodationId = String(bookingRequest.accommodationId ?? "");
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        const accommodation = accommodations.find((item) => String(item._id ?? item.id ?? "") === accommodationId);
        if (!accommodation) return response({ error: "Cette demande n’est liée à aucun de vos hébergements." }, 403);
        const currentStatus = String(bookingRequest.status ?? "pending").toLowerCase();
        const reservations = (dashboard?.reservations as Record<string, unknown>[] | undefined) ?? [];
        const checkInDate = String(bookingRequest.checkInDate ?? "").slice(0, 10);
        const checkOutDate = String(bookingRequest.checkOutDate ?? "").slice(0, 10);
        const vacationerId = String(bookingRequest.vacationerId ?? "");
        const hostId = String((dashboard?.profile as Record<string, unknown> | undefined)?._id ?? "");
        if (!/^\d{4}-\d{2}-\d{2}$/.test(checkInDate) || !/^\d{4}-\d{2}-\d{2}$/.test(checkOutDate) || checkOutDate <= checkInDate) {
          return response({ error: "Les dates de cette demande sont invalides." }, 409);
        }
        if (currentStatus === "accepted" && nextStatus === "rejected") {
          return response({ error: "Une réservation déjà acceptée ne peut pas être refusée depuis cette demande." }, 409);
        }
        if (currentStatus === "rejected" && nextStatus === "accepted") {
          return response({ error: "Cette demande a déjà été refusée." }, 409);
        }
        if (currentStatus !== "pending" && currentStatus !== nextStatus) {
          return response({ error: "Seules les demandes en attente peuvent être modifiées." }, 409);
        }
        const existingReservation = reservations.find((item) =>
          String(item.accommodationId ?? "") === accommodationId &&
          String(item.vacationerId ?? "") === vacationerId &&
          String(item.checkInDate ?? "").slice(0, 10) === checkInDate &&
          String(item.checkOutDate ?? "").slice(0, 10) === checkOutDate &&
          String(item.reservationStatus ?? "").toLowerCase() === "confirmed"
        );
        if (nextStatus === "accepted" && !existingReservation) {
          const allCalendar = await queryAll("seasonalcalendars", { linkedEntityId: { $eq: accommodationId } }, [
            "linkedEntityId", "calendarDate", "availabilityStatus", "bookingRequestId",
          ], token);
          const nights: string[] = [];
          const cursor = new Date(`${checkInDate}T00:00:00.000Z`);
          const checkout = new Date(`${checkOutDate}T00:00:00.000Z`);
          while (cursor < checkout && nights.length < 366) {
            nights.push(cursor.toISOString().slice(0, 10));
            cursor.setUTCDate(cursor.getUTCDate() + 1);
          }
          const conflicts = allCalendar.filter((entry) => {
            const date = String(entry.calendarDate ?? "").slice(0, 10);
            if (!nights.includes(date) || String(entry.bookingRequestId ?? "") === requestId) return false;
            const status = String(entry.availabilityStatus ?? "").toLowerCase();
            return ["unavailable", "reserved", "booked", "blocked", "external"].includes(status) ||
              (status === "pending" && Boolean(entry.bookingRequestId));
          });
          const reservationConflict = reservations.some((item) =>
            String(item.accommodationId ?? "") === accommodationId &&
            String(item.reservationStatus ?? "").toLowerCase() === "confirmed" &&
            String(item.checkInDate ?? "").slice(0, 10) < checkOutDate &&
            String(item.checkOutDate ?? "").slice(0, 10) > checkInDate
          );
          const externalBookings = (dashboard?.externalBookings as Record<string, unknown>[] | undefined) ?? [];
          const externalConflict = externalBookings.some((item) =>
            String(item.accommodationId ?? "") === accommodationId &&
            String(item.startDate ?? "").slice(0, 10) < checkOutDate &&
            String(item.endDate ?? "").slice(0, 10) > checkInDate
          );
          if (conflicts.length || reservationConflict || externalConflict) {
            return response({ error: "Ces dates ne sont plus disponibles. Actualisez le calendrier avant d’accepter." }, 409);
          }
          const adults = Number(bookingRequest.numberOfAdults ?? 0);
          const children = Number(bookingRequest.numberOfChildren ?? 0);
          const babies = Number(bookingRequest.numberOfBabies ?? 0);
          const nightsCount = nights.length;
          const totalPrice = Number(bookingRequest.totalPrice ?? (Number(accommodation.itemPrice ?? 0) * nightsCount));
          const bookingDateTime = new Date().toISOString();
          const insertedReservation = await wixRequest<{ dataItem?: WixItem }>("/wix-data/v2/items", token, {
            method: "POST",
            body: JSON.stringify({ dataCollectionId: "seasonalreservations", dataItem: { data: {
              accommodationId, hostId, vacationerId,
              vacationerName: String(bookingRequest.vacationerName ?? ""),
              vacationerEmail: String(bookingRequest.vacationerEmail ?? ""),
              accommodationTitle: String(accommodation.itemName ?? ""),
              checkInDate: String(bookingRequest.checkInDate), checkOutDate: String(bookingRequest.checkOutDate),
              numberOfGuests: adults + children + babies, reservationStatus: "confirmed", paymentStatus: "pending",
              totalPrice: Number.isFinite(totalPrice) ? totalPrice : 0, bookingDateTime,
            } } }),
          });
          if (!insertedReservation.dataItem?.id && !insertedReservation.dataItem?.data?._id) {
            return response({ error: "Wix n’a pas confirmé la création de la réservation." }, 502);
          }
        }

        const calendarEntries = await queryAll("seasonalcalendars", { bookingRequestId: { $eq: requestId } }, [
          "linkedEntityId", "bookingRequestId", "availabilityStatus",
        ], token);
        if (nextStatus === "accepted") {
          for (const entry of calendarEntries) {
            const calendarId = String(entry._id ?? "");
            if (!calendarId || String(entry.linkedEntityId ?? "") !== accommodationId) continue;
            await wixRequest(`/wix-data/v2/items/${encodeURIComponent(calendarId)}`, token, {
              method: "PATCH", body: JSON.stringify({ dataCollectionId: "seasonalcalendars", patch: {
                dataItemId: calendarId,
                fieldModifications: [{ fieldPath: "availabilityStatus", action: "SET_FIELD", setFieldOptions: { value: "reserved" } }],
              } }),
            });
          }
        }
        if (currentStatus !== nextStatus) {
          await wixRequest(`/wix-data/v2/items/${encodeURIComponent(requestId)}`, token, {
            method: "PATCH", body: JSON.stringify({ dataCollectionId: "seasonalbookingrequests", patch: {
              dataItemId: requestId,
              fieldModifications: [{ fieldPath: "status", action: "SET_FIELD", setFieldOptions: { value: nextStatus } }],
            } }),
          });
        }
        if (nextStatus === "rejected") {
          for (const entry of calendarEntries) {
            const calendarId = String(entry._id ?? "");
            if (!calendarId || String(entry.linkedEntityId ?? "") !== accommodationId) continue;
            await wixRequest(`/wix-data/v2/items/${encodeURIComponent(calendarId)}`, token, {
              method: "PATCH", body: JSON.stringify({ dataCollectionId: "seasonalcalendars", patch: {
                dataItemId: calendarId,
                fieldModifications: [
                  { fieldPath: "availabilityStatus", action: "SET_FIELD", setFieldOptions: { value: "available" } },
                  { fieldPath: "bookingRequestId", action: "SET_FIELD", setFieldOptions: { value: "" } },
                ],
              } }),
            });
          }
        }

        let emailSent = false;
        if (currentStatus !== nextStatus && vacationerId) {
          try {
            const privateProfile = first(await query("privateprofiles", { ownerId: { $eq: vacationerId } }, ["email", "firstName", "lastName"], token, 2));
            const recipientEmail = String(privateProfile?.email ?? "").trim();
            if (recipientEmail.includes("@")) {
              const emailResponse = await fetch("https://www.partenairefoyer.com/api/send-seasonal-email", {
                method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" },
                body: JSON.stringify({
                  eventType: nextStatus === "accepted" ? "booking_accepted" : "booking_rejected",
                  toEmail: recipientEmail,
                  recipientName: [privateProfile?.firstName, privateProfile?.lastName].filter(Boolean).join(" ") || "Vacancier",
                  accommodationName: String(accommodation.itemName ?? "l’hébergement"),
                  checkInDate: String(bookingRequest.checkInDate), checkOutDate: String(bookingRequest.checkOutDate),
                }),
                signal: AbortSignal.timeout(12_000),
              });
              emailSent = emailResponse.ok;
            }
          } catch (error) {
            console.warn("[ios-native-dashboard] Seasonal booking e-mail unavailable", error);
          }
        }
        return response({ success: true, requestId, status: nextStatus, emailSent });
      }

      if (body.action === "save_seasonal_calendar_dates") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const accommodationId = String(body.accommodationId ?? "").trim();
        const status = String(body.availabilityStatus ?? "").trim().toLowerCase();
        const dates = Array.isArray(body.dates) ? body.dates.map((value) => String(value ?? "").trim()) : [];
        const pricePerNight = body.pricePerNight == null || body.pricePerNight === "" ? null : Number(body.pricePerNight);
        const minimumStay = body.minimumStay == null || body.minimumStay === "" ? null : Number(body.minimumStay);
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(accommodationId) || !["available", "blocked"].includes(status) ||
            dates.length < 1 || dates.length > 31 || new Set(dates).size !== dates.length ||
            dates.some((value) => {
              if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return true;
              const date = new Date(`${value}T00:00:00.000Z`);
              return Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== value;
            }) || (pricePerNight != null && (!Number.isFinite(pricePerNight) || pricePerNight < 0 || pricePerNight > 100_000)) ||
            (minimumStay != null && (!Number.isInteger(minimumStay) || minimumStay < 1 || minimumStay > 365))) {
          return response({ error: "Vérifiez les dates, le tarif et le séjour minimum." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        if (!accommodations.some((item) => String(item._id ?? item.id ?? "") === accommodationId)) {
          return response({ error: "Cet hébergement n’appartient pas à votre espace." }, 403);
        }
        const allCalendar = await queryAll("seasonalcalendars", { linkedEntityId: { $eq: accommodationId } }, [
          "linkedEntityId", "calendarDate", "availabilityStatus", "bookingRequestId", "pricePerNight", "minimumStay",
        ], token);
        const reservations = (dashboard?.reservations as Record<string, unknown>[] | undefined) ?? [];
        const externalBookings = (dashboard?.externalBookings as Record<string, unknown>[] | undefined) ?? [];
        const updates: { date: string; calendarId?: string }[] = [];
        for (const date of dates) {
          const entry = allCalendar.find((item) => String(item.calendarDate ?? "").slice(0, 10) === date);
          const reserved = reservations.some((item) =>
            String(item.accommodationId ?? "") === accommodationId && String(item.reservationStatus ?? "").toLowerCase() === "confirmed" &&
            String(item.checkInDate ?? "").slice(0, 10) <= date && String(item.checkOutDate ?? "").slice(0, 10) > date
          );
          const statusValue = String(entry?.availabilityStatus ?? "").toLowerCase();
          const external = externalBookings.some((item) =>
            String(item.accommodationId ?? "") === accommodationId &&
            String(item.startDate ?? "").slice(0, 10) <= date && String(item.endDate ?? "").slice(0, 10) > date
          );
          if (reserved || external || statusValue === "reserved" || statusValue === "booked" || statusValue === "external" || statusValue === "pending") {
            return response({ error: `La date ${date} est déjà réservée ou liée à une demande.` }, 409);
          }
          updates.push({ date, ...(entry?._id ? { calendarId: String(entry._id) } : {}) });
        }
        for (const update of updates) {
          if (update.calendarId) {
            const fields: Record<string, unknown> = { availabilityStatus: status };
            if (pricePerNight !== null) fields.pricePerNight = pricePerNight;
            if (minimumStay !== null) fields.minimumStay = minimumStay;
            await wixRequest(`/wix-data/v2/items/${encodeURIComponent(update.calendarId)}`, token, {
              method: "PATCH", body: JSON.stringify({ dataCollectionId: "seasonalcalendars", patch: {
                dataItemId: update.calendarId,
                fieldModifications: Object.entries(fields).map(([fieldPath, value]) => ({ fieldPath, action: "SET_FIELD", setFieldOptions: { value } })),
              } }),
            });
          } else {
            const data: Record<string, unknown> = {
              linkedEntityId: accommodationId, linkedEntityType: "accommodation",
              calendarDate: `${update.date}T00:00:00.000Z`, availabilityStatus: status,
            };
            if (pricePerNight !== null) data.pricePerNight = pricePerNight;
            if (minimumStay !== null) data.minimumStay = minimumStay;
            const inserted = await wixRequest<{ dataItem?: WixItem }>("/wix-data/v2/items", token, {
              method: "POST", body: JSON.stringify({ dataCollectionId: "seasonalcalendars", dataItem: { data } }),
            });
            if (!inserted.dataItem?.id && !inserted.dataItem?.data?._id) return response({ error: `Wix n’a pas confirmé la date ${update.date}.` }, 502);
          }
        }
        return response({ success: true, accommodationId, updatedDates: updates.map(({ date }) => date) });
      }

      if (body.action === "save_seasonal_rate") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const accommodationId = String(body.accommodationId ?? "").trim();
        const rateId = String(body.rateId ?? "").trim();
        const seasonName = String(body.seasonName ?? "").trim();
        const startDate = String(body.startDate ?? "").trim();
        const endDate = String(body.endDate ?? "").trim();
        const pricePerNight = Number(body.pricePerNight);
        const minimumStayNights = Number(body.minimumStayNights);
        const dateIsValid = (value: string) => {
          if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
          const date = new Date(`${value}T00:00:00.000Z`);
          return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value;
        };
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(accommodationId) ||
            (rateId && !/^[A-Za-z0-9_-]{1,160}$/.test(rateId)) ||
            seasonName.length < 2 || seasonName.length > 80 ||
            !dateIsValid(startDate) || !dateIsValid(endDate) || startDate > endDate ||
            !Number.isFinite(pricePerNight) || pricePerNight <= 0 || pricePerNight > 100_000 ||
            !Number.isInteger(minimumStayNights) || minimumStayNights < 1 || minimumStayNights > 365) {
          return response({ error: "Vérifiez le nom, les dates et les critères du tarif." }, 400);
        }

        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        if (!accommodations.some((item) => String(item._id ?? item.id ?? "") === accommodationId)) {
          return response({ error: "Cet hébergement n’appartient pas à votre espace." }, 403);
        }
        const data = { accommodationId, seasonName, startDate, endDate, pricePerNight, minimumStayNights };
        const rates = (dashboard?.seasonalRates as Record<string, unknown>[] | undefined) ?? [];
        const overlappingRate = rates.find((item) => {
          if (String(item.accommodationId ?? "") !== accommodationId || String(item._id ?? item.id ?? "") === rateId) return false;
          const existingStart = String(item.startDate ?? "").slice(0, 10);
          const existingEnd = String(item.endDate ?? "").slice(0, 10);
          return existingStart && existingEnd && startDate <= existingEnd && endDate >= existingStart;
        });
        if (overlappingRate) return response({ error: "Cette période chevauche déjà un autre tarif de cet hébergement." }, 409);
        if (rateId) {
          const current = rates.find((item) => String(item._id ?? item.id ?? "") === rateId);
          if (!current || String(current.accommodationId ?? "") !== accommodationId) {
            return response({ error: "Ce tarif n’est pas associé à cet hébergement." }, 403);
          }
          await wixRequest(`/wix-data/v2/items/${encodeURIComponent(rateId)}`, token, {
            method: "PATCH",
            body: JSON.stringify({ dataCollectionId: "seasonalrates", patch: {
              dataItemId: rateId,
              fieldModifications: Object.entries(data).map(([fieldPath, value]) => ({
                fieldPath, action: "SET_FIELD", setFieldOptions: { value },
              })),
            } }),
          });
          return response({ success: true, rateId, accommodationId });
        }
        const inserted = await wixRequest<{ dataItem?: WixItem }>("/wix-data/v2/items", token, {
          method: "POST",
          body: JSON.stringify({ dataCollectionId: "seasonalrates", dataItem: { data } }),
        });
        const createdId = String(inserted.dataItem?.id ?? inserted.dataItem?.data?._id ?? "");
        if (!createdId) return response({ error: "Wix n’a pas confirmé la création du tarif." }, 502);
        return response({ success: true, rateId: createdId, accommodationId });
      }

      if (body.action === "save_host_accommodation") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const accommodationId = String(body.accommodationId ?? "").trim();
        const itemName = String(body.itemName ?? "").trim();
        const itemDescription = String(body.itemDescription ?? "").trim();
        const accommodationType = String(body.accommodationType ?? "").trim();
        const locationAddress = String(body.locationAddress ?? "").trim();
        const city = String(body.city ?? "").trim();
        const postalCode = String(body.postalCode ?? "").trim();
        const maxGuests = Number(body.maxGuests);
        const numberOfBedrooms = Number(body.numberOfBedrooms);
        const itemPrice = Number(body.itemPrice);
        const latitude = body.latitude === undefined || body.latitude === null || body.latitude === "" ? undefined : Number(body.latitude);
        const longitude = body.longitude === undefined || body.longitude === null || body.longitude === "" ? undefined : Number(body.longitude);
        const amenities = String(body.amenities ?? "").trim();
        const slug = String(body.slug ?? "").trim().toLowerCase();
        const checkInMode = String(body.checkInMode ?? "FLEXIBLE").trim().toUpperCase();
        const checkInTime = String(body.checkInTime ?? "15:00").trim();
        const checkInUntil = String(body.checkInUntil ?? "20:00").trim();
        const accessMethod = String(body.accessMethod ?? "HOST").trim().toUpperCase();
        const arrivalInstructions = String(body.arrivalInstructions ?? "").trim();
        const accommodationPhotoKeys = ["itemImage", ...Array.from({ length: 30 }, (_, index) => `photo${index + 1}`),
          "galleryImage2", "galleryImage3", "galleryImage4", "galleryImage5"];
        const requestedPhotos = body.photos;
        if (requestedPhotos !== undefined && (!Array.isArray(requestedPhotos) ||
            requestedPhotos.length > accommodationPhotoKeys.length ||
            requestedPhotos.some((photo) => typeof photo !== "string" || !photo.trim() || photo.length > 2048) ||
            new Set(requestedPhotos).size !== requestedPhotos.length)) {
          return response({ error: "La sélection de photos est invalide." }, 400);
        }
        const typeOptions = new Set(["apartment", "house", "villa", "cottage", "studio", "room"]);
        const timeIsValid = (value: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
        if ((accommodationId && !/^[A-Za-z0-9_-]{1,160}$/.test(accommodationId)) ||
            itemName.length < 2 || itemName.length > 140 || itemDescription.length < 1 || itemDescription.length > 8000 ||
            !typeOptions.has(accommodationType) || locationAddress.length < 4 || locationAddress.length > 250 ||
            city.length < 2 || city.length > 100 || !/^\d{4,10}$/.test(postalCode) ||
            !Number.isInteger(maxGuests) || maxGuests < 1 || maxGuests > 100 ||
            !Number.isInteger(numberOfBedrooms) || numberOfBedrooms < 1 || numberOfBedrooms > 100 ||
            !Number.isFinite(itemPrice) || itemPrice < 0 || itemPrice > 100_000 || amenities.length > 2000 ||
            ((latitude === undefined) !== (longitude === undefined)) ||
            (latitude !== undefined && (!Number.isFinite(latitude) || latitude < -90 || latitude > 90)) ||
            (longitude !== undefined && (!Number.isFinite(longitude) || longitude < -180 || longitude > 180)) ||
            (slug && !/^[a-z0-9-]{2,120}$/.test(slug)) ||
            !["FLEXIBLE", "FROM_TIME", "TIME_WINDOW", "BY_AGREEMENT"].includes(checkInMode) || !timeIsValid(checkInTime) || !timeIsValid(checkInUntil) ||
            !["HOST", "LOCKBOX", "SMART_LOCK", "RECEPTION", "KEY_PICKUP", "OTHER"].includes(accessMethod) || arrivalInstructions.length > 3000) {
          return response({ error: "Vérifiez les informations de l’hébergement, la capacité, le prix et les horaires d’arrivée." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const profile = dashboard?.profile as Record<string, unknown> | null | undefined;
        const hostId = String(profile?._id ?? "");
        if (!hostId) return response({ error: "Aucun profil hébergeur n’est associé à ce compte." }, 403);
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        const data: Record<string, unknown> = {
          itemName, itemDescription, accommodationType, locationAddress, city, postalCode,
          maxGuests, numberOfBedrooms, itemPrice, amenities, slug: slug || itemName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 120),
          checkInMode, checkInTime, checkInUntil, accessMethod, arrivalInstructions,
        };
        if (latitude !== undefined && longitude !== undefined) {
          data.latitude = latitude;
          data.longitude = longitude;
        }
        let ownedAccommodation: Record<string, unknown> | undefined;
        if (accommodationId) {
          ownedAccommodation = accommodations.find((item) => String(item._id ?? item.id ?? "") === accommodationId);
          if (!ownedAccommodation || String(ownedAccommodation.hostId ?? "") !== hostId) {
            return response({ error: "Cet hébergement n’appartient pas à votre espace." }, 403);
          }
        }
        if (Array.isArray(requestedPhotos)) {
          const existingPhotos = new Set(accommodationPhotoKeys
            .map((key) => ownedAccommodation?.[key])
            .filter((photo): photo is string => typeof photo === "string" && photo.length > 0));
          const supabaseURL = String(Deno.env.get("SUPABASE_URL") ?? "");
          if (requestedPhotos.some((photo) => !existingPhotos.has(photo as string) &&
              !ownedListingPhotos([photo], role, result.member.id, supabaseURL))) {
            return response({ error: "Une photo ne provient pas de cet hébergement ou de votre sélection sécurisée." }, 400);
          }
          accommodationPhotoKeys.forEach((key, index) => { data[key] = String(requestedPhotos[index] ?? ""); });
        }
        if (accommodationId) {
          await wixRequest(`/wix-data/v2/items/${encodeURIComponent(accommodationId)}`, token, {
            method: "PATCH", body: JSON.stringify({ dataCollectionId: "seasonalaccommodations", patch: {
              dataItemId: accommodationId,
              fieldModifications: Object.entries(data).map(([fieldPath, value]) => ({ fieldPath, action: "SET_FIELD", setFieldOptions: { value } })),
            } }),
          });
          return response({ success: true, accommodationId });
        }
        const status = String(body.status ?? "draft").trim().toLowerCase();
        if (!["draft", "pending"].includes(status)) return response({ error: "Choisissez un brouillon ou une demande de validation." }, 400);
        const inserted = await wixRequest<{ dataItem?: WixItem }>("/wix-data/v2/items", token, {
          method: "POST", body: JSON.stringify({ dataCollectionId: "seasonalaccommodations", dataItem: { data: { ...data, hostId, status } } }),
        });
        const createdId = String(inserted.dataItem?.id ?? inserted.dataItem?.data?._id ?? "");
        if (!createdId) return response({ error: "Wix n’a pas confirmé la création de l’hébergement." }, 502);
        return response({ success: true, accommodationId: createdId });
      }

      if (body.action === "delete_host_accommodation") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const accommodationId = String(body.accommodationId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(accommodationId)) return response({ error: "Hébergement invalide." }, 400);
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        if (!accommodations.some((item) => String(item._id ?? item.id ?? "") === accommodationId)) {
          return response({ error: "Cet hébergement n’appartient pas à votre espace." }, 403);
        }
        const [requests, reservations, rates, calendar] = await Promise.all([
          queryAll("seasonalbookingrequests", { accommodationId: { $eq: accommodationId } }, ["status"], token),
          queryAll("seasonalreservations", { accommodationId: { $eq: accommodationId } }, ["reservationStatus"], token),
          queryAll("seasonalrates", { accommodationId: { $eq: accommodationId } }, [], token),
          queryAll("seasonalcalendars", { linkedEntityId: { $eq: accommodationId } }, [], token),
        ]);
        if (requests.length || reservations.length || rates.length || calendar.length) {
          return response({ error: "Cet hébergement contient des demandes, réservations ou réglages de calendrier. Supprimez ou traitez-les d’abord depuis votre espace." }, 409);
        }
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(accommodationId)}?dataCollectionId=seasonalaccommodations`, token, { method: "DELETE" });
        return response({ success: true, accommodationId });
      }

      if (body.action === "delete_seasonal_rate") {
        if (role !== "hebergeur") return response({ error: "Cette action est réservée à l’espace hébergeur." }, 403);
        const rateId = String(body.rateId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(rateId)) return response({ error: "Tarif saisonnier invalide." }, 400);
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const rates = (dashboard?.seasonalRates as Record<string, unknown>[] | undefined) ?? [];
        const rate = rates.find((item) => String(item._id ?? item.id ?? "") === rateId);
        if (!rate) return response({ error: "Ce tarif n’appartient pas à votre espace." }, 404);
        const accommodations = (dashboard?.accommodations as Record<string, unknown>[] | undefined) ?? [];
        if (!accommodations.some((item) => String(item._id ?? item.id ?? "") === String(rate.accommodationId ?? ""))) {
          return response({ error: "Ce tarif n’est lié à aucun de vos hébergements." }, 403);
        }
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(rateId)}?dataCollectionId=seasonalrates`, token, {
          method: "DELETE",
        });
        return response({ success: true, rateId });
      }

      if (body.action === "mark_minisite_request_processed") {
        if (role !== "professionnel") return response({ error: "Cette action est réservée à l’espace professionnel." }, 403);
        const requestId = String(body.requestId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(requestId)) return response({ error: "Demande mini-site invalide." }, 400);
        const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive"], token, 2));
        if (!account || account.isActive === false) return response({ error: "Aucun compte professionnel actif n’est associé à cette adresse." }, 403);
        const nativeProfile = first(await query("prosprofiles", { accountId: { $eq: String(account._id ?? "") } }, ["accountId", "isActive"], token, 2));
        const legacyProfile = first(await query("professionnels", { memberId: { $eq: result.member.id } }, ["memberId"], token, 2));
        const professionalId = String(legacyProfile?._id ?? nativeProfile?._id ?? "");
        const owned = first(await query("demandesminisite", {
          _id: { $eq: requestId }, professionalId: { $eq: professionalId },
        }, ["professionalId", "status"], token, 2));
        if (!owned) return response({ error: "Cette demande mini-site n’appartient pas à votre espace." }, 404);
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(requestId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({ dataCollectionId: "demandesminisite", patch: { dataItemId: requestId, fieldModifications: [
            { fieldPath: "status", action: "SET_FIELD", setFieldOptions: { value: "processed" } },
          ] } }),
        });
        return response({ success: true, requestId, status: "processed" });
      }

      if (body.action === "delete_minisite_request") {
        if (role !== "professionnel") return response({ error: "Cette action est réservée à l’espace professionnel." }, 403);
        const requestId = String(body.requestId ?? "").trim();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(requestId)) return response({ error: "Demande mini-site invalide." }, 400);
        const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive"], token, 2));
        if (!account || account.isActive === false) return response({ error: "Aucun compte professionnel actif n’est associé à cette adresse." }, 403);
        const nativeProfile = first(await query("prosprofiles", { accountId: { $eq: String(account._id ?? "") } }, ["accountId", "isActive"], token, 2));
        const legacyProfile = first(await query("professionnels", { memberId: { $eq: result.member.id } }, ["memberId"], token, 2));
        const professionalId = String(legacyProfile?._id ?? nativeProfile?._id ?? "");
        if (!professionalId) return response({ error: "Aucune fiche professionnelle liée à cette session." }, 403);
        const owned = first(await query("demandesminisite", {
          _id: { $eq: requestId }, professionalId: { $eq: professionalId },
        }, ["professionalId"], token, 2));
        if (!owned) return response({ error: "Cette demande mini-site n’appartient pas à votre espace." }, 404);
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(requestId)}?dataCollectionId=demandesminisite`, token, {
          method: "DELETE",
        });
        return response({ success: true, requestId, deleted: true });
      }

      if (body.action === "upload_listing_photo") {
        if (!["particulier", "professionnel", "hebergeur"].includes(role)) {
          return response({ error: "L’ajout de photos est réservé aux espaces compatibles." }, 403);
        }
        if (role === "hebergeur") {
          const profile = first(await query("seasonalhostprofiles", emailFilter(email), ["email", "isVerified"], token, 2));
          if (!profile) return response({ error: "Aucun profil hébergeur n’est associé à cette adresse." }, 403);
        } else {
          const accountCollection = role === "particulier" ? "privateaccounts" : "prosaccounts";
          const profileCollection = role === "particulier" ? "privateprofiles" : "prosprofiles";
          const account = first(await query(accountCollection, emailFilter(email), ["email", "isActive"], token, 2));
          if (!account || account.isActive === false) return response({ error: "Aucun compte actif n’est associé à cette adresse." }, 403);
          const accountID = String(account._id ?? "");
          const profileFilter = role === "particulier" ? { ownerId: { $eq: accountID } } : { accountId: { $eq: accountID } };
          const profile = first(await query(profileCollection, profileFilter, ["ownerId", "accountId", "isActive"], token, 2));
          if (!profile || profile.isActive === false) return response({ error: "Aucun profil actif n’a été trouvé pour cet espace." }, 403);
        }

        const mimeType = String(body.mimeType ?? "");
        const encoded = String(body.contentBase64 ?? "");
        if (mimeType !== "image/jpeg" || !encoded || encoded.length > 4_300_000) {
          return response({ error: "Choisissez une photo JPEG de moins de 3 Mo." }, 400);
        }
        let bytes: Uint8Array;
        try {
          const binary = atob(encoded);
          bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
        } catch {
          return response({ error: "Le fichier photo est illisible." }, 400);
        }
        if (bytes.length === 0 || bytes.length > 3 * 1024 * 1024) {
          return response({ error: "La photo dépasse la taille maximale de 3 Mo." }, 400);
        }
        const supabaseURL = String(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
        const secretKey = getSupabaseSecretKey();
        if (!supabaseURL || !secretKey) return response({ error: "Le stockage photo de l’application n’est pas configuré." }, 503);
        const filePath = `${role}/${encodeURIComponent(result.member.id)}/${crypto.randomUUID()}.jpg`;
        const upload = await fetch(`${supabaseURL}/storage/v1/object/${listingPhotoBucket}/${filePath}`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${secretKey}`,
            apikey: secretKey,
            "Content-Type": mimeType,
            "Cache-Control": "public, max-age=31536000, immutable",
            "x-upsert": "false",
          },
          body: bytes,
        });
        if (!upload.ok) {
          console.error("[ios-native-dashboard] Listing photo upload failed", upload.status);
          return response({ error: "La photo n’a pas pu être enregistrée. Réessayez." }, 502);
        }
        return response({
          success: true,
          url: `${supabaseURL}/storage/v1/object/public/${listingPhotoBucket}/${filePath}`,
          sizeInBytes: bytes.length,
        });
      }

      if (body.action === "create_private_property" || body.action === "create_classified_ad") {
        if (role !== "particulier") return response({ error: "Cette action est réservée à l’espace particulier." }, 403);
        const account = first(await query("privateaccounts", emailFilter(email), ["email", "isActive"], token, 2));
        if (!account || account.isActive === false) return response({ error: "Aucun compte particulier actif n’est associé à cette adresse." }, 403);
        const accountID = String(account._id ?? "");
        const profile = first(await query("privateprofiles", { ownerId: { $eq: accountID } }, ["ownerId", "email"], token, 2));
        if (!profile) return response({ error: "Votre profil particulier doit être complété avant de publier." }, 403);

        const now = new Date().toISOString();
        if (body.action === "create_private_property") {
          const title = String(body.title ?? "").trim().slice(0, 140);
          const description = String(body.description ?? "").trim().slice(0, 8000);
          const propertyType = String(body.propertyType ?? "").trim().slice(0, 60);
          const transactionType = String(body.transactionType ?? "");
          const city = String(body.city ?? "").trim().slice(0, 100);
          const postalCode = String(body.postalCode ?? "").trim().slice(0, 10);
          const price = Number(body.price);
          const surface = Number(body.surface);
          const landSurface = body.landSurface === undefined || body.landSurface === null || body.landSurface === ""
            ? undefined : Number(body.landSurface);
          const rooms = Number(body.rooms);
          const bedrooms = Number(body.bedrooms ?? 0);
          const bathrooms = Number(body.bathrooms ?? 0);
          const supabaseURL = String(Deno.env.get("SUPABASE_URL") ?? "");
          const photos = ownedListingPhotos(body.photos, role, result.member.id, supabaseURL);
          if (!photos) return response({ error: "Une photo ne provient pas de votre sélection d’images sécurisée." }, 400);
          if (title.length < 5 || description.length < 20 || propertyType.length < 2 ||
              !["vente", "location"].includes(transactionType) || city.length < 2 ||
              !/^\d{4,10}$/.test(postalCode) || !Number.isFinite(price) || price < 0 ||
              !Number.isFinite(surface) || surface <= 0 ||
              (landSurface !== undefined && (!Number.isFinite(landSurface) || landSurface < 0)) ||
              !Number.isInteger(rooms) || rooms < 1 || !Number.isInteger(bedrooms) || bedrooms < 0 ||
              !Number.isInteger(bathrooms) || bathrooms < 0) {
            return response({ error: "Vérifiez le titre, la description, la localisation et les caractéristiques du bien." }, 400);
          }
          const data: Record<string, unknown> = {
            ownerId: accountID, title, description, propertyType, transactionType, sellingPrice: price, surface,
            rooms, bedrooms, bathrooms, city, postalCode, isPublic: body.publishImmediately === true,
            status: "active", createdAt: now, updatedAt: now,
          };
          if (landSurface !== undefined) data.landSurface = landSurface;
          if (photos.length > 0) {
            data.mainImage = photos[0];
            data.photo1 = photos[0];
            photos.slice(1, 8).forEach((photo, index) => { data[`photo${index + 2}`] = photo; });
            data.galleryImages = JSON.stringify(photos);
          }
          const inserted = await wixRequest<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, {
            method: "POST",
            body: JSON.stringify({ dataCollectionId: "privateproperties", dataItem: { data } }),
          });
          if (!inserted.dataItem?.id) return response({ error: "Wix n’a pas confirmé l’enregistrement du bien." }, 502);
          return response({ success: true, propertyId: inserted.dataItem.id, status: data.status, isPublic: data.isPublic });
        }

        const itemName = String(body.itemName ?? "").trim().slice(0, 140);
        const itemDescription = String(body.itemDescription ?? "").trim().slice(0, 5000);
        const category = String(body.category ?? "").trim().slice(0, 100);
        const subcategory = String(body.subcategory ?? "").trim().slice(0, 100);
        const adListingType = String(body.adListingType ?? "sell");
        const itemCondition = String(body.itemCondition ?? "");
        const rentalUnit = String(body.rentalUnit ?? "day");
        const rawAttributes = body.attributes;
        const city = String(body.city ?? "").trim().slice(0, 100);
        const postalCode = String(body.postalCode ?? "").trim().slice(0, 10);
        const itemPrice = Number(body.itemPrice);
        const photos = ownedListingPhotos(body.photos, role, result.member.id, String(Deno.env.get("SUPABASE_URL") ?? ""));
        if (!photos) return response({ error: "Une photo ne provient pas de votre sélection d’images sécurisée." }, 400);
        const allowedConditions = new Set(["Neuf", "Comme neuf", "Très bon état", "Bon état", "État correct"]);
        if (itemName.length < 3 || itemDescription.length < 10 || category.length < 2 ||
            !["sell", "give", "exchange", "rent"].includes(adListingType) ||
            (adListingType === "rent" && !["hour", "day", "weekend", "week", "month"].includes(rentalUnit)) ||
            !allowedConditions.has(itemCondition) || city.length < 2 || !/^\d{4,10}$/.test(postalCode) ||
            !Number.isFinite(itemPrice) || itemPrice < 0) {
          return response({ error: "Vérifiez le titre, la description, la catégorie, l’état et la localisation de l’objet." }, 400);
        }
        const data: Record<string, unknown> = {
          ownerId: accountID, itemName, itemPrice, itemDescription, category, subcategory,
          adListingType, itemCondition, city, postalCode, status: "published", createdAt: now,
        };
        const attributes: Record<string, string> = {};
        if (rawAttributes !== undefined) {
          if (!rawAttributes || typeof rawAttributes !== "object" || Array.isArray(rawAttributes)) {
            return response({ error: "Les caractéristiques de l’annonce sont invalides." }, 400);
          }
          const entries = Object.entries(rawAttributes as Record<string, unknown>);
          if (entries.length > 80) return response({ error: "L’annonce contient trop de caractéristiques." }, 400);
          for (const [key, value] of entries) {
            if (!isAllowedClassifiedAttribute(key) || typeof value !== "string" || value.length > 300) {
              return response({ error: "Une caractéristique de l’annonce n’est pas autorisée." }, 400);
            }
            const clean = value.trim();
            if (clean) attributes[key] = clean;
          }
        }
        if (adListingType === "rent") attributes.rentalUnit = rentalUnit;
        if (Object.keys(attributes).length > 0) data.attributesJSON = JSON.stringify(attributes);
        if (photos.length > 0) {
          data.itemImage = photos[0];
          photos.slice(1).forEach((photo, index) => { data[`photo${index + 2}`] = photo; });
        }
        const inserted = await wixRequest<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, {
          method: "POST",
          body: JSON.stringify({ dataCollectionId: "classifiedads-1", dataItem: { data } }),
        });
        if (!inserted.dataItem?.id) return response({ error: "Wix n’a pas confirmé la publication de la petite annonce." }, 502);
        return response({ success: true, classifiedAdID: inserted.dataItem.id, status: data.status });
      }

      if (body.action === "create_professional_property") {
        if (role !== "professionnel") return response({ error: "Cette action est réservée à l’espace professionnel." }, 403);
        const title = String(body.title ?? "").trim().slice(0, 140);
        const description = String(body.description ?? "").trim().slice(0, 8000);
        const propertyType = String(body.propertyType ?? "");
        const transactionType = String(body.transactionType ?? "");
        const address = String(body.address ?? "").trim().slice(0, 240);
        const city = String(body.city ?? "").trim().slice(0, 100);
        const postalCode = String(body.postalCode ?? "").trim().slice(0, 10);
        const price = Number(body.price);
        const surface = Number(body.surface);
        const landSurface = body.landSurface === undefined || body.landSurface === null || body.landSurface === ""
          ? undefined : Number(body.landSurface);
        const rooms = Number(body.rooms);
        const bedrooms = Number(body.bedrooms ?? 0);
        const bathrooms = Number(body.bathrooms ?? 0);
        const photos = ownedListingPhotos(body.photos, role, result.member.id, String(Deno.env.get("SUPABASE_URL") ?? ""));
        if (!photos) return response({ error: "Une photo ne provient pas de votre sélection d’images sécurisée." }, 400);
        const allowedPropertyTypes = new Set([
          "house", "apartment", "maison", "appartement", "other", "commercial", "garage", "building", "land", "office",
        ]);
        if (title.length < 5 || description.length < 20 || !allowedPropertyTypes.has(propertyType) ||
            !["sale", "rent"].includes(transactionType) || address.length < 5 || city.length < 2 ||
            !/^\d{4,10}$/.test(postalCode) || !Number.isFinite(price) || price < 0 ||
            (landSurface !== undefined && (!Number.isFinite(landSurface) || landSurface < 0)) ||
            !Number.isFinite(surface) || surface <= 0 || !Number.isInteger(rooms) || rooms < 1 ||
            !Number.isInteger(bedrooms) || bedrooms < 0 || !Number.isInteger(bathrooms) || bathrooms < 0) {
          return response({ error: "Vérifiez le titre, la description, la localisation et les caractéristiques du bien." }, 400);
        }

        const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive"], token, 2));
        if (!account || account.isActive === false) return response({ error: "Aucun compte professionnel actif n’est associé à cette adresse." }, 403);
        const accountId = String(account._id ?? "");
        const profile = first(await query("prosprofiles", { accountId: { $eq: accountId } }, [
          "accountId", "companyName", "contactName", "phoneNumber", "email", "isActive",
        ], token, 2));
        if (!profile || profile.isActive === false) return response({ error: "Aucune fiche professionnelle active n’a été trouvée." }, 403);

        const now = new Date().toISOString();
        const data: Record<string, unknown> = {
          wixMemberId: result.member.id,
          professionalId: String(profile._id ?? ""),
          title,
          description,
          propertyType,
          transactionType,
          price,
          surface,
          rooms,
          bedrooms,
          bathrooms,
          address,
          city,
          postalCode,
          status: body.publishImmediately === true ? "active" : "inactive",
          createdAt: now,
          updatedAt: now,
        };
        if (landSurface !== undefined) {
          data.landSurface = landSurface;
          data.surfaceLand = landSurface;
        }
        if (photos.length > 0) {
          data.mainImageUrl = photos[0];
          data.galleryImages = JSON.stringify(photos);
          photos.slice(0, 5).forEach((photo, index) => { data[`photo${index + 1}`] = photo; });
        }
        const inserted = await wixRequest<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, {
          method: "POST",
          body: JSON.stringify({ dataCollectionId: "biensprofessionnels", dataItem: { data } }),
        });
        if (!inserted.dataItem?.id) return response({ error: "Wix n’a pas confirmé l’enregistrement du bien." }, 502);
        return response({ success: true, propertyId: inserted.dataItem.id, status: data.status });
      }
      if (body.action === "archive_listing") {
        const itemId = String(body.itemId ?? "").trim();
        const list = String(body.list ?? "");
        const allowed = role === "particulier"
          ? new Set(["properties", "classifieds"])
          : role === "professionnel"
            ? new Set(["properties"])
            : new Set<string>();
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(itemId) || !allowed.has(list)) {
          return response({ error: "Annonce invalide ou espace non autorisé." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const rows = (dashboard?.[list] as Record<string, unknown>[] | undefined) ?? [];
        const item = rows.find((entry) => String(entry._id ?? entry.id ?? "") === itemId);
        if (!item) return response({ error: "Cette annonce n’est pas associée à votre espace." }, 404);
        const collection = role === "professionnel"
          ? "biensprofessionnels"
          : list === "classifieds" ? "classifiedads-1" : "privateproperties";
        const modifications = list === "properties" && role === "particulier"
          ? [
            { fieldPath: "status", action: "SET_FIELD", setFieldOptions: { value: "archived" } },
            { fieldPath: "isPublic", action: "SET_FIELD", setFieldOptions: { value: false } },
            { fieldPath: "updatedAt", action: "SET_FIELD", setFieldOptions: { value: new Date().toISOString() } },
          ]
          : [
            { fieldPath: "status", action: "SET_FIELD", setFieldOptions: { value: "archived" } },
          ];
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(itemId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({
            dataCollectionId: collection,
            patch: { dataItemId: itemId, fieldModifications: modifications },
          }),
        });
        return response({ success: true, itemId, list, status: "archived" });
      }
      if (body.action === "update_listing") {
        const itemId = String(body.itemId ?? "").trim();
        const list = String(body.list ?? "");
        const allowed = role === "particulier"
          ? new Set(["properties", "classifieds"])
          : role === "professionnel"
            ? new Set(["properties"])
            : new Set<string>();
        const fields = body.fields;
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(itemId) || !allowed.has(list) || !fields || typeof fields !== "object" || Array.isArray(fields)) {
          return response({ error: "Annonce invalide ou espace non autorisé." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const rows = (dashboard?.[list] as Record<string, unknown>[] | undefined) ?? [];
        const ownedItem = rows.find((entry) => String(entry._id ?? entry.id ?? "") === itemId);
        if (!ownedItem) {
          return response({ error: "Cette annonce n’est pas associée à votre espace." }, 404);
        }
        const source = fields as Record<string, unknown>;
        const fieldRules: Record<string, "text" | "number" | "boolean"> = list === "classifieds"
          ? { itemName: "text", itemDescription: "text", category: "text", subcategory: "text", adListingType: "text", itemCondition: "text", city: "text", postalCode: "text", itemPrice: "number" }
          : role === "professionnel"
            ? { title: "text", description: "text", propertyType: "text", transactionType: "text", address: "text", city: "text", postalCode: "text", price: "number", surface: "number", landSurface: "number", surfaceLand: "number", rooms: "number", bedrooms: "number", bathrooms: "number", status: "text" }
            : { title: "text", description: "text", propertyType: "text", transactionType: "text", city: "text", postalCode: "text", sellingPrice: "number", surface: "number", landSurface: "number", rooms: "number", bedrooms: "number", bathrooms: "number", isPublic: "boolean" };
        const data: Record<string, unknown> = {};
        for (const [key, value] of Object.entries(source)) {
          if (key === "photos" || key === "rentalUnit" || key === "attributes") continue;
          const type = fieldRules[key];
          if (!type) return response({ error: "Un des champs à modifier n’est pas autorisé." }, 400);
          if (type === "text") {
            if (typeof value !== "string") return response({ error: "Vérifiez les champs texte de l’annonce." }, 400);
            data[key] = value.trim().slice(0, key.toLowerCase().includes("description") ? 8000 : 500);
          } else if (type === "number") {
            const number = Number(value);
            if (!Number.isFinite(number) || number < 0 || (["rooms"].includes(key) && (!Number.isInteger(number) || number < 1)) ||
                (["bedrooms", "bathrooms"].includes(key) && !Number.isInteger(number)) || (key === "surface" && number <= 0)) {
              return response({ error: "Vérifiez les chiffres de l’annonce." }, 400);
            }
            data[key] = number;
          } else {
            if (typeof value !== "boolean") return response({ error: "Vérifiez le choix de publication." }, 400);
            data[key] = value;
          }
        }
        if (list === "properties" && role === "professionnel" && data.landSurface !== undefined) {
          data.surfaceLand = data.landSurface;
        }
        if (source.photos !== undefined) {
          const maxPhotos = role === "professionnel" ? 5 : 20;
          if (!Array.isArray(source.photos) || source.photos.length > maxPhotos || source.photos.some((photo) => typeof photo !== "string" || !photo || photo.length > 2048)) {
            return response({ error: "La galerie de photos est invalide." }, 400);
          }
          const requestedPhotos = [...new Set(source.photos as string[])];
          const existingPhotos = new Set(listingPhotoURLs(ownedItem, list, role));
          for (const photo of requestedPhotos) {
            if (existingPhotos.has(photo)) continue;
            if (!ownedListingPhotos([photo], role, result.member.id, String(Deno.env.get("SUPABASE_URL") ?? ""))) {
              return response({ error: "Une photo ne provient pas de votre espace sécurisé." }, 400);
            }
          }
          if (list === "classifieds") {
            data.itemImage = requestedPhotos[0] ?? "";
            for (let index = 2; index <= 20; index++) data[`photo${index}`] = requestedPhotos[index - 1] ?? "";
          } else if (role === "professionnel") {
            data.mainImageUrl = requestedPhotos[0] ?? "";
            data.galleryImages = JSON.stringify(requestedPhotos);
            for (let index = 1; index <= 5; index++) data[`photo${index}`] = requestedPhotos[index - 1] ?? "";
          } else {
            data.mainImage = requestedPhotos[0] ?? "";
            data.galleryImages = JSON.stringify(requestedPhotos);
            for (let index = 1; index <= 20; index++) data[`photo${index}`] = requestedPhotos[index - 1] ?? "";
          }
        }
        if (list === "classifieds" && (source.rentalUnit !== undefined || source.attributes !== undefined)) {
          const listingType = String(data.adListingType ?? ownedItem.adListingType ?? "");
          const rentalUnit = typeof source.rentalUnit === "string" ? source.rentalUnit : "";
          const allowedRentalUnits = ["hour", "day", "weekend", "week", "month"];
          if (source.rentalUnit !== undefined && listingType === "rent" && !allowedRentalUnits.includes(rentalUnit)) {
            return response({ error: "Choisissez une périodicité valide pour le prix de location." }, 400);
          }
          let attributes: Record<string, unknown> = {};
          const originalAttributes = ownedItem.attributesJSON;
          if (typeof originalAttributes === "string") {
            try {
              const parsed = JSON.parse(originalAttributes) as unknown;
              if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) attributes = parsed as Record<string, unknown>;
            } catch { /* Start with an empty supported-attributes object when legacy JSON is malformed. */ }
          } else if (originalAttributes && typeof originalAttributes === "object" && !Array.isArray(originalAttributes)) {
            attributes = { ...(originalAttributes as Record<string, unknown>) };
          }
          if (source.attributes !== undefined) {
            if (!source.attributes || typeof source.attributes !== "object" || Array.isArray(source.attributes)) {
              return response({ error: "Les caractéristiques de l’annonce sont invalides." }, 400);
            }
            const entries = Object.entries(source.attributes as Record<string, unknown>);
            if (entries.length > 80) return response({ error: "L’annonce contient trop de caractéristiques." }, 400);
            for (const [key, value] of entries) {
              if (!isAllowedClassifiedAttribute(key) || typeof value !== "string" || value.length > 300) {
                return response({ error: "Une caractéristique de l’annonce n’est pas autorisée." }, 400);
              }
              const clean = value.trim();
              if (clean) attributes[key] = clean;
              else delete attributes[key];
            }
          }
          if (listingType === "rent" && source.rentalUnit !== undefined) attributes.rentalUnit = rentalUnit;
          else if (listingType !== "rent") delete attributes.rentalUnit;
          data.attributesJSON = JSON.stringify(attributes);
        }
        if (Object.keys(data).length === 0) return response({ error: "Aucune modification à enregistrer." }, 400);
        if (list === "properties" && role === "particulier") {
          if (data.transactionType !== undefined && !["vente", "location"].includes(String(data.transactionType))) return response({ error: "Type de transaction invalide." }, 400);
          if (data.title !== undefined && String(data.title).length < 5) return response({ error: "Le titre doit contenir au moins 5 caractères." }, 400);
          if (data.description !== undefined && String(data.description).length < 20) return response({ error: "La description doit contenir au moins 20 caractères." }, 400);
        } else if (list === "properties") {
          if (data.transactionType !== undefined && !["sale", "rent"].includes(String(data.transactionType))) return response({ error: "Type de transaction invalide." }, 400);
          if (data.status !== undefined && !["active", "inactive"].includes(String(data.status))) return response({ error: "Statut de publication invalide." }, 400);
          if (data.title !== undefined && String(data.title).length < 5) return response({ error: "Le titre doit contenir au moins 5 caractères." }, 400);
          if (data.description !== undefined && String(data.description).length < 20) return response({ error: "La description doit contenir au moins 20 caractères." }, 400);
          if (data.address !== undefined && String(data.address).length < 5) return response({ error: "L’adresse doit contenir au moins 5 caractères." }, 400);
        } else {
          if (data.adListingType !== undefined && !["sell", "give", "exchange", "rent"].includes(String(data.adListingType))) return response({ error: "Type de petite annonce invalide." }, 400);
          if (data.itemCondition !== undefined && !new Set(["Neuf", "Comme neuf", "Très bon état", "Bon état", "État correct"]).has(String(data.itemCondition))) return response({ error: "État de l’objet invalide." }, 400);
          if (data.itemName !== undefined && String(data.itemName).length < 3) return response({ error: "Le titre doit contenir au moins 3 caractères." }, 400);
          if (data.itemDescription !== undefined && String(data.itemDescription).length < 10) return response({ error: "La description doit contenir au moins 10 caractères." }, 400);
          if (data.category !== undefined && String(data.category).length < 2) return response({ error: "La catégorie doit contenir au moins 2 caractères." }, 400);
        }
        if (data.propertyType !== undefined && String(data.propertyType).length < 2) return response({ error: "Le type de bien doit contenir au moins 2 caractères." }, 400);
        if (data.city !== undefined && String(data.city).length < 2) return response({ error: "La ville doit contenir au moins 2 caractères." }, 400);
        if (data.postalCode !== undefined && !/^\d{4,10}$/.test(String(data.postalCode))) return response({ error: "Le code postal doit contenir entre 4 et 10 chiffres." }, 400);
        if (data.updatedAt === undefined && list === "properties" && role === "particulier") data.updatedAt = new Date().toISOString();
        const collection = list === "classifieds" ? "classifiedads-1" : role === "professionnel" ? "biensprofessionnels" : "privateproperties";
        const fieldModifications = Object.entries(data).map(([fieldPath, value]) => ({
          fieldPath, action: "SET_FIELD", setFieldOptions: { value },
        }));
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(itemId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({ dataCollectionId: collection, patch: { dataItemId: itemId, fieldModifications } }),
        });
        return response({ success: true, itemId, list });
      }
      if (body.action === "mark_matching_seen") {
        if (role !== "professionnel") return response({ error: "Cette action est réservée à l’espace professionnel." }, 403);
        const itemId = String(body.itemId ?? "").trim();
        const list = String(body.list ?? "");
        if (!/^[A-Za-z0-9_-]{1,160}$/.test(itemId) || !["matchings", "demands"].includes(list)) {
          return response({ error: "Élément de matching invalide." }, 400);
        }
        const dashboard = await loadDashboard(role, email, result.member.id, token);
        const rows = (dashboard?.[list] as Record<string, unknown>[] | undefined) ?? [];
        const item = rows.find((entry) => String(entry._id ?? entry.id ?? "") === itemId);
        if (!item) return response({ error: "Ce matching n’est pas associé à votre espace." }, 404);
        if (item.seen === true && (list !== "demands" || item.isViewed === true)) {
          return response({ success: true, alreadySeen: true, itemId });
        }
        const collection = list === "matchings" ? "matchings" : "demandespromatchings";
        const modifications = [{
          fieldPath: "seen",
          action: "SET_FIELD",
          setFieldOptions: { value: true },
        }];
        if (list === "demands") {
          modifications.push({
            fieldPath: "isViewed",
            action: "SET_FIELD",
            setFieldOptions: { value: true },
          });
        }
        await wixRequest(`/wix-data/v2/items/${encodeURIComponent(itemId)}`, token, {
          method: "PATCH",
          body: JSON.stringify({
            dataCollectionId: collection,
            patch: { dataItemId: itemId, fieldModifications: modifications },
          }),
        });
        return response({ success: true, itemId, list });
      }
      if (body.action !== "mark_inquiry_read" || !["courtier", "artisan", "diagnostiqueur", "prestataire"].includes(role)) {
        return response({ error: "Action de messagerie inconnue." }, 400);
      }
      const messageID = String(body.messageId ?? "").trim();
      if (!/^[A-Za-z0-9_-]{1,160}$/.test(messageID)) return response({ error: "Identifiant de message invalide." }, 400);
      const dashboard = await loadDashboard(role, email, result.member.id, token);
      const messages = (dashboard?.messages as Record<string, unknown>[] | undefined) ?? [];
      const message = messages.find((entry) => String(entry._id ?? entry.id ?? "") === messageID);
      if (!message) return response({ error: "Ce message n’est pas associé à votre espace." }, 404);
      if (message.isRead === true) return response({ success: true, alreadyRead: true });
      const collection = role === "courtier" ? "brokermessages" : "artisanmessages";
      await wixRequest(`/wix-data/v2/items/${encodeURIComponent(messageID)}`, token, {
        method: "PATCH",
        body: JSON.stringify({
          dataCollectionId: collection,
          patch: {
            dataItemId: messageID,
            fieldModifications: [{ fieldPath: "isRead", action: "SET_FIELD", setFieldOptions: { value: true } }],
          },
        }),
      });
      return response({ success: true, messageId: messageID });
    }
    const dashboard = await loadDashboard(role, email, result.member.id, token);
    if (!dashboard) return response({ error: "Aucun compte actif de ce type n’est associé à cette adresse e-mail." }, 403);
    return response({ success: true, member: { id: result.member.id, email }, dashboard });
  } catch (error) {
    console.error("[ios-native-dashboard]", error);
    return response({ error: "Impossible de charger cet espace. Réessayez." }, 502);
  }
});
