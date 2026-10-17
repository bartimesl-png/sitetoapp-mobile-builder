const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const WIX = "https://www.wixapis.com";

type WixItem = { id?: string; data?: Record<string, unknown>; [key: string]: unknown };
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});

async function wix<T>(path: string, token: string, method = "GET", body?: unknown): Promise<T> {
  const result = await fetch(`${WIX}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const raw = await result.text();
  if (!result.ok) throw new Error(`Wix API (${result.status})`);
  return (raw ? JSON.parse(raw) : {}) as T;
}

async function query(collection: string, filter: Record<string, unknown>, fields: string[], token: string, limit = 10) {
  const result = await wix<{ dataItems?: WixItem[] }>("/wix-data/v2/items/query", token, "POST", {
    dataCollectionId: collection,
    query: { filter, paging: { limit }, ...(fields.length ? { fields } : {}) },
  });
  return (result.dataItems ?? []).map((item) => {
    const data = item.data && typeof item.data === "object" ? item.data : item;
    return { ...data, _id: data._id ?? item.id ?? data.id } as Record<string, unknown>;
  });
}

async function queryAll(collection: string, filter: Record<string, unknown>, fields: string[], token: string) {
  const all: Record<string, unknown>[] = [];
  const limit = 100;
  let offset = 0;
  while (true) {
    const result = await wix<{ dataItems?: WixItem[]; pagingMetadata?: { offset?: number } }>("/wix-data/v2/items/query", token, "POST", {
      dataCollectionId: collection,
      query: { filter, paging: { limit, offset }, ...(fields.length ? { fields } : {}) },
    });
    const page = (result.dataItems ?? []).map((item) => {
      const data = item.data && typeof item.data === "object" ? item.data : item;
      return { ...data, _id: data._id ?? item.id ?? data.id } as Record<string, unknown>;
    });
    all.push(...page);
    if (page.length < limit) break;
    const nextOffset = Number(result.pagingMetadata?.offset ?? offset) + page.length;
    if (!Number.isFinite(nextOffset) || nextOffset <= offset) break;
    offset = nextOffset;
  }
  return all;
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function numeric(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function normalizePropertyType(value: unknown): string {
  const normalized = text(value, 100).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, "-").replace(/_/g, "-").replace(/-+/g, "-");
  const aliases: Record<string, string> = {
    house: "maison", home: "maison", apartment: "appartement", flat: "appartement", land: "terrain", plot: "terrain",
    building: "immeuble", commercial: "commerce", "commercial-property": "commerce", office: "bureau",
    "local-commercial": "commerce", parking: "garage", "garage-parking": "garage", "place-parking": "place-parking",
    mobilehome: "mobile-home", "holiday-home": "maison-vacances", "secondary-residence": "residence-secondaire",
    secondaryresidence: "residence-secondaire", castle: "chateau", chateaux: "chateau", farmhouse: "corps-ferme",
    "farm-house": "corps-ferme", farm: "corps-ferme", barn: "grange", outbuilding: "dependance", workshop: "atelier",
    warehouse: "hangar", "professional-premises": "local-professionnel", business: "fonds-commerce",
    "fonds-de-commerce": "fonds-commerce", room: "chambre", gite: "gite", seasonal: "bien-saisonnier",
    "terrain-de-loisirs": "terrain-loisirs",
  };
  return aliases[normalized] ?? normalized;
}

function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const radians = (value: number) => value * Math.PI / 180;
  const dLat = radians(lat2 - lat1), dLon = radians(lon2 - lon1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

// Mirrors calculateMatchingScore in Wix's particularSearchMatchingService.
function matchingScore(search: Record<string, unknown>, property: Record<string, unknown>): number {
  let score = 0, totalWeight = 0;
  const value = (key: string) => numeric(property[key]);
  const latitude = numeric(search.latitude), longitude = numeric(search.longitude);
  const propertyLatitude = value("latitude"), propertyLongitude = value("longitude");
  const radius = numeric(search.radius) ?? 50;
  if (propertyLatitude && propertyLongitude && latitude !== undefined && longitude !== undefined) {
    const distance = distanceKm(latitude, longitude, propertyLatitude, propertyLongitude);
    score += distance <= radius ? 30 : Math.max(0, 30 - ((distance - radius) / radius) * 30);
  }
  totalWeight += 30;
  const price = value("price");
  if (price) {
    const min = numeric(search.minBudget) ?? 0, max = numeric(search.maxBudget) || Infinity;
    if (price >= min && price <= max) score += 25;
    else if (price < min) score += Math.max(0, 25 - ((min - price) / min) * 25);
    else score += Math.max(0, 25 - ((price - max) / max) * 25);
  }
  totalWeight += 25;
  const surface = value("surface"), minSurface = numeric(search.minSurface), maxSurface = numeric(search.maxSurface);
  if (minSurface && surface) {
    score += surface >= minSurface ? 15 : Math.max(0, 15 - ((minSurface - surface) / minSurface) * 15);
    totalWeight += 15;
  }
  if (maxSurface && surface) {
    score += surface <= maxSurface ? 15 : Math.max(0, 15 - ((surface - maxSurface) / maxSurface) * 15);
    totalWeight += 15;
  }
  const land = value("landSurface"), minLand = numeric(search.minLandSurface), maxLand = numeric(search.maxLandSurface);
  if (minLand && land) {
    score += land >= minLand ? 10 : Math.max(0, 10 - ((minLand - land) / minLand) * 10);
    totalWeight += 10;
  }
  if (maxLand && land) {
    score += land <= maxLand ? 10 : Math.max(0, 10 - ((land - maxLand) / maxLand) * 10);
    totalWeight += 10;
  }
  const types = typeof search.propertyTypes === "string" ? search.propertyTypes.split(",").map((item) => item.trim()) : [];
  const propertyType = text(property.propertyType, 100);
  if (types.length && propertyType) {
    if (types.some((item) => normalizePropertyType(item) === normalizePropertyType(propertyType))) score += 10;
    totalWeight += 10;
  }
  let roomScore = 0, roomWeight = 0;
  for (const [criteria, field, weight] of [["minRooms", "rooms", 3], ["minBedrooms", "bedrooms", 3], ["minBathrooms", "bathrooms", 4]] as const) {
    const wanted = numeric(search[criteria]), actual = value(field);
    if (wanted && actual) {
      if (actual >= wanted) roomScore += weight;
      roomWeight += weight;
    }
  }
  if (roomWeight > 0) { score += (roomScore / roomWeight) * 10; totalWeight += 10; }
  let featureScore = 0;
  if (search.singleStory && property.hasGroundFloorBedroom) featureScore += 2;
  if (search.garage && property.hasGarage) featureScore += 2;
  if (search.garden && property.isLandFenced) featureScore += 2;
  if (search.terrace && property.hasAnnexe) featureScore += 2;
  if (search.pool && property.hasPiscine) featureScore += 2;
  score += featureScore;
  totalWeight += 10;
  return totalWeight > 0 ? Math.round(score / totalWeight * 100) : 0;
}

async function sendMatchingEmails(
  matchingId: string,
  matching: Record<string, unknown>,
  token: string,
): Promise<void> {
  const buyerEmail = text(matching.buyerEmail ?? matching.particulierEmail, 254);
  const professionalEmail = text(matching.professionalEmail, 254);
  if (!buyerEmail.includes("@") || !professionalEmail.includes("@")) return;
  const propertyUrl = text(matching.propertyUrl, 1000) || `https://www.partenairefoyer.com/annonce/${matchingId}`;
  const common = {
    searchName: text(matching.propertyTitle, 200), propertyTitle: text(matching.propertyTitle, 200),
    propertyCity: text(matching.propertyCity, 120), propertyPostalCode: text(matching.propertyPostalCode, 12),
    propertyPrice: String(matching.propertyPrice ?? ""), propertySurface: String(matching.propertySurface ?? ""),
    matchingScore: String(Math.round(numeric(matching.matchingScore) ?? 0)), propertyUrl, annonceUrl: propertyUrl,
    professionalName: text(matching.professionalName, 200), professionalEmail, professionalPhone: text(matching.professionalPhone, 60),
    siteName: "Immobilier Particulier",
  };
  const deliveries = [
    { email: buyerEmail, field: "emailSentToBuyer", alreadySent: matching.emailSentToBuyer === true,
      params: { ...common, firstName: text(matching.buyerFirstName ?? matching.particulierFirstName, 80) || "Particulier" } },
    { email: professionalEmail, field: "emailSentToProfessional", alreadySent: matching.emailSentToProfessional === true,
      params: { ...common, firstName: text(matching.professionalFirstName, 80) || text(matching.professionalName, 200).split(" ")[0] || "Professionnel" } },
  ];
  const results = await Promise.all(deliveries.map(async (delivery) => {
    if (delivery.alreadySent || !delivery.email.includes("@")) return delivery.alreadySent;
    try {
      const result = await fetch("https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-brevo-email", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          to: [{ email: delivery.email }],
          sender: { name: "PartenaireFoyer", email: "contact@partenairefoyer.com" },
          templateId: 19, params: delivery.params,
        }),
      });
      return result.ok;
    } catch { return false; }
  }));
  const buyerSent = results[0] === true;
  const professionalSent = results[1] === true;
  const anySent = buyerSent || professionalSent;
  const fieldModifications = [
    { fieldPath: "emailSentToBuyer", action: "SET_FIELD", setFieldOptions: { value: buyerSent } },
    { fieldPath: "emailSentToProfessional", action: "SET_FIELD", setFieldOptions: { value: professionalSent } },
    ...(anySent ? [{ fieldPath: "status", action: "SET_FIELD", setFieldOptions: { value: "notified" } }] : []),
    ...(buyerSent && professionalSent ? [{ fieldPath: "notifiedAt", action: "SET_FIELD", setFieldOptions: { value: new Date().toISOString() } }] : []),
  ];
  await wix(`/wix-data/v2/items/${encodeURIComponent(matchingId)}`, token, "PATCH", {
    dataCollectionId: "particularsearchmatchings", patch: { dataItemId: matchingId, fieldModifications },
  });
}

