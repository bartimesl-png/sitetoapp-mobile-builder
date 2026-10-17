const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
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
    body: JSON.stringify({ dataCollectionId: collection, query: { filter, paging: { limit }, fields } }),
  });
  return (result.dataItems ?? []).map(unwrap);
}

const first = (items: Record<string, unknown>[]) => items[0] ?? null;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") return response({ error: "Méthode non autorisée." }, 405);

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  const conversationID = new URL(req.url).searchParams.get("conversationId")?.trim() ?? "";
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(conversationID)) {
    return response({ error: "Identifiant de conversation invalide." }, 400);
  }

  try {
    const result = await wixRequest<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = String(result.member?.loginEmail ?? "").trim().toLowerCase();
    if (!result.member?.id || !email || result.member.loginEmailVerified === false) {
      return response({ error: "Le compte Wix n’est pas vérifié." }, 403);
    }

    const account = first(await query("prosaccounts", { email: { $eq: email } }, ["email", "isActive"], token, 2));
    if (!account || account.isActive === false) return response({ error: "Espace professionnel introuvable." }, 403);
    const accountID = String(account._id ?? "");
    const profile = first(await query("prosprofiles", { accountId: { $eq: accountID } }, ["accountId", "isActive"], token, 2));
    if (!profile || profile.isActive === false) return response({ error: "Profil professionnel inactif." }, 403);
    const professionalID = String(profile._id ?? "");

    const messages = await query("messages", { conversationId: { $eq: conversationID } }, [
      "conversationId", "senderId", "receiverId", "content", "createdAt", "isRead", "readAt", "seen", "attachments",
    ], token);
    if (!messages.some((message) => String(message.senderId ?? "") === professionalID || String(message.receiverId ?? "") === professionalID)) {
      return response({ error: "Cette conversation n’est pas associée à votre espace professionnel." }, 403);
    }

    messages.sort((a, b) => String(a.createdAt ?? "").localeCompare(String(b.createdAt ?? "")));
    return response({ success: true, conversationId: conversationID, messages });
  } catch (error) {
    console.error("[ios-native-conversation]", error);
    return response({ error: "Impossible de charger cette conversation. Réessayez." }, 502);
  }
});
