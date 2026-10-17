const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const WIX = "https://www.wixapis.com";

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

const first = (items: Record<string, unknown>[]) => items[0] ?? null;
const emailFilter = (email: string) => ({ email: { $eq: email } });

async function loadDashboard(role: string, email: string, memberID: string, token: string) {
  if (role === "particulier") {
    const account = first(await query("privateaccounts", emailFilter(email), ["email", "accountType", "isActive"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const [profiles, properties, classifieds, favorites, savedSearches, buyerMatchings] = await Promise.all([
      query("privateprofiles", { ownerId: { $eq: accountId } }, ["ownerId", "firstName", "lastName", "email", "phone", "city", "postalCode", "isProfileComplete"], token, 2),
      query("privateproperties", { ownerId: { $eq: accountId } }, ["ownerId", "title", "description", "propertyType", "transactionType", "price", "surface", "landSurface", "rooms", "bedrooms", "bathrooms", "city", "postalCode", "mainImage", "galleryImages", "isPublic", "status", "createdAt", "slug"], token),
      query("classifiedads-1", { ownerId: { $eq: accountId } }, [
        "ownerId", "itemName", "itemPrice", "itemDescription", "itemImage",
        "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8", "photo9", "photo10",
        "photo11", "photo12", "photo13", "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20",
        "category", "subcategory", "itemCondition", "city", "postalCode", "status", "createdAt",
      ], token),
      query("favoritelistings", { accountId: { $eq: accountId } }, ["accountId", "listingId", "sourceCollection", "createdAt", "isArchived"], token),
      query("particularbuyersearches", { accountId: { $eq: accountId }, isActive: { $eq: true } }, ["accountId", "searchName", "transactionType", "propertyTypes", "city", "postalCode", "radius", "minBudget", "maxBudget", "minSurface", "maxSurface", "minRooms", "minBedrooms", "emailAlertsEnabled", "createdAt", "updatedAt"], token),
      query("particularsearchmatchings", { buyerAccountId: { $eq: accountId } }, ["buyerAccountId", "searchId", "propertyId", "propertyTitle", "propertyCity", "propertyPrice", "propertySurface", "propertyUrl", "professionalId", "professionalName", "professionalEmail", "professionalPhone", "matchingScore", "status", "emailSentToBuyer", "createdAt", "notifiedAt"], token),
    ]);
    return { role, account: { id: accountId }, profile: first(profiles), properties, classifieds, favorites, savedSearches, buyerMatchings };
  }

  if (role === "professionnel") {
    const account = first(await query("prosaccounts", emailFilter(email), ["email", "isActive", "cguAccepted", "cgvAccepted"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profile = first(await query("prosprofiles", { accountId: { $eq: accountId } }, ["accountId", "companyName", "contactName", "phoneNumber", "email", "city", "postalCode", "professionalType", "category", "categories", "description", "logo", "photo", "website", "slug", "isActive", "isVisiblePublicly", "hasActiveSubscription", "subscriptionStatus", "subscriptionStartDate", "subscriptionEndDate"], token, 2));
    const accountSummary = {
      id: accountId,
      cguAccepted: account.cguAccepted === true,
      cgvAccepted: account.cgvAccepted === true,
    };
    if (!profile) return { role, account: accountSummary, profile: null, properties: [], matchings: [], messages: [] };
    const professionalId = String(profile._id ?? "");
    const [properties, matchings, demands, messages] = await Promise.all([
      // Public Wix listings are linked to the Wix member identity, not the
      // separate prosprofiles item ID. Using professionalId here returned an
      // empty property list for otherwise active professional accounts.
      query("biensprofessionnels", { wixMemberId: { $eq: memberID } }, ["wixMemberId", "professionalId", "title", "description", "propertyType", "transactionType", "price", "surface", "surfaceLand", "landSurface", "rooms", "bedrooms", "bathrooms", "city", "postalCode", "mainImageUrl", "galleryImages", "status", "commercialStatus", "updatedAt"], token),
      query("matchings", { professionalId: { $eq: professionalId } }, ["professionalId", "propertyId", "acquereurId", "matchingScore", "matchingType", "status", "seen", "createdAt"], token),
      query("demandespromatchings", { proId: { $eq: professionalId } }, ["proId", "demandId", "demandType", "postalCode", "status", "seen", "isViewed", "createdAt"], token),
      query("messages", { receiverId: { $eq: professionalId } }, ["conversationId", "senderId", "receiverId", "content", "createdAt", "isRead", "readAt"], token),
    ]);
    return { role, account: accountSummary, profile, properties, matchings, demands, messages };
  }

  if (role === "courtier") {
    const account = first(await query("brokeraccounts", emailFilter(email), ["email", "isActive", "cguAccepted", "cgvAccepted"], token, 2));
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profile = first(await query("brokerprofiles", { accountId: { $eq: accountId } }, ["accountId", "fullName", "professionalTitle", "profilePicture", "bio", "contactEmail", "phoneNumber", "city", "websiteUrl", "yearsOfExperience"], token, 2));
    const messages = profile ? await query("brokermessages", { brokerProfileId: { $eq: String(profile._id ?? "") } }, ["brokerProfileId", "senderName", "senderEmail", "senderPhone", "message", "isRead", "createdAt"], token) : [];
    return { role, account: { id: accountId, cguAccepted: account.cguAccepted === true, cgvAccepted: account.cgvAccepted === true }, profile, messages };
  }

  if (role === "prestataire" || role === "artisan" || role === "diagnostiqueur") {
    // Native registration uses the current suffixed collections for all service
    // provider roles. Keep the legacy collection as a read-only fallback for
    // existing Wix prestataire accounts.
    const accountFields = ["email", "isActive", "firstName", "lastName"];
    let account = first(await query("serviceprovideraccounts-1", emailFilter(email), accountFields, token, 2));
    if (!account) {
      account = first(await query("serviceprovideraccounts", emailFilter(email), accountFields, token, 2));
    }
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const providers = await query("serviceproviders-1", { accountId: { $eq: accountId } }, ["accountId", "businessName", "category", "subcategory", "description", "services", "city", "postalCode", "phone", "email", "website", "photoUrls", "status", "verified"], token, 3);
    const activity = (entry: Record<string, unknown>) => `${String(entry.category ?? "")} ${String(entry.subcategory ?? "")}`;
    const profile = providers.find((entry) => role === "artisan"
      ? /artisan/i.test(activity(entry)) && !/diagnostiqueur/i.test(activity(entry))
      : role === "diagnostiqueur"
        ? /diagnostiqueur/i.test(activity(entry))
        : !/artisan|diagnostiqueur/i.test(activity(entry))) ?? null;
    const messages = profile ? await query("artisanmessages", { artisanId: { $eq: String(profile._id ?? "") } }, ["artisanId", "senderName", "senderEmail", "messageContent", "createdAt", "isRead"], token) : [];
    return { role, account: { id: accountId }, profile, messages };
  }

  if (role === "hebergeur") {
    const profile = first(await query("seasonalhostprofiles", emailFilter(email), ["email", "fullName", "phoneNumber", "profilePicture", "biography", "isVerified"], token, 2));
    if (!profile) return null;
    return { role, profile };
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