async function processSearchMatching(search: Record<string, unknown>, token: string): Promise<number> {
  const searchId = String(search._id ?? "");
  const latitude = numeric(search.latitude), longitude = numeric(search.longitude);
  if (!searchId || !latitude || !longitude || !numeric(search.radius)) return 0;
  const [properties, existingMatches, professionals] = await Promise.all([
    queryAll("biensprofessionnels", {}, ["title", "city", "postalCode", "price", "surface", "landSurface", "propertyType", "transactionType", "latitude", "longitude", "status", "listingUrl", "professionalId", "wixMemberId", "owner", "email", "phone", "companyName", "hasGroundFloorBedroom", "hasGarage", "isLandFenced", "hasAnnexe", "hasPiscine", "mainImageUrl", "galleryImages"], token),
    queryAll("particularsearchmatchings", { searchId: { $eq: searchId } }, [], token),
    queryAll("professionnels", {}, ["memberId", "firstName", "lastName", "companyName", "email", "phone", "slug", "network", "agency", "company", "enseigne", "reseau", "profilePhoto", "photo", "image"], token),
  ]);
  const existing = new Map(existingMatches.map((item) => [String(item.propertyId ?? ""), item]));
  const profileMap = new Map<string, Record<string, unknown>>();
  for (const professional of professionals) {
    for (const key of [professional._id, professional.memberId, professional.email]) {
      if (key) profileMap.set(String(key).toLowerCase(), professional);
    }
  }
  const candidates = properties.filter((property) => {
    const status = String(property.status ?? "").toLowerCase();
    return status === "active" || status === "published" || !status;
  }).filter((property) => String(property._id ?? "") && matchingScore(search, property) >= 80);
  let created = 0;
  for (const property of candidates) {
    const propertyId = String(property._id);
    const old = existing.get(propertyId);
    if (old) {
      if (old.emailSentToBuyer !== true || old.emailSentToProfessional !== true) {
        await sendMatchingEmails(String(old._id ?? ""), old, token);
      }
      continue;
    }
    const professional = [property.professionalId, property.wixMemberId, property.owner, property.email]
      .map((key) => key ? profileMap.get(String(key).toLowerCase()) : undefined).find(Boolean) ?? {};
    const matchingData: Record<string, unknown> = {
      searchId, propertyId,
      buyerAccountId: String(search.accountId ?? ""),
      buyerEmail: String(search.particulierEmail ?? search.email ?? ""),
      buyerFirstName: search.particulierFirstName ?? search.firstName,
      buyerLastName: search.particulierLastName ?? search.lastName,
      buyerName: search.particulierName,
      buyerPhone: search.particulierPhone ?? search.phone,
      particulierFirstName: search.particulierFirstName,
      particulierLastName: search.particulierLastName,
      particulierName: search.particulierName,
      particulierEmail: search.particulierEmail ?? search.email,
      particulierPhone: search.particulierPhone ?? search.phone,
      propertyTitle: property.title ?? "", propertyCity: property.city ?? "", propertyPostalCode: property.postalCode ?? "",
      propertyPrice: property.price, propertySurface: property.surface, propertyType: property.propertyType ?? "",
      transactionType: property.transactionType ?? "", propertyUrl: property.listingUrl ?? "",
      propertyImage: property.mainImageUrl ?? "", professionalId: professional._id ?? property.professionalId ?? "",
      professionalMemberId: professional.memberId ?? property.wixMemberId ?? "",
      professionalName: professional.companyName ?? property.companyName ?? "",
      professionalFirstName: professional.firstName ?? "",
      professionalNetwork: professional.network ?? professional.agency ?? professional.company ?? professional.enseigne ?? professional.reseau ?? "",
      professionalPhoto: professional.profilePhoto ?? professional.photo ?? professional.image ?? "",
      professionalEmail: professional.email ?? property.email ?? "", professionalPhone: professional.phone ?? property.phone ?? "",
      professionalCity: property.city ?? "", professionalSlug: professional.slug ?? "",
      matchingScore: matchingScore(search, property), status: "new", emailSentToBuyer: false,
      emailSentToProfessional: false, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    };
    const inserted = await wix<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, "POST", {
      dataCollectionId: "particularsearchmatchings", dataItem: { data: matchingData },
    });
    const matchingId = String(inserted.dataItem?.id ?? "");
    if (!matchingId) continue;
    created++;
    await sendMatchingEmails(matchingId, matchingData, token);
  }
  return created;
}

