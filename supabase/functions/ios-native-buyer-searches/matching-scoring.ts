type RecordValue = Record<string, unknown>;

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function numeric(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function normalizedText(value: unknown): string {
  return String(value ?? "").trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[\s_-]+/g, " ");
}

export function normalizePropertyType(value: unknown): string {
  const normalized = normalizedText(text(value, 100)).replace(/[\/]+/g, " ").replace(/\s+/g, "-");
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

export function normalizeTransactionType(value: unknown): string {
  const normalized = normalizedText(text(value, 40)).replace(/\s/g, "");
  if (["buy", "sale", "sell", "vente", "achat", "acheter"].includes(normalized)) return "buy";
  if (["rent", "rental", "location", "louer", "locatif"].includes(normalized)) return "rent";
  return normalized;
}

function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const radians = (value: number) => value * Math.PI / 180;
  const dLat = radians(lat2 - lat1), dLon = radians(lon2 - lon1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function propertyFeatures(property: RecordValue): Set<string> {
  const values: string[] = [];
  const raw = property.features;
  if (Array.isArray(raw)) values.push(...raw.map(String));
  else if (typeof raw === "string") values.push(...raw.split(/[,;|\n]/));
  else if (raw && typeof raw === "object") {
    values.push(...Object.entries(raw as RecordValue).filter(([, enabled]) => Boolean(enabled)).map(([name]) => name));
  }
  return new Set(values.map(normalizedText).filter(Boolean));
}

function hasFeature(property: RecordValue, features: Set<string>, fields: string[], labels: string[]): boolean {
  if (fields.some((field) => property[field] === true)) return true;
  return labels.some((label) => features.has(normalizedText(label)));
}

/** Mirrors the Wix saved-search scorer while keeping optional feature criteria neutral when unset. */
export function calculateBuyerSearchScore(search: RecordValue, property: RecordValue): number {
  let score = 0, totalWeight = 0;
  const value = (key: string) => numeric(property[key]);
  const latitude = numeric(search.latitude), longitude = numeric(search.longitude);
  const propertyLatitude = value("latitude"), propertyLongitude = value("longitude");
  const radius = numeric(search.radius) ?? 50;
  if (propertyLatitude !== undefined && propertyLongitude !== undefined &&
      !Number.isNaN(propertyLatitude) && !Number.isNaN(propertyLongitude) &&
      latitude !== undefined && longitude !== undefined && !Number.isNaN(latitude) && !Number.isNaN(longitude)) {
    const distance = distanceKm(latitude, longitude, propertyLatitude, propertyLongitude);
    score += distance <= radius ? 30 : Math.max(0, 30 - ((distance - radius) / radius) * 30);
  }
  totalWeight += 30;

  const price = value("price");
  if (price !== undefined && !Number.isNaN(price)) {
    const min = numeric(search.minBudget) ?? 0, max = numeric(search.maxBudget) || Infinity;
    if (price >= min && price <= max) score += 25;
    else if (price < min && min > 0) score += Math.max(0, 25 - ((min - price) / min) * 25);
    else if (price > max && Number.isFinite(max) && max > 0) score += Math.max(0, 25 - ((price - max) / max) * 25);
  }
  totalWeight += 25;

  const surface = value("surface"), minSurface = numeric(search.minSurface), maxSurface = numeric(search.maxSurface);
  if (minSurface !== undefined && minSurface > 0 && surface !== undefined && !Number.isNaN(surface)) {
    score += surface >= minSurface ? 15 : Math.max(0, 15 - ((minSurface - surface) / minSurface) * 15);
    totalWeight += 15;
  }
  if (maxSurface !== undefined && maxSurface > 0 && surface !== undefined && !Number.isNaN(surface)) {
    score += surface <= maxSurface ? 15 : Math.max(0, 15 - ((surface - maxSurface) / maxSurface) * 15);
    totalWeight += 15;
  }

  const land = value("landSurface"), minLand = numeric(search.minLandSurface), maxLand = numeric(search.maxLandSurface);
  if (minLand !== undefined && minLand > 0 && land !== undefined && !Number.isNaN(land)) {
    score += land >= minLand ? 10 : Math.max(0, 10 - ((minLand - land) / minLand) * 10);
    totalWeight += 10;
  }
  if (maxLand !== undefined && maxLand > 0 && land !== undefined && !Number.isNaN(land)) {
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
    if (wanted !== undefined && wanted > 0 && actual !== undefined && !Number.isNaN(actual)) {
      if (actual >= wanted) roomScore += weight;
      roomWeight += weight;
    }
  }
  if (roomWeight > 0) { score += (roomScore / roomWeight) * 10; totalWeight += 10; }

  const featureCriteria = ["singleStory", "garage", "garden", "terrace", "pool", "parking"]
    .filter((key) => search[key] === true);
  if (featureCriteria.length > 0) {
    const features = propertyFeatures(property);
    const matched = featureCriteria.filter((criterion) => {
      switch (criterion) {
        case "singleStory":
          return property.hasGroundFloorBedroom === true && property.hasGroundFloorBathroom === true;
        case "garage": return hasFeature(property, features, ["hasGarage"], ["garage"]);
        case "garden": return hasFeature(property, features, ["hasGarden"], ["jardin", "garden"]);
        case "terrace": return hasFeature(property, features, ["hasTerrace"], ["terrasse", "terrace"]);
        case "pool": return hasFeature(property, features, ["hasPiscine", "hasSwimmingPool"], ["piscine", "pool"]);
        case "parking": return hasFeature(property, features, ["hasParking", "hasGarage"], ["parking", "garage"]);
        default: return false;
      }
    }).length;
    score += (matched / featureCriteria.length) * 10;
    totalWeight += 10;
  }
  return totalWeight > 0 ? Math.round(score / totalWeight * 100) : 0;
}
