const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const WIX = "https://www.wixapis.com";
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});
type WixItem = { id?: string; data?: Record<string, unknown>; [key: string]: unknown };

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

async function query(collection: string, filter: Record<string, unknown>, fields: string[], token: string, limit = 100) {
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  try {
    const member = await wix<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = text(member.member?.loginEmail, 254).toLowerCase();
    if (!member.member?.id || !email || member.member.loginEmailVerified === false) {
      return response({ error: "Le compte Wix n’est pas vérifié." }, 403);
    }

    const accounts = await query("privateaccounts", { email: { $eq: email } }, ["email", "isActive"], token, 2);
    const account = accounts.find((item) => item.isActive !== false);
    const accountId = text(account?._id, 128);
    if (!accountId) return response({ error: "Aucun compte particulier actif n’est associé à cette adresse e-mail." }, 403);

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return response({ error: "Demande invalide." }, 400);
    const action = text(body.action, 20);
    if (action === "list") {
      const favorites = await query("favoritelistings", { accountId: { $eq: accountId }, isArchived: { $ne: true } },
        ["accountId", "listingId", "sourceCollection", "isArchived"], token, 500);
      return response({ success: true, favorites: favorites
        .filter((item) => item.accountId === accountId && item.isArchived !== true)
        .map((item) => ({ listingId: text(item.listingId, 128), sourceCollection: text(item.sourceCollection, 80) }))
        .filter((item) => item.listingId && item.sourceCollection) });
    }

    const listingId = text(body.listingId, 128);
    const sourceCollection = text(body.sourceCollection, 80);
    const allowedSources = new Set(["privateproperties", "biensprofessionnels", "classifiedads-1", "imported-listings"]);
    if (!listingId || !allowedSources.has(sourceCollection)) {
      return response({ error: "Annonce ou source invalide." }, 400);
    }

    const matches = await query("favoritelistings", {
      accountId: { $eq: accountId },
      listingId: { $eq: listingId },
      sourceCollection: { $eq: sourceCollection },
    }, ["accountId", "listingId", "sourceCollection", "isArchived"], token, 100);
    const owned = matches.filter((item) => item.accountId === accountId &&
      item.listingId === listingId && item.sourceCollection === sourceCollection && typeof item._id === "string");

    if (action === "add") {
      if (owned.some((item) => item.isArchived !== true)) return response({ success: true, alreadySaved: true });
      const archived = owned.find((item) => item.isArchived === true);
      if (archived) {
        const id = text(archived._id, 128);
        await wix(`/wix-data/v2/items/${encodeURIComponent(id)}`, token, "PATCH", {
          dataCollectionId: "favoritelistings",
          patch: { dataItemId: id, fieldModifications: [{ fieldPath: "isArchived", action: "SET_FIELD", setFieldOptions: { value: false } }] },
        });
      } else {
        const created = await wix<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, "POST", {
          dataCollectionId: "favoritelistings",
          dataItem: { data: { accountId, listingId, sourceCollection, isArchived: false, createdAt: new Date().toISOString() } },
        });
        if (!created.dataItem?.id) return response({ error: "Wix n’a pas confirmé l’enregistrement du favori." }, 502);
      }
      return response({ success: true, listingId, sourceCollection });
    }

    if (action === "remove") {
      for (const item of owned.filter((entry) => entry.isArchived !== true)) {
        const id = text(item._id, 128);
        await wix(`/wix-data/v2/items/${encodeURIComponent(id)}`, token, "PATCH", {
          dataCollectionId: "favoritelistings",
          patch: { dataItemId: id, fieldModifications: [{ fieldPath: "isArchived", action: "SET_FIELD", setFieldOptions: { value: true } }] },
        });
      }
      return response({ success: true, listingId, sourceCollection, isArchived: true });
    }
    return response({ error: "Action inconnue." }, 400);
  } catch (error) {
    console.error("[ios-native-favorites]", error);
    return response({ error: "Impossible de synchroniser les favoris avec Wix. Réessayez." }, 502);
  }
});
