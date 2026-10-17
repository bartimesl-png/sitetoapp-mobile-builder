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

async function query(collection: string, filter: Record<string, unknown>, fields: string[], token: string) {
  const result = await wix<{ dataItems?: WixItem[] }>("/wix-data/v2/items/query", token, "POST", {
    dataCollectionId: collection,
    query: { filter, paging: { limit: 3 }, fields },
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
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : undefined;
}
async function insert(collection: string, data: Record<string, unknown>, token: string): Promise<string> {
  const result = await wix<{ dataItem?: { id?: string } }>("/wix-data/v2/items", token, "POST", {
    dataCollectionId: collection,
    dataItem: { data },
  });
  const id = text(result.dataItem?.id, 128);
  if (!id) throw new Error(`Wix did not confirm insert into ${collection}`);
  return id;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return response({ error: "Méthode non autorisée." }, 405);
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response({ error: "Connexion requise." }, 401);

  try {
    const wixMember = await wix<{ member?: { id?: string; loginEmail?: string; loginEmailVerified?: boolean; contact?: { firstName?: string; lastName?: string } } }>(
      "/members/v1/members/my?fieldSet=FULL", token,
    );
    const email = text(wixMember.member?.loginEmail, 254).toLowerCase();
    const memberID = text(wixMember.member?.id, 128);
    if (!memberID || !email || wixMember.member?.loginEmailVerified === false) {
      return response({ error: "Le compte Wix doit être vérifié avant de créer un espace métier." }, 403);
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return response({ error: "Demande invalide." }, 400);
    const role = text(body.role, 24);
    if (!new Set(["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire", "hebergeur"]).has(role)) {
      return response({ error: "Espace inconnu." }, 400);
    }
    if (body.acceptedTerms !== true) return response({ error: "L’acceptation des conditions est nécessaire pour créer votre espace." }, 400);

    const firstName = text(body.firstName, 80) || text(wixMember.member?.contact?.firstName, 80);
    const lastName = text(body.lastName, 80) || text(wixMember.member?.contact?.lastName, 80);
    const phone = text(body.phone, 40);
    const city = text(body.city, 100);
    const postalCode = text(body.postalCode, 10);
    const companyName = text(body.companyName, 140);
    const contactName = text(body.contactName, 140) || [firstName, lastName].filter(Boolean).join(" ");
    const category = text(body.category, 100);
    const subcategory = text(body.subcategory, 100);
    const description = text(body.description, 1600);
    const websiteValue = text(body.website, 300);
    const websiteURL = websiteValue ? new URL(websiteValue.startsWith("http") ? websiteValue : `https://${websiteValue}`) : null;
    const website = websiteURL && ["http:", "https:"].includes(websiteURL.protocol) ? websiteURL.toString() : "";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    if (firstName.length < 2 || lastName.length < 2 || phone.replace(/\D/g, "").length < 8) {
      return response({ error: "Renseignez vos prénom, nom et un numéro de téléphone valide." }, 400);
    }
    const now = new Date().toISOString();
    let accountId = "";
    let profileId = "";
    let accountCollection = "";
    let profileCollection = "";
    let accountFilter: Record<string, unknown> = { email: { $eq: email } };

    if (role === "particulier") {
      accountCollection = "privateaccounts";
      profileCollection = "privateprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive", "accountType"], token))[0];
      if (existing?._id) return response({ success: true, role, accountId: String(existing._id), alreadyExists: true });
      accountId = await insert(accountCollection, { email, accountType: "private_vendor", acceptedTerms: true, acceptedTermsDate: now, isActive: true, createdAt: now }, token);
      profileId = await insert(profileCollection, { ownerId: accountId, firstName, lastName, email, phone, city, postalCode, isProfileComplete: false, createdAt: now }, token);
    } else if (role === "professionnel") {
      if (companyName.length < 2 || category.length < 2 || city.length < 2 || postalCode.length < 4) {
        return response({ error: "Renseignez la société, le métier, la ville et le code postal." }, 400);
      }
      accountCollection = "prosaccounts";
      profileCollection = "prosprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) return response({ success: true, role, accountId: String(existing._id), alreadyExists: true });
      accountId = await insert(accountCollection, { email, isActive: true, cguAccepted: true, cgvAccepted: true, cguAcceptedAt: now, cgvAcceptedAt: now, createdAt: now }, token);
      const categories = JSON.stringify([{ mainCategory: category, subCategories: subcategory ? [subcategory] : [] }]);
      profileId = await insert(profileCollection, {
        accountId, professionalType: text(body.professionalType, 40) || "mandataire", companyName, contactName,
        phoneNumber: phone, email, city, postalCode, category, categories,
        description, isProfileComplete: false, isActive: true, isVisiblePublicly: false,
        hasActiveSubscription: false, subscriptionStatus: "free", createdAt: now, updatedAt: now,
      }, token);
      if (website) {
        await wix(`/wix-data/v2/items/${encodeURIComponent(profileId)}`, token, "PATCH", {
          dataCollectionId: profileCollection,
          patch: { dataItemId: profileId, fieldModifications: [{ fieldPath: "website", action: "SET_FIELD", setFieldOptions: { value: website } }] },
        });
      }
    } else if (role === "courtier") {
      if (text(body.professionalTitle, 100).length < 2 || city.length < 2) {
        return response({ error: "Renseignez votre spécialité et votre ville." }, 400);
      }
      accountCollection = "brokeraccounts";
      profileCollection = "brokerprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) return response({ success: true, role, accountId: String(existing._id), alreadyExists: true });
      accountId = await insert(accountCollection, { email, isActive: true, cguAccepted: true, cgvAccepted: true, cguAcceptedAt: now, cgvAcceptedAt: now, createdAt: now }, token);
      const broker: Record<string, unknown> = { accountId, fullName, professionalTitle: text(body.professionalTitle, 100), contactEmail: email, phoneNumber: phone, city };
      if (website) broker.websiteUrl = website;
      const experience = numeric(body.yearsOfExperience);
      if (experience !== undefined) broker.yearsOfExperience = experience;
      profileId = await insert(profileCollection, broker, token);
    } else if (["artisan", "diagnostiqueur", "prestataire"].includes(role)) {
      if (companyName.length < 2 || category.length < 2 || city.length < 2 || postalCode.length < 4) {
        return response({ error: "Renseignez l’entreprise, l’activité, la ville et le code postal." }, 400);
      }
      accountCollection = "serviceprovideraccounts-1";
      profileCollection = "serviceproviders-1";
      accountFilter = { email: { $eq: email } };
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) return response({ success: true, role, accountId: String(existing._id), alreadyExists: true });
      accountId = await insert(accountCollection, { firstName, lastName, email, phone, isActive: true, createdAt: now }, token);
      const roleCategory = role === "artisan" ? "Artisan" : role === "diagnostiqueur" ? "Diagnostiqueur" : category;
      profileId = await insert(profileCollection, {
        accountId, businessName: companyName, category: roleCategory, subcategory, description,
        city, postalCode, phone, email, status: "pending", verified: false, createdAt: now, updatedAt: now,
      }, token);
      if (website) {
        await wix(`/wix-data/v2/items/${encodeURIComponent(profileId)}`, token, "PATCH", {
          dataCollectionId: profileCollection,
          patch: { dataItemId: profileId, fieldModifications: [{ fieldPath: "website", action: "SET_FIELD", setFieldOptions: { value: website } }] },
        });
      }
    } else {
      if (role !== "hebergeur" || companyName.length < 2) {
        return response({ error: "Renseignez le nom de votre hébergement ou activité." }, 400);
      }
      profileCollection = "seasonalhostprofiles";
      const existing = (await query(profileCollection, { email: { $eq: email } }, ["email", "isVerified"], token))[0];
      if (existing?._id) return response({ success: true, role, profileId: String(existing._id), alreadyExists: true });
      profileId = await insert(profileCollection, { fullName: companyName, email, phoneNumber: phone, biography: description, isVerified: false }, token);
    }

    return response({ success: true, role, accountId: accountId || undefined, profileId });
  } catch (error) {
    console.error("[ios-native-role-registration]", error);
    return response({ error: "Impossible de relier l’inscription à votre espace métier Wix. Vous pouvez réessayer depuis l’application." }, 502);
  }
});
