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

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function patchFields(collection: string, id: string, fields: Record<string, unknown>, token: string): Promise<void> {
  const fieldModifications = Object.entries(fields)
    .filter(([, value]) => value !== undefined && value !== null && value !== "")
    .map(([fieldPath, value]) => ({
      fieldPath,
      action: "SET_FIELD",
      setFieldOptions: { value },
    }));
  if (fieldModifications.length === 0) return;
  await wix(`/wix-data/v2/items/${encodeURIComponent(id)}`, token, "PATCH", {
    dataCollectionId: collection,
    patch: { dataItemId: id, fieldModifications },
  });
}

async function triggerProfessionalSignupEmails(data: {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  companyName: string;
  network: string;
  createdAt: string;
}): Promise<{ welcomeProfessional: boolean; professionalCreated: boolean }> {
  const endpoint = "https://www.partenairefoyer.com/api/emailEvents";
  const events = [
    {
      key: "welcomeProfessional" as const,
      body: {
        type: "welcomeProfessional",
        data: {
          firstName: data.firstName,
          lastName: data.lastName,
          email: data.email,
          network: data.network,
        },
      },
    },
    {
      key: "professionalCreated" as const,
      body: {
        eventType: "professional.created",
        data: {
          _id: data.id,
          _createdDate: data.createdAt,
          firstName: data.firstName,
          lastName: data.lastName,
          companyName: data.companyName,
          email: data.email,
        },
      },
    },
  ];
  const status = { welcomeProfessional: false, professionalCreated: false };
  for (const event of events) {
    try {
      const result = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(event.body),
      });
      const payload = await result.json().catch(() => null) as { success?: boolean } | null;
      status[event.key] = result.ok && payload?.success === true;
    } catch (error) {
      console.error(`[ios-native-role-registration] Failed email event ${event.key}`, error);
    }
  }
  return status;
}