async function accountForMember(email: string, token: string) {
  const accounts = await query("privateaccounts", { email: { $eq: email } }, ["email", "isActive"], token, 2);
  const account = accounts.find((item) => item.isActive !== false);
  if (!account?._id) return null;
  const profiles = await query("privateprofiles", { ownerId: { $eq: String(account._id) } }, ["ownerId", "firstName", "lastName", "phone"], token, 1);
  return { id: String(account._id), profile: profiles[0] ?? {} };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  try {
    const memberResponse = await wix<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = text(memberResponse.member?.loginEmail, 254).toLowerCase();
    if (!memberResponse.member?.id || !email || memberResponse.member.loginEmailVerified === false) {
      return response({ error: "Le compte Wix n’est pas vérifié." }, 403);
    }
    const account = await accountForMember(email, token);
    if (!account) return response({ error: "Aucun compte particulier actif n’est associé à cette adresse e-mail." }, 403);

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || typeof body !== "object") return response({ error: "Demande invalide." }, 400);
    const action = text(body.action, 20);

    if (action === "dismiss_matching") {
      const matchingId = text(body.matchingId, 128);
      if (!matchingId) return response({ error: "Matching introuvable." }, 400);
      const matching = (await query("particularsearchmatchings", {
        _id: { $eq: matchingId }, buyerAccountId: { $eq: account.id },
      }, ["buyerAccountId"], token, 2)).find((item) => item._id === matchingId);
      if (!matching) return response({ error: "Ce matching n’appartient pas à votre espace." }, 403);
      await wix(`/wix-data/v2/items/${encodeURIComponent(matchingId)}`, token, "PATCH", {
        dataCollectionId: "particularsearchmatchings",
        patch: { dataItemId: matchingId, fieldModifications: [
          { fieldPath: "dismissedByParticulier", action: "SET_FIELD", setFieldOptions: { value: true } },
        ] },
      });
      return response({ success: true, matchingId, dismissedByParticulier: true });
    }

    if (action === "create" || action === "update") {
      const searchId = text(body.searchId, 128);
      let existing: Record<string, unknown> | undefined;
      if (action === "update") {
        if (!searchId) return response({ error: "Recherche introuvable." }, 400);
        existing = (await query("particularbuyersearches", {
          _id: { $eq: searchId }, accountId: { $eq: account.id },
        }, ["accountId", "isActive"], token, 2)).find((item) => item._id === searchId);
        if (!existing) return response({ error: "Cette recherche n’appartient pas à votre espace." }, 403);
      }
      const searchName = text(body.searchName, 80);
      const transactionType = text(body.transactionType, 20);
      const city = text(body.city, 100);
      const postalCode = text(body.postalCode, 10);
      const rawPropertyTypes = Array.isArray(body.propertyTypes) ? body.propertyTypes : [];
      const allowedPropertyTypes = new Set([
        "Maison", "Appartement", "Terrain", "Immeuble", "Commerce", "Bureau", "Garage / Parking", "Autre",
        "Mobile-home", "Bien saisonnier", "Gîte", "Château", "Camping", "Mas", "Place de parking", "Pêcherie",
        "Maison de vacances", "Résidence secondaire", "Terrain de loisirs", "Terrain agricole", "Étang", "Grange",
        "Dépendance", "Corps de ferme", "Longère", "Loft", "Atelier", "Hangar", "Local professionnel",
        "Fonds de commerce", "Viager", "Colocation", "Chambre", "Studio",
      ]);
      const propertyTypes = [...new Set(rawPropertyTypes.map((item) => text(item, 40)).filter((item) => allowedPropertyTypes.has(item)))];
      const radius = numeric(body.radius);
      const minBudget = numeric(body.minBudget) ?? 0;
      const maxBudget = numeric(body.maxBudget) ?? 0;
      const minSurface = numeric(body.minSurface) ?? 0;
      const maxSurface = numeric(body.maxSurface);
      const minLandSurface = numeric(body.minLandSurface) ?? 0;
      const maxLandSurface = numeric(body.maxLandSurface);
      const minRooms = numeric(body.minRooms) ?? 0;
      const minBedrooms = numeric(body.minBedrooms) ?? 0;
      const minBathrooms = numeric(body.minBathrooms) ?? 0;
      const latitude = numeric(body.latitude);
      const longitude = numeric(body.longitude);
      const emailAlertsEnabled = body.emailAlertsEnabled === true;
      if (searchName.length < 2 || !["buy", "rent"].includes(transactionType) ||
          !city || !/^\d{5}$/.test(postalCode) || propertyTypes.length === 0 ||
          radius === undefined || Number.isNaN(radius) || radius < 1 || radius > 500 ||
          [minBudget, maxBudget, minSurface, maxSurface, minLandSurface, maxLandSurface, minRooms, minBedrooms, minBathrooms].some((value) => Number.isNaN(value) || (value !== undefined && value < 0)) ||
          (maxBudget > 0 && minBudget > maxBudget) ||
          (maxSurface !== undefined && maxSurface > 0 && minSurface > maxSurface) ||
          (maxLandSurface !== undefined && maxLandSurface > 0 && minLandSurface > maxLandSurface) ||
          ((latitude === undefined) !== (longitude === undefined)) ||
          (latitude !== undefined && (Number.isNaN(latitude) || latitude < -90 || latitude > 90)) ||
          (longitude !== undefined && (Number.isNaN(longitude) || longitude < -180 || longitude > 180))) {
        return response({ error: "Vérifiez le nom, la localisation, les types de biens et les critères de recherche." }, 400);
      }

      const profile = account.profile;
      const name = [text(profile.firstName, 80), text(profile.lastName, 80)].filter(Boolean).join(" ");
      const data: Record<string, unknown> = {
        accountId: account.id,
        searchName,
        transactionType,
        propertyTypes: propertyTypes.join(", "),
        city,
        postalCode,
        radius,
        minBudget,
        maxBudget,
        minSurface,
        minLandSurface,
        minRooms,
        minBedrooms,
        minBathrooms,
        singleStory: body.singleStory === true,
        garage: body.garage === true,
        garden: body.garden === true,
        terrace: body.terrace === true,
        pool: body.pool === true,
        parking: body.parking === true,
        isActive: existing ? existing.isActive !== false : true,
        emailAlertsEnabled,
        particulierEmail: email,
        email,
        firstName: text(profile.firstName, 80),
        lastName: text(profile.lastName, 80),
        phone: text(profile.phone, 40),
        particulierName: name,
        particulierFirstName: text(profile.firstName, 80),
        particulierLastName: text(profile.lastName, 80),
        particulierPhone: text(profile.phone, 40),
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      if (maxSurface !== undefined) data.maxSurface = maxSurface;
      if (maxLandSurface !== undefined) data.maxLandSurface = maxLandSurface;
      if (latitude !== undefined && longitude !== undefined) {
        data.latitude = latitude;
        data.longitude = longitude;
      }

      if (existing) {
        const fieldModifications = Object.entries(data).map(([fieldPath, value]) => ({
          fieldPath, action: "SET_FIELD", setFieldOptions: { value },
        }));
        await wix(`/wix-data/v2/items/${encodeURIComponent(searchId)}`, token, "PATCH", {
          dataCollectionId: "particularbuyersearches",
          patch: { dataItemId: searchId, fieldModifications },
        });
        const matchingCount = await processSearchMatching({ ...data, _id: searchId }, token).catch((error) => {
          console.error("[ios-native-buyer-searches] matching update failed", error);
          return 0;
        });
        return response({ success: true, searchId, isActive: data.isActive, matchingCount });
      }
      const inserted = await wix<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, "POST", {
        dataCollectionId: "particularbuyersearches",
        dataItem: { data },
      });
      if (!inserted.dataItem?.id) return response({ error: "Wix n’a pas confirmé l’enregistrement de la recherche." }, 502);
      const matchingCount = await processSearchMatching({ ...data, _id: inserted.dataItem.id }, token).catch((error) => {
        console.error("[ios-native-buyer-searches] matching creation failed", error);
        return 0;
      });
      return response({ success: true, searchId: inserted.dataItem.id, matchingCount });
    }

    if (["deactivate", "activate", "alerts", "delete"].includes(action)) {
      const searchId = text(body.searchId, 128);
      if (!searchId) return response({ error: "Recherche introuvable." }, 400);
      const owned = (await query("particularbuyersearches", {
        _id: { $eq: searchId }, accountId: { $eq: account.id },
      }, ["accountId", "isActive"], token, 2)).find((item) => item._id === searchId);
      if (!owned) return response({ error: "Cette recherche n’appartient pas à votre espace." }, 403);
      if (action === "delete") {
        await wix(`/wix-data/v2/items/${encodeURIComponent(searchId)}?dataCollectionId=particularbuyersearches`, token, "DELETE");
        return response({ success: true, searchId, deleted: true });
      }
      const fieldPath = action === "alerts" ? "emailAlertsEnabled" : "isActive";
      const fieldValue = action === "alerts" ? body.enabled === true : action === "activate";
      await wix(`/wix-data/v2/items/${encodeURIComponent(searchId)}`, token, "PATCH", {
        dataCollectionId: "particularbuyersearches",
        patch: {
          dataItemId: searchId,
          fieldModifications: [{
            fieldPath,
            action: "SET_FIELD",
            setFieldOptions: { value: fieldValue },
          }],
        },
      });
      return response({ success: true, searchId, [fieldPath]: fieldValue });
    }
    return response({ error: "Action inconnue." }, 400);
  } catch (error) {
    console.error("[ios-native-buyer-searches]", error);
    return response({ error: "Impossible de traiter cette recherche. Réessayez." }, 502);
  }
});
