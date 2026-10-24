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
  paging: { limit?: number; offset?: number } = {},
): Promise<Record<string, unknown>[]> {
  const result = await wixRequest<{ dataItems?: WixItem[] }>("/wix-data/v2/items/query", token, {
    method: "POST",
    body: JSON.stringify({
      dataCollectionId: collection,
      query: { filter, paging: { limit: paging.limit ?? 100, offset: paging.offset ?? 0 }, fields },
    }),
  });
  return (result.dataItems ?? []).map(unwrap);
}

async function listConversationMessages(conversationID: string, token: string) {
  const messages: Record<string, unknown>[] = [];
  const limit = 100;
  for (let offset = 0; offset < 1000; offset += limit) {
    const page = await query("seasonalmessages", { conversationId: { $eq: conversationID } }, [
      "conversationId", "accommodationId", "subject", "senderId", "receiverId", "messageContent", "sentAt", "isRead",
    ], token, { limit, offset });
    messages.push(...page);
    if (page.length < limit) break;
  }
  return messages.sort((a, b) => String(a.sentAt ?? "").localeCompare(String(b.sentAt ?? "")));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET" && req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  let body: Record<string, unknown> = {};
  if (req.method === "POST") {
    try { body = await req.json(); }
    catch { return response({ error: "Demande invalide." }, 400); }
  }
  const params = new URL(req.url).searchParams;
  const conversationID = String(body.conversationId ?? params.get("conversationId") ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(conversationID)) {
    return response({ error: "Identifiant de conversation invalide." }, 400);
  }
  const action = String(body.action ?? "send");
  if (req.method === "POST" && !["send", "mark_read"].includes(action)) {
    return response({ error: "Action de conversation inconnue." }, 400);
  }
  const content = String(body.content ?? "").trim();
  if (req.method === "POST" && action === "send" && (!content || content.length > 4000)) {
    return response({ error: "Le message doit contenir entre 1 et 4 000 caractères." }, 400);
  }

  try {
    const memberResponse = await wixRequest<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = String(memberResponse.member?.loginEmail ?? "").trim().toLowerCase();
    if (!memberResponse.member?.id || !email || memberResponse.member.loginEmailVerified === false) {
      return response({ error: "Le compte Wix n’est pas vérifié." }, 403);
    }

    const profiles = await query("seasonalhostprofiles", { email: { $eq: email } }, ["email"], token, { limit: 2 });
    const hostID = String(profiles[0]?._id ?? "");
    if (!hostID) return response({ error: "Aucun profil hébergeur n’est associé à ce compte." }, 403);

    const conversations = await query("seasonalconversations", {
      _id: { $eq: conversationID },
      hostId: { $eq: hostID },
    }, ["hostId", "vacationerId", "accommodationId", "status"], token, { limit: 2 });
    const conversation = conversations[0];
    if (!conversation || String(conversation.hostId ?? "") !== hostID) {
      return response({ error: "Cette conversation n’est pas associée à votre espace hébergeur." }, 404);
    }

    const messages = await listConversationMessages(conversationID, token);
    if (req.method === "GET") return response({ success: true, conversationId: conversationID, hostId: hostID, messages });

    if (action === "mark_read") {
      const unread = messages.filter((message) =>
        String(message.receiverId ?? "") === hostID && message.isRead !== true
      );
      for (let start = 0; start < unread.length; start += 10) {
        await Promise.all(unread.slice(start, start + 10).map(async (message) => {
          const id = String(message._id ?? "");
          if (!id) return;
          await wixRequest(`/wix-data/v2/items/${encodeURIComponent(id)}`, token, {
            method: "PATCH",
            body: JSON.stringify({
              dataCollectionId: "seasonalmessages",
              patch: {
                dataItemId: id,
                fieldModifications: [
                  { fieldPath: "isRead", action: "SET_FIELD", setFieldOptions: { value: true } },
                ],
              },
            }),
          });
        }));
      }
      return response({ success: true, markedRead: unread.length });
    }

    const recipientID = String(conversation.vacationerId ?? "");
    const accommodationID = String(conversation.accommodationId ?? "");
    if (!recipientID || !accommodationID) return response({ error: "Le destinataire de la conversation est introuvable." }, 409);
    const subject = String(messages.at(-1)?.subject ?? "Échange au sujet de votre hébergement").slice(0, 140);
    const inserted = await wixRequest<{ dataItem?: WixItem }>("/wix-data/v2/items", token, {
      method: "POST",
      body: JSON.stringify({
        dataCollectionId: "seasonalmessages",
        dataItem: { data: {
          conversationId: conversationID,
          accommodationId: accommodationID,
          subject,
          senderId: hostID,
          receiverId: recipientID,
          messageContent: content,
          sentAt: new Date().toISOString(),
          isRead: false,
        } },
      }),
    });
    if (!inserted.dataItem) return response({ error: "Wix n’a pas confirmé l’envoi du message." }, 502);
    try {
      await wixRequest(`/wix-data/v2/items/${encodeURIComponent(conversationID)}`, token, {
        method: "PATCH",
        body: JSON.stringify({
          dataCollectionId: "seasonalconversations",
          patch: {
            dataItemId: conversationID,
            fieldModifications: [{ fieldPath: "lastMessageTimestamp", action: "SET_FIELD", setFieldOptions: { value: new Date().toISOString() } }],
          },
        }),
      });
    } catch (error) {
      // Do not report failure after Wix has already stored the message; that
      // would encourage duplicate sends when the host retries.
      console.warn("[ios-native-host-conversation] timestamp update deferred", error);
    }
    return response({ success: true, message: inserted.dataItem ? unwrap(inserted.dataItem) : null });
  } catch (error) {
    console.error("[ios-native-host-conversation]", error);
    return response({ error: "Impossible de traiter cette conversation. Réessayez." }, 502);
  }
});