async function syncExistingRealEstateLegalAcceptance(memberID: string, now: string, token: string): Promise<void> {
  try {
    const records = await query("professionnels", { memberId: { $eq: memberID } }, ["memberId", "termsAccepted", "termsAcceptedVersion"], token);
    const record = records[0];
    if (!record?._id) return;
    await patchFields("professionnels", String(record._id), {
      termsAccepted: true,
      termsAcceptedDate: now,
      termsAcceptedVersion: "1.0|1.0",
    }, token);
  } catch (error) {
    console.warn("[ios-native-role-registration] Could not sync the real-estate legal acceptance", error);
  }
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
    if (body.acceptedTerms !== true || body.cguAccepted !== true || body.cgvAccepted !== true) {
      return response({ error: "Vous devez consulter et accepter séparément les CGU et les CGV applicables pour créer votre espace métier." }, 400);
    }

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
    const legacyPassword = typeof body.legacyPassword === "string" ? body.legacyPassword : "";
    const websiteValue = text(body.website, 300);
    const isVisiblePublicly = body.isVisiblePublicly === true || text(body.isVisiblePublicly, 5).toLowerCase() === "true";
    const websiteURL = websiteValue ? new URL(websiteValue.startsWith("http") ? websiteValue : `https://${websiteValue}`) : null;
    const website = websiteURL && ["http:", "https:"].includes(websiteURL.protocol) ? websiteURL.toString() : "";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    if (firstName.length < 2 || lastName.length < 2 || phone.replace(/\D/g, "").length < 8) {
      return response({ error: "Renseignez vos prénom, nom et un numéro de téléphone valide." }, 400);
    }
    const now = new Date().toISOString();
    const privateLegalAcceptance = {
      acceptedTerms: true,
      acceptedTermsDate: now,
    };
    const realEstateLegalAcceptance = {
      cguAccepted: true,
      cgvAccepted: true,
      cguAcceptedAt: now,
      cgvAcceptedAt: now,
      cguVersion: "1.0",
      cgvVersion: "1.0",
    };
    const brokerLegalAcceptance = {
      cguAccepted: true,
      cgvAccepted: true,
      cguAcceptedAt: now,
      cgvAcceptedAt: now,
      cguVersion: "2026-09-11",
      cgvVersion: "2026-09-11",
    };
    let accountId = "";
    let profileId = "";
    let accountCollection = "";
    let profileCollection = "";
    let shouldSendProfessionalSignupEmails = false;
    let accountFilter: Record<string, unknown> = { email: { $eq: email } };

    if (role === "particulier") {
      accountCollection = "privateaccounts";
      profileCollection = "privateprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive", "accountType"], token))[0];
      if (existing?._id) {
        if (existing.isActive === false) return response({ error: "Ce compte particulier est désactivé. Contactez PartenaireFoyer pour le réactiver." }, 403);
        accountId = String(existing._id);
        await patchFields(accountCollection, accountId, privateLegalAcceptance, token);
        const profile = (await query(profileCollection, { ownerId: { $eq: accountId } }, ["ownerId", "email"], token))[0];
        if (profile?._id) {
          const profileId = String(profile._id);
          await patchFields(profileCollection, profileId, { firstName, lastName, email, phone, city, postalCode }, token);
          return response({ success: true, role, accountId, profileId, alreadyExists: true, profileUpdated: true });
        }
      } else {
        accountId = await insert(accountCollection, { email, accountType: "private_vendor", ...privateLegalAcceptance, isActive: true, createdAt: now }, token);
      }
      profileId = await insert(profileCollection, { ownerId: accountId, firstName, lastName, email, phone, city, postalCode, isProfileComplete: false, createdAt: now }, token);
    } else if (role === "professionnel") {
      if (companyName.length < 2 || category.length < 2 || city.length < 2 || postalCode.length < 4) {
        return response({ error: "Renseignez la société, le métier, la ville et le code postal." }, 400);
      }
      accountCollection = "prosaccounts";
      profileCollection = "prosprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) {
        if (existing.isActive === false) return response({ error: "Ce compte professionnel est désactivé. Contactez PartenaireFoyer pour le réactiver." }, 403);
        accountId = String(existing._id);
        await patchFields(accountCollection, accountId, realEstateLegalAcceptance, token);
        const profile = (await query(profileCollection, { accountId: { $eq: accountId } }, ["accountId", "email"], token))[0];
        if (profile?._id) {
          const profileId = String(profile._id);
          const categories = JSON.stringify([{ mainCategory: category, subCategories: subcategory ? [subcategory] : [] }]);
          await patchFields(profileCollection, profileId, {
            professionalType: text(body.professionalType, 40) || undefined,
            companyName, contactName, phoneNumber: phone, email, city, postalCode,
            category, categories, description, website: website || undefined, isVisiblePublicly,
          }, token);
          await syncExistingRealEstateLegalAcceptance(memberID, now, token);
          return response({ success: true, role, accountId, profileId, alreadyExists: true, profileUpdated: true });
        }
      } else {
        accountId = await insert(accountCollection, { email, isActive: true, ...realEstateLegalAcceptance, createdAt: now }, token);
      }
      const categories = JSON.stringify([{ mainCategory: category, subCategories: subcategory ? [subcategory] : [] }]);
      profileId = await insert(profileCollection, {
        accountId, professionalType: text(body.professionalType, 40) || "mandataire", companyName, contactName,
        phoneNumber: phone, email, city, postalCode, category, categories,
        description, isProfileComplete: false, isActive: true,
        hasActiveSubscription: false, subscriptionStatus: "free", isVisiblePublicly, createdAt: now, updatedAt: now,
      }, token);
      shouldSendProfessionalSignupEmails = true;
      if (website) {
        await wix(`/wix-data/v2/items/${encodeURIComponent(profileId)}`, token, "PATCH", {
          dataCollectionId: profileCollection,
          patch: { dataItemId: profileId, fieldModifications: [{ fieldPath: "website", action: "SET_FIELD", setFieldOptions: { value: website } }] },
        });
      }
      await syncExistingRealEstateLegalAcceptance(memberID, now, token);
    } else if (role === "courtier") {
      if (text(body.professionalTitle, 100).length < 2 || city.length < 2) {
        return response({ error: "Renseignez votre spécialité et votre ville." }, 400);
      }
      accountCollection = "brokeraccounts";
      profileCollection = "brokerprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) {
        if (existing.isActive === false) return response({ error: "Ce compte courtier est désactivé. Contactez PartenaireFoyer pour le réactiver." }, 403);
        accountId = String(existing._id);
        await patchFields(accountCollection, accountId, brokerLegalAcceptance, token);
        const profile = (await query(profileCollection, { accountId: { $eq: accountId } }, ["accountId", "contactEmail"], token))[0];
        if (profile?._id) {
          const profileId = String(profile._id);
          const experience = numeric(body.yearsOfExperience);
          await patchFields(profileCollection, profileId, {
            fullName, professionalTitle: text(body.professionalTitle, 100), contactEmail: email,
            phoneNumber: phone, city, websiteUrl: website || undefined,
            yearsOfExperience: experience, bio: description || undefined,
          }, token);
          return response({ success: true, role, accountId, profileId, alreadyExists: true, profileUpdated: true });
        }
      } else {
        accountId = await insert(accountCollection, { email, isActive: true, ...brokerLegalAcceptance, createdAt: now }, token);
      }
      const broker: Record<string, unknown> = { accountId, fullName, professionalTitle: text(body.professionalTitle, 100), contactEmail: email, phoneNumber: phone, city, bio: description };
      if (website) broker.websiteUrl = website;
      const experience = numeric(body.yearsOfExperience);
      if (experience !== undefined) broker.yearsOfExperience = experience;
      profileId = await insert(profileCollection, broker, token);
    } else if (role === "artisan" || role === "diagnostiqueur") {
      if (companyName.length < 2 || subcategory.length < 2 || city.length < 2 || postalCode.length < 4) {
        return response({ error: "Renseignez l’entreprise, la spécialité, la ville et le code postal." }, 400);
      }
      if (legacyPassword.length < 8) {
        return response({ error: "Le mot de passe doit contenir au moins 8 caractères pour créer votre espace professionnel." }, 400);
      }
      accountCollection = "prosaccounts";
      profileCollection = "prosprofiles";
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      const roleCategory = role === "artisan" ? "Artisan" : "Diagnostiqueur";
      const categories = JSON.stringify([{ mainCategory: roleCategory, subCategories: [subcategory] }]);
      if (existing?._id) {
        if (existing.isActive === false) return response({ error: "Ce compte professionnel est désactivé. Contactez PartenaireFoyer pour le réactiver." }, 403);
        accountId = String(existing._id);
        const profiles = await query(profileCollection, { accountId: { $eq: accountId } }, ["accountId", "professionalType", "category", "categories"], token);
        const matchingProfile = profiles.find((item) => {
          const type = String(item.professionalType ?? "").toLowerCase();
          const categoryValue = String(item.category ?? "").toLowerCase();
          const categoryList = String(item.categories ?? "").toLowerCase();
          return role === "artisan"
            ? (type.includes("artisan") || categoryValue.includes("artisan") || categoryList.includes("artisan")) && !categoryList.includes("diagnostiqueur")
            : type.includes("diagnostiqueur") || categoryValue.includes("diagnostiqueur") || categoryList.includes("diagnostiqueur");
        });
        if (!matchingProfile?._id) {
          return response({ error: "Cette adresse est déjà associée à un autre espace professionnel. Utilisez l’adresse de votre compte artisan ou diagnostiqueur." }, 409);
        }
        profileId = String(matchingProfile._id);
        await patchFields(accountCollection, accountId, {
          cguAccepted: true, cgvAccepted: true, cguAcceptedAt: now, cgvAcceptedAt: now,
          cguVersion: "2026-09-11", cgvVersion: "2026-09-11",
        }, token);
        await patchFields(profileCollection, profileId, {
          professionalType: role, companyName, contactName, phoneNumber: phone, email,
          city, postalCode, mainPostalCode: postalCode, category: roleCategory, categories,
          description, website: website || undefined, isActive: true, updatedAt: now,
        }, token);
        return response({ success: true, role, accountId, profileId, alreadyExists: true, profileUpdated: true });
      }
      const passwordHash = await sha256Hex(legacyPassword);
      accountId = await insert(accountCollection, {
        email, passwordHash, isActive: true, cguAccepted: true, cgvAccepted: true,
        cguAcceptedAt: now, cgvAcceptedAt: now, cguVersion: "2026-09-11", cgvVersion: "2026-09-11",
        createdAt: now, lastLoginAt: now, failedLoginAttempts: 0,
      }, token);
      profileId = await insert(profileCollection, {
        accountId, professionalType: role, companyName, contactName, phoneNumber: phone, email,
        city, postalCode, mainPostalCode: postalCode, category: roleCategory, categories,
        description, website: website || undefined, isProfileComplete: false, isActive: true,
        isVisiblePublicly: false, hasActiveSubscription: false, subscriptionStatus: "free",
        createdAt: now, updatedAt: now,
      }, token);
    } else if (role === "prestataire") {
      if (companyName.length < 2 || category.length < 2 || city.length < 2 || postalCode.length < 4) {
        return response({ error: "Renseignez l’entreprise, l’activité, la ville et le code postal." }, 400);
      }
      accountCollection = "serviceprovideraccounts-1";
      profileCollection = "serviceproviders-1";
      accountFilter = { email: { $eq: email } };
      const existing = (await query(accountCollection, accountFilter, ["email", "isActive"], token))[0];
      if (existing?._id) {
        if (existing.isActive === false) return response({ error: "Ce compte professionnel de service est désactivé. Contactez PartenaireFoyer pour le réactiver." }, 403);
        accountId = String(existing._id);
        const profiles = await query(profileCollection, { accountId: { $eq: accountId } }, ["accountId", "category", "subcategory"], token);
        const matchesRole = profiles.find((item) => String(item.category ?? "").toLowerCase() === category.toLowerCase() &&
          !/artisan|diagnostiqueur/i.test(String(item.category ?? "")));
        if (matchesRole?._id) {
          const profileId = String(matchesRole._id);
          await patchFields(profileCollection, profileId, {
            businessName: companyName, category, subcategory, description,
            city, postalCode, phone, email, website: website || undefined,
          }, token);
          return response({ success: true, role, accountId, profileId, alreadyExists: true, profileUpdated: true });
        }
      } else {
        accountId = await insert(accountCollection, { firstName, lastName, email, phone, isActive: true, createdAt: now }, token);
      }
      profileId = await insert(profileCollection, {
        accountId, businessName: companyName, category, subcategory, description,
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
      if (existing?._id) {
        const profileId = String(existing._id);
        await patchFields(profileCollection, profileId, { fullName: companyName, email, phoneNumber: phone, biography: description }, token);
        return response({ success: true, role, profileId, alreadyExists: true, profileUpdated: true });
      }
      profileId = await insert(profileCollection, { fullName: companyName, email, phoneNumber: phone, biography: description, isVerified: false }, token);
    }

    const emailNotifications = shouldSendProfessionalSignupEmails
      ? await triggerProfessionalSignupEmails({
        id: profileId,
        email,
        firstName,
        lastName,
        companyName,
        network: text(body.companyName, 140),
        createdAt: now,
      })
      : undefined;
    return response({ success: true, role, accountId: accountId || undefined, profileId, emailNotifications });
  } catch (error) {
    console.error("[ios-native-role-registration]", error);
    return response({ error: "Impossible de relier l’inscription à votre espace métier Wix. Vous pouvez réessayer depuis l’application." }, 502);
  }
});
