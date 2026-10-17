const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WIX = "https://www.wixapis.com";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
type WixItem = { id?: string; data?: Record<string, unknown>; [key: string]: unknown };

const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});
const clean = (value: unknown) => String(value ?? "").trim();
const emailFilter = (email: string) => ({ email: { $eq: email } });

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
): Promise<Record<string, unknown>[]> {
  const result = await wixRequest<{ dataItems?: WixItem[] }>("/wix-data/v2/items/query", token, {
    method: "POST",
    body: JSON.stringify({ dataCollectionId: collection, query: { filter, paging: { limit: 5 }, fields } }),
  });
  return (result.dataItems ?? []).map(unwrap);
}

async function ownerForRole(role: string, email: string, token: string): Promise<{ ownerId: string; accountType: string } | null> {
  if (role === "particulier") {
    const account = (await query("privateaccounts", emailFilter(email), ["email", "isActive"], token))[0];
    if (!account || account.isActive === false) return null;
    return { ownerId: String(account._id ?? ""), accountType: "private_vendor" };
  }
  if (role === "professionnel") {
    const account = (await query("prosaccounts", emailFilter(email), ["email", "isActive"], token))[0];
    if (!account || account.isActive === false) return null;
    const profile = (await query("prosprofiles", { accountId: { $eq: String(account._id ?? "") } }, ["accountId", "isActive"], token))[0];
    if (!profile || profile.isActive === false) return null;
    return { ownerId: String(profile._id ?? ""), accountType: "real_estate_agent" };
  }
  if (role === "courtier") {
    const account = (await query("brokeraccounts", emailFilter(email), ["email", "isActive"], token))[0];
    if (!account || account.isActive === false) return null;
    const profile = (await query("brokerprofiles", { accountId: { $eq: String(account._id ?? "") } }, ["accountId"], token))[0];
    if (!profile) return null;
    return { ownerId: String(profile._id ?? ""), accountType: "broker" };
  }
  if (role === "artisan" || role === "diagnostiqueur") {
    const account = (await query("prosaccounts", emailFilter(email), ["email", "isActive"], token))[0];
    if (!account || account.isActive === false) return null;
    const accountId = String(account._id ?? "");
    const profiles = await query("prosprofiles", { accountId: { $eq: accountId } }, [
      "accountId", "professionalType", "category", "categories",
    ], token);
    const profile = profiles.find((item) => {
      const identity = `${String(item.professionalType ?? "")} ${String(item.category ?? "")} ${String(item.categories ?? "")}`;
      return role === "artisan"
        ? /artisan/i.test(identity) && !/diagnostiqueur/i.test(identity)
        : /diagnostiqueur|diagnostic/i.test(identity);
    });
    if (!profile) return null;
    return {
      ownerId: String(profile._id ?? ""),
      accountType: role === "artisan" ? "artisan" : "diagnostician",
    };
  }
  if (role === "prestataire") {
    // Service-provider signup still uses its independent legacy Wix collections.
    const accountCollection = "serviceprovideraccounts";
    const account = (await query(accountCollection, emailFilter(email), ["email", "isActive"], token))[0];
    if (!account || account.isActive === false) return null;
    const providers = await query("serviceproviders-1", { accountId: { $eq: String(account._id ?? "") } }, ["accountId", "category", "subcategory"], token);
    const profile = providers.find((item) => !/artisan|diagnostiqueur/i.test(`${String(item.category ?? "")} ${String(item.subcategory ?? "")}`));
    if (!profile) return null;
    return { ownerId: String(profile._id ?? ""), accountType: "service_provider" };
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);

  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  try {
    const body = await req.json() as Record<string, unknown>;
    const action = clean(body.action || "register");
    if (!['register', 'disable'].includes(action)) return response({ error: "Action inconnue." }, 400);
    const role = clean(body.role);
    const deviceId = clean(body.deviceId);
    const fcmToken = clean(body.fcmToken);
    const installationId = clean(body.installationId);
    if (action === "register" && !/^[a-z_]{3,32}$/.test(role)) return response({ error: "Espace invalide." }, 400);
    if (action === "register" && (deviceId.length < 5 || deviceId.length > 200)) return response({ error: "Appareil invalide." }, 400);
    if (action === "register" && (fcmToken.length < 20 || fcmToken.length > 4096)) return response({ error: "Jeton de notification invalide." }, 400);
    if (action === "disable" && !/^[0-9a-f-]{36}$/i.test(installationId)) return response({ error: "Appareil invalide." }, 400);
    if (!SUPABASE_URL || !SERVICE_ROLE) throw new Error("Configuration Supabase serveur manquante.");

    const memberResponse = await wixRequest<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const member = memberResponse.member;
    const email = clean(member?.loginEmail).toLowerCase();
    if (!member?.id || !email || member.loginEmailVerified === false) return response({ error: "Compte Wix non vérifié." }, 403);

    if (action === "disable") {
      const ownerIDs = new Set<string>();
      for (const supportedRole of ["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire"]) {
        const owner = await ownerForRole(supportedRole, email, token);
        if (owner?.ownerId) ownerIDs.add(owner.ownerId);
      }
      let disabled = 0;
      for (const ownerId of ownerIDs) {
        const url = new URL("/rest/v1/push_devices", SUPABASE_URL);
        url.searchParams.set("user_id", `eq.${ownerId}`);
        url.searchParams.set("device_id", `like.${installationId}-%`);
        const result = await fetch(url, {
          method: "PATCH",
          headers: {
            apikey: SERVICE_ROLE,
            Authorization: `Bearer ${SERVICE_ROLE}`,
            "Content-Type": "application/json",
            Prefer: "return=representation",
          },
          body: JSON.stringify({ enabled: false, registration_status: "disabled", updated_at: new Date().toISOString() }),
        });
        const raw = await result.text();
        if (!result.ok) throw new Error(`Désactivation des notifications impossible (${result.status}).`);
        const rows = raw ? JSON.parse(raw) as unknown : [];
        if (Array.isArray(rows)) disabled += rows.length;
      }
      return response({ success: true, disabled });
    }

    const owner = await ownerForRole(role, email, token);
    if (!owner?.ownerId) return response({ error: "Aucun espace actif associé à ce compte." }, 403);
    const now = new Date().toISOString();
    const url = new URL("/rest/v1/push_devices", SUPABASE_URL);
    url.searchParams.set("on_conflict", "user_id,device_id");
    const saved = await fetch(url, {
      method: "POST",
      headers: {
        apikey: SERVICE_ROLE,
        Authorization: `Bearer ${SERVICE_ROLE}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=representation",
      },
      body: JSON.stringify({
        user_id: owner.ownerId,
        email,
        account_type: owner.accountType,
        fcm_token: fcmToken,
        platform: "ios",
        device_id: deviceId,
        enabled: true,
        registration_status: "active",
        updated_at: now,
        last_seen_at: now,
      }),
    });
    const raw = await saved.text();
    if (!saved.ok) throw new Error(`Enregistrement du jeton impossible (${saved.status}).`);
    const rows = raw ? JSON.parse(raw) as unknown : [];
    return response({ success: true, registered: true, platform: "ios", ownerType: owner.accountType, device: Array.isArray(rows) ? rows[0] ?? null : null });
  } catch (error) {
    console.error("[ios-native-push-registration]", error);
    return response({ error: error instanceof Error ? error.message : "Enregistrement des notifications impossible." }, 502);
  }
});
