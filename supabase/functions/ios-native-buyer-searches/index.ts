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
    query: { filter, paging: { limit }, fields },
  });
  return (result.dataItems ?? []).map((item) => {
    const data = item.data && typeof item.data === "object" ? item.data : item;
    return { ...data, _id: data._id ?? item.id ?? data.id } as Record<string, unknown>;
  });
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function numeric(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
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

    if (action === "create") {
      const searchName = text(body.searchName, 80);
      const transactionType = text(body.transactionType, 20);
      const city = text(body.city, 100);
      const postalCode = text(body.postalCode, 10);
      const rawPropertyTypes = Array.isArray(body.propertyTypes) ? body.propertyTypes : [];
      const allowedPropertyTypes = new Set(["Maison", "Appartement", "Immeuble", "Terrain", "Commerce", "Autre", "Bureau", "Mas"]);
      const propertyTypes = [...new Set(rawPropertyTypes.map((item) => text(item, 40)).filter((item) => allowedPropertyTypes.has(item)))];
      const radius = numeric(body.radius);
      const minBudget = numeric(body.minBudget) ?? 0;
      const maxBudget = numeric(body.maxBudget) ?? 0;
      const minSurface = numeric(body.minSurface) ?? 0;
      const maxSurface = numeric(body.maxSurface);
      const minRooms = numeric(body.minRooms) ?? 0;
      const minBedrooms = numeric(body.minBedrooms) ?? 0;
      const emailAlertsEnabled = body.emailAlertsEnabled === true;
      if (searchName.length < 2 || !["buy", "rent"].includes(transactionType) ||
          (!city && !/^\d{5}$/.test(postalCode)) || propertyTypes.length === 0 ||
          Number.isNaN(radius) || radius! < 1 || radius! > 100 ||
          [minBudget, maxBudget, minSurface, maxSurface, minRooms, minBedrooms].some((value) => Number.isNaN(value) || (value !== undefined && value < 0)) ||
          (maxBudget > 0 && minBudget > maxBudget) ||
          (maxSurface !== undefined && maxSurface > 0 && minSurface > maxSurface)) {
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
        minRooms,
        minBedrooms,
        isActive: true,
        emailAlertsEnabled,
        particulierEmail: email,
        particulierName: name,
        particulierFirstName: text(profile.firstName, 80),
        particulierLastName: text(profile.lastName, 80),
        particulierPhone: text(profile.phone, 40),
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      if (maxSurface !== undefined) data.maxSurface = maxSurface;

      const inserted = await wix<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, "POST", {
        dataCollectionId: "particularbuyersearches",
        dataItem: { data },
      });
      if (!inserted.dataItem?.id) return response({ error: "Wix n’a pas confirmé l’enregistrement de la recherche." }, 502);
      return response({ success: true, searchId: inserted.dataItem.id });
    }

    if (action === "deactivate") {
      const searchId = text(body.searchId, 128);
      if (!searchId) return response({ error: "Recherche introuvable." }, 400);
      const ownedSearches = await query("particularbuyersearches", { accountId: { $eq: account.id } }, ["accountId", "isActive"], token, 100);
      const owned = ownedSearches.find((item) => item._id === searchId && item.accountId === account.id);
      if (!owned) return response({ error: "Cette recherche n’appartient pas à votre espace." }, 403);
      await wix(`/wix-data/v2/items/${encodeURIComponent(searchId)}`, token, "PATCH", {
        dataCollectionId: "particularbuyersearches",
        patch: {
          dataItemId: searchId,
          fieldModifications: [{
            fieldPath: "isActive",
            action: "SET_FIELD",
            setFieldOptions: { value: false },
          }],
        },
      });
      return response({ success: true, searchId, isActive: false });
    }
    return response({ error: "Action inconnue." }, 400);
  } catch (error) {
    console.error("[ios-native-buyer-searches]", error);
    return response({ error: "Impossible de traiter cette recherche. Réessayez." }, 502);
  }
});
