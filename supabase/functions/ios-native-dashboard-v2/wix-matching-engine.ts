// Wix matching engine port. Scoring and strict filters are copied from src/lib/matchingService.ts.
// Keep this synchronized with the read-only Wix source audit.
type BiensProfessionnels = Record<string, any>;
type BuyerProfiles = Record<string, any>;

function getDistance(lat1: number | undefined, lon1: number | undefined, lat2: number | undefined, lon2: number | undefined): number | null {
  if (lat1 === undefined || lon1 === undefined || lat2 === undefined || lon2 === undefined) return null;
  const toRad = (degrees: number) => degrees * Math.PI / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return Math.round((R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))) * 10) / 10;
}
function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number { return getDistance(lat1, lon1, lat2, lon2) ?? 0; }
function normalizeFeatures(features: any): string[] {
  if (Array.isArray(features)) return features;
  if (typeof features === 'string') return features.split(',').map((f: string) => f.trim()).filter(Boolean);
  if (features && typeof features === 'object') return Object.keys(features).filter(key => !!features[key]);
  return [];
}
function isRecentProperty(property: { anneeConstruction?: number } | null | undefined): boolean {
  if (!property?.anneeConstruction) return false;
  return new Date().getFullYear() - property.anneeConstruction <= 10;
}
export function normalizePropertyType(value: string): string {
  if (!value) return '';

  // Step 1: Normalize whitespace and case
  let normalized = value
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, ''); // Remove accents

  // Step 2: Normalize separators (spaces, underscores → hyphens)
  normalized = normalized
    .replace(/\s+/g, '-')      // spaces to hyphens
    .replace(/_/g, '-')        // underscores to hyphens
    .replace(/-+/g, '-');      // multiple hyphens to single

  // Step 3: Canonical mapping - English and old variants to French canonical values
  const canonicalMapping: Record<string, string> = {
    // Houses
    'house': 'maison',
    'home': 'maison',

    // Apartments
    'apartment': 'appartement',
    'flat': 'appartement',
    'studio': 'studio',

    // Land
    'land': 'terrain',
    'plot': 'terrain',

    // Buildings
    'building': 'immeuble',
    'immeuble': 'immeuble',

    // Commercial
    'commercial': 'commerce',
    'commercial-property': 'commerce',
    'office': 'bureau',
    'local-commercial': 'commerce',

    // Parking/Garage
    'parking': 'garage',
    'garage-parking': 'garage',
    'place-parking': 'place-parking',

    // Mobile homes
    'mobile-home': 'mobile-home',
    'mobile_home': 'mobile-home',
    'mobilehome': 'mobile-home',

    // Holiday/Seasonal
    'holiday-home': 'maison-vacances',
    'holiday_home': 'maison-vacances',
    'holidayhome': 'maison-vacances',
    'bien-saisonnier': 'bien-saisonnier',
    'seasonal': 'bien-saisonnier',

    // Secondary residence
    'secondary-residence': 'residence-secondaire',
    'secondary_residence': 'residence-secondaire',
    'secondaryresidence': 'residence-secondaire',

    // Castles/Chateaux
    'castle': 'chateau',
    'chateau': 'chateau',
    'chateaux': 'chateau',

    // Farm-related
    'farmhouse': 'corps-ferme',
    'farm-house': 'corps-ferme',
    'farm_house': 'corps-ferme',
    'farm': 'corps-ferme',
    'barn': 'grange',
    'grange': 'grange',

    // Outbuildings
    'outbuilding': 'dependance',
    'dependance': 'dependance',
    'atelier': 'atelier',
    'workshop': 'atelier',
    'hangar': 'hangar',
    'warehouse': 'hangar',

    // Professional spaces
    'professional-premises': 'local-professionnel',
    'professional_premises': 'local-professionnel',
    'local-professionnel': 'local-professionnel',
    'business': 'fonds-commerce',
    'fonds-commerce': 'fonds-commerce',
    'fonds-de-commerce': 'fonds-commerce',
    'fonds_de_commerce': 'fonds-commerce',

    // Other types
    'room': 'chambre',
    'chambre': 'chambre',
    'gite': 'gite',
    'camping': 'camping',
    'mas': 'mas',
    'loft': 'loft',
    'longere': 'longere',
    'etang': 'etang',
    'terrain-loisirs': 'terrain-loisirs',
    'terrain-de-loisirs': 'terrain-loisirs',
    'terrain_de_loisirs': 'terrain-loisirs',
    'terrain-agricole': 'terrain-agricole',
    'viager': 'viager',
    'colocation': 'colocation',
    'pecherie': 'pecherie',
  };

  // Step 4: Return canonical value if exists, otherwise return normalized
  return canonicalMapping[normalized] || normalized;
}
const OR_GROUPS = [
  ["terrasse", "balcon"],
  ["garage", "parking"],
  ["sud", "sud-ouest"]
];
function transactionKind(value: unknown): "sale" | "rent" | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  if (["vente", "achat", "acheter", "sale", "sell", "buy"].some((term) => normalized.includes(term))) return "sale";
  if (["location", "louer", "locatif", "rent", "rental"].some((term) => normalized.includes(term))) return "rent";
  return undefined;
}
function preFilterProperties(
  properties: BiensProfessionnels[],
  buyer: BuyerProfiles
): BiensProfessionnels[] {
  return properties.filter((property) => {
    // ===== SINGLE STORY LIVING REQUIREMENT CHECK =====
    // requiresSingleStoryLiving = true ONLY if BOTH:
    // - hasGroundFloorBedroom = true AND
    // - hasGroundFloorBathroom = true
    if (buyer.requiresSingleStoryLiving) {
      const hasGroundFloorBedroom = property.hasGroundFloorBedroom === true;
      const hasGroundFloorBathroom = property.hasGroundFloorBathroom === true;

      if (!(hasGroundFloorBedroom && hasGroundFloorBathroom)) {
        return false; // Property doesn't meet single story living requirement
      }
    }

    // ===== MANDATORY FEATURES FILTER WITH INTELLIGENT OR GROUPS =====
    // Check if property has ALL mandatory features required by buyer
    // This is a HARD filter - property must have ALL mandatory features
    // PRIORITY: Check new boolean fields FIRST, then fall back to CSV features
    const mandatoryFeatures = buyer.mandatoryFeatures
      ? buyer.mandatoryFeatures.split(',').map(f => f.trim().toLowerCase()).filter(f => f.length > 0)
      : [];
    if (mandatoryFeatures.length > 0) {
      // Map of feature names to their corresponding boolean fields on the property
      const booleanFieldMap: Record<string, boolean | undefined> = {
        'ground floor bedroom': property.hasGroundFloorBedroom,
        'ground floor bathroom': property.hasGroundFloorBathroom,
        'separate wc': property.hasSeparateWc,
        'carport': property.hasCarport,
        'fenced land': property.isLandFenced,
        'garage': property.hasGarage,
        'annex': property.hasAnnexe || property.hasAnnex,
        'pool': property.hasPiscine || property.hasSwimmingPool,
      };

      const featuresArray = normalizeFeatures(property.features);
      const propertyFeatures = featuresArray.map(f => String(f).trim().toLowerCase()).filter(f => f.length > 0);

      // 🔒 Vérification des critères obligatoires avec gestion OU
      const hasMandatoryFeatures = mandatoryFeatures.every(feature => {
        // Vérifier si ce critère appartient à un groupe OU
        const group = OR_GROUPS.find(g => g.includes(feature));

        if (!group) {
          // comportement normal (AND)
          // PRIORITY: Check boolean field first, then CSV features
          const booleanValue = booleanFieldMap[feature];
          if (booleanValue !== undefined) {
            return booleanValue === true;
          }
          return propertyFeatures.includes(feature);
        }

        // comportement OU : au moins un du groupe doit être présent
        const selectedInGroup = group.filter(f => mandatoryFeatures.includes(f));

        return selectedInGroup.some(f => {
          // PRIORITY: Check boolean field first, then CSV features
          const booleanValue = booleanFieldMap[f];
          if (booleanValue !== undefined) {
            return booleanValue === true;
          }
          return propertyFeatures.includes(f);
        });
      });

      if (!hasMandatoryFeatures) {
        return false;
      }
    }

    // ===== STRICT FILTER 1: GEOGRAPHIC DISTANCE (MANDATORY ELIMINATOR) =====
    // CRITICAL: Buyer's location is a strict eliminator criterion
    // Rule: Property MUST be in buyer's postal codes OR within exact search radius
    // NO TOLERANCE - the radius must be respected strictly

    // Check if property postal code matches buyer's postal codes (if available)
    let postalCodeMatch = false;
    if (buyer.postalCode && property.postalCode) {
      // Normalize postal codes for comparison
      const buyerPostalCodes = buyer.postalCode.split(',').map(pc => pc.trim());
      postalCodeMatch = buyerPostalCodes.includes(property.postalCode.trim());
    }

    // If postal code doesn't match, GPS distance check is MANDATORY
    if (!postalCodeMatch) {
      // GPS distance check is MANDATORY if postal code doesn't match
      // CRITICAL: If coordinates are missing, REJECT immediately (cannot validate location)
      if (
        property.latitude === undefined ||
        property.longitude === undefined ||
        buyer.latitude === undefined ||
        buyer.longitude === undefined ||
        !buyer.searchRadiusKm
      ) {
        // Cannot validate location (missing lat/lon or radius) - REJECT
        // Location validation is mandatory - no fallback allowed
        return false;
      }

      // Calculate distance with valid coordinates
      const distance = haversine(
        property.latitude,
        property.longitude,
        buyer.latitude,
        buyer.longitude
      );

      // STRICT: Distance must be <= searchRadius (NO TOLERANCE, NO 2x multiplier)
      if (distance > buyer.searchRadiusKm) {
        return false; // Property is outside search radius - REJECT
      }
    }

    // ===== STRICT FILTER 2: TRANSACTION TYPE =====
    // Hard rejection if transaction types don't match
    // Buyer wants 'sale' but property is 'rent' (or vice versa)
    const buyerTransaction = transactionKind(buyer.transactionType ?? buyer.operationType)
      ?? transactionKind(buyer.propertyType);
    const propertyTransaction = transactionKind(property.transactionType);
    if (buyerTransaction && propertyTransaction && buyerTransaction !== propertyTransaction) {
      return false;
    }

    // ===== STRICT FILTER 3: PROPERTY TYPE =====
    // Flexible matching: use includes logic instead of exact match
    // This allows for better compatibility between similar property types
    if (buyer.propertyType && property.propertyType && !transactionKind(buyer.propertyType)) {
      const buyerPropType = normalizePropertyType(buyer.propertyType);
      const propertyPropType = normalizePropertyType(property.propertyType);

      // Check if property type includes buyer type or vice versa (flexible matching)
      const isCompatibleType = buyerPropType.includes(propertyPropType) ||
                               propertyPropType.includes(buyerPropType) ||
                               buyerPropType === propertyPropType;

      if (!isCompatibleType) {
        return false;
      }
    }

    // ===== STRICT FILTER 4: BUDGET HARD LIMIT =====
    // Exclude properties exceeding budget by more than 10%
    // This is a hard filter to prevent matching with clearly out-of-budget properties
    if (buyer.budgetMax !== undefined && property.price !== undefined) {
      if (property.price > buyer.budgetMax * 1.10) {
        return false; // Property exceeds budget by more than 10%
      }
    }

    // All other criteria are now evaluated in scoring with gradual penalties
    // No hard filters here - everything gets scored
    return true;
  });
}

/**
 * Detailed breakdown of a matching score
 * Shows which criteria matched and which did not
 */
export interface MatchingScoreBreakdown {
  totalScore: number;
  criteria: {
    name: string;
    matched: boolean;
    points: number;
    maxPoints: number;
    description: string;
  }[];
  bonusPoints: number;
  summary: string;
}

/**
 * Calculate detailed matching score breakdown between a property and a buyer
 * This function returns the same score as calculateMatchingScore but also provides
 * a detailed breakdown of which criteria matched and which did not
 *
 * @param property - The property to evaluate
 * @param buyer - The buyer profile to match against
 * @returns MatchingScoreBreakdown with detailed criteria information
 */
// The detailed logger path is disabled by the engine call; no-op definitions keep the Wix scorer unchanged.
const logDistanceCalculation = (..._args: any[]) => {};
const logPriceCalculation = (..._args: any[]) => {};
const logSurfaceCalculation = (..._args: any[]) => {};
const logRoomsCalculation = (..._args: any[]) => {};
const logBedroomsCalculation = (..._args: any[]) => {};
const logBonusPoints = (..._args: any[]) => {};
const logPenalties = (..._args: any[]) => {};
const logMatchingScoreCalculation = (..._args: any[]) => {};
export function calculateMatchingScore(
  property: BiensProfessionnels,
  buyer: BuyerProfiles,
  enableDetailedLogging: boolean = false
): number {
  try {
    let points = 0;
    let maxPoints = 0;
    const scoreBreakdown: {
      section: string;
      criteria: string;
      weight: number;
      maxPoints: number;
      earnedPoints: number;
      percentage: number;
      details: Record<string, any>;
      matched: boolean;
    }[] = [];
    const bonusesApplied: { name: string; points: number }[] = [];
    const penaltiesApplied: { name: string; amount: number; reason: string }[] = [];

    // ===== INITIALIZE ALL SCORING VARIABLES =====
    // CRITICAL: Initialize all variables to prevent ReferenceError if sections are skipped
    let locationPoints = 0;
    let pricePoints = 0;
    let surfacePoints = 0;
    let roomsPoints = 0;
    let landSurfacePoints = 0;
    let bedroomsPoints = 0;
    let bathroomsPoints = 0;
    let mandatoryFeaturesPoints = 0;

  // ===== LOCATION SCORING (max 25 points) =====
  // Distance-based progressive scoring with STRICT radius enforcement
  // CRITICAL: Only score properties that are within the exact search radius
  // NO TOLERANCE - properties beyond searchRadius get 0 points
  locationPoints = 0;
  if (
    buyer.latitude !== undefined &&
    buyer.longitude !== undefined &&
    buyer.searchRadiusKm !== undefined &&
    property.latitude !== undefined &&
    property.longitude !== undefined
  ) {
    maxPoints += 25;
    const distance = haversine(
      property.latitude,
      property.longitude,
      buyer.latitude,
      buyer.longitude
    );
    const searchRadius = buyer.searchRadiusKm;

    if (distance <= searchRadius * 0.5) {
      // Within 50% of radius: full points
      locationPoints = 25;
    } else if (distance <= searchRadius) {
      // Linear interpolation: 25 to 15 points
      const ratio = (distance - searchRadius * 0.5) / (searchRadius * 0.5);
      locationPoints = Math.round(25 - (10 * ratio));
    } else {
      // STRICT: Beyond search radius = 0 points (no tolerance)
      locationPoints = 0;
    }
    points += locationPoints;

    if (enableDetailedLogging) {
      logDistanceCalculation(property, buyer, distance, searchRadius, locationPoints, 25);
      scoreBreakdown.push({
        section: 'LOCATION',
        criteria: 'Distance from buyer location',
        weight: 25,
        maxPoints: 25,
        earnedPoints: locationPoints,
        percentage: Math.round((locationPoints / 25) * 100),
        details: {
          'Property Location': `(${property.latitude}, ${property.longitude})`,
          'Buyer Location': `(${buyer.latitude}, ${buyer.longitude})`,
          'Distance': `${distance.toFixed(1)}km`,
          'Search Radius': `${searchRadius}km`,
          'Status': distance <= searchRadius ? 'Within radius' : distance <= searchRadius * 2 ? 'Slightly outside' : 'Far outside'
        },
        matched: locationPoints >= 15
      });
    }
  }

  // ===== PRICE COMPATIBILITY SCORING (max 25 points) =====
  // Progressive scoring: decreases gradually as price moves away from desired range
  pricePoints = 0;
  if (buyer.budgetMin !== undefined && buyer.budgetMax !== undefined && property.price !== undefined) {
    maxPoints += 25;
    const budgetMin = buyer.budgetMin;
    const budgetMax = buyer.budgetMax;
    const budgetRange = budgetMax - budgetMin;
    const tolerance = Math.max(budgetRange * 0.15, 15000);

    if (property.price >= budgetMin && property.price <= budgetMax) {
      pricePoints = 25;
    } else if (property.price < budgetMin) {
      const deficit = budgetMin - property.price;
      if (deficit <= tolerance * 0.5) {
        const ratio = deficit / (tolerance * 0.5);
        pricePoints = Math.round(25 - (7 * ratio));
      } else if (deficit <= tolerance) {
        const ratio = (deficit - tolerance * 0.5) / (tolerance * 0.5);
        pricePoints = Math.round(18 - (6 * ratio));
      } else if (deficit <= tolerance * 1.5) {
        const ratio = (deficit - tolerance) / (tolerance * 0.5);
        pricePoints = Math.round(12 - (7 * ratio));
      } else if (deficit <= tolerance * 2) {
        const ratio = (deficit - tolerance * 1.5) / (tolerance * 0.5);
        pricePoints = Math.round(5 - (5 * ratio));
      }
    } else if (property.price > budgetMax) {
      const excess = property.price - budgetMax;
      if (excess <= tolerance * 0.5) {
        const ratio = excess / (tolerance * 0.5);
        pricePoints = Math.round(25 - (7 * ratio));
      } else if (excess <= tolerance) {
        const ratio = (excess - tolerance * 0.5) / (tolerance * 0.5);
        pricePoints = Math.round(18 - (6 * ratio));
      } else if (excess <= tolerance * 1.5) {
        const ratio = (excess - tolerance) / (tolerance * 0.5);
        pricePoints = Math.round(12 - (7 * ratio));
      } else if (excess <= tolerance * 2) {
        const ratio = (excess - tolerance * 1.5) / (tolerance * 0.5);
        pricePoints = Math.round(5 - (5 * ratio));
      }
    }
    points += pricePoints;

    if (enableDetailedLogging) {
      logPriceCalculation(property, buyer, pricePoints, 25);
      scoreBreakdown.push({
        section: 'PRICE',
        criteria: 'Budget compatibility',
        weight: 25,
        maxPoints: 25,
        earnedPoints: pricePoints,
        percentage: Math.round((pricePoints / 25) * 100),
        details: {
          'Property Price': `€${property.price.toLocaleString()}`,
          'Budget Range': `€${budgetMin.toLocaleString()} - €${budgetMax.toLocaleString()}`,
          'Difference': property.price < budgetMin ? `€${(budgetMin - property.price).toLocaleString()} below` : property.price > budgetMax ? `€${(property.price - budgetMax).toLocaleString()} above` : 'Within range',
          'Tolerance': `€${tolerance.toLocaleString()}`
        },
        matched: pricePoints >= 18
      });
    }
  }

  // ===== SURFACE HABITABLE SCORING (max 20 points) =====
  // CRITICAL: Strict penalties for surface mismatches
  surfacePoints = 0;
  if (buyer.surfaceHouseMin !== undefined && buyer.surfaceHouseMax !== undefined && property.surface !== undefined) {
    maxPoints += 20;
    const surfaceMin = buyer.surfaceHouseMin;
    const surfaceMax = buyer.surfaceHouseMax;
    const surfaceRange = surfaceMax - surfaceMin;
    const tolerance = Math.max(surfaceRange * 0.05, 5);

    if (property.surface >= surfaceMin && property.surface <= surfaceMax) {
      surfacePoints = 20;
    } else if (property.surface < surfaceMin) {
      const deficit = surfaceMin - property.surface;
      if (deficit <= tolerance * 0.25) {
        const ratio = deficit / (tolerance * 0.25);
        surfacePoints = Math.round(20 - (2 * ratio));
      } else if (deficit <= tolerance * 0.5) {
        const ratio = (deficit - tolerance * 0.25) / (tolerance * 0.25);
        surfacePoints = Math.round(18 - (6 * ratio));
      } else if (deficit <= tolerance) {
        const ratio = (deficit - tolerance * 0.5) / (tolerance * 0.5);
        surfacePoints = Math.round(12 - (8 * ratio));
      } else if (deficit <= tolerance * 1.5) {
        const ratio = (deficit - tolerance) / (tolerance * 0.5);
        surfacePoints = Math.round(4 - (4 * ratio));
      }
    } else if (property.surface > surfaceMax) {
      const excess = property.surface - surfaceMax;
      if (excess <= tolerance * 0.5) {
        const ratio = excess / (tolerance * 0.5);
        surfacePoints = Math.round(20 - (5 * ratio));
      } else if (excess <= tolerance) {
        const ratio = (excess - tolerance * 0.5) / (tolerance * 0.5);
        surfacePoints = Math.round(15 - (5 * ratio));
      } else if (excess <= tolerance * 1.5) {
        const ratio = (excess - tolerance) / (tolerance * 0.5);
        surfacePoints = Math.round(10 - (5 * ratio));
      } else if (excess <= tolerance * 2) {
        const ratio = (excess - tolerance * 1.5) / (tolerance * 0.5);
        surfacePoints = Math.round(5 - (5 * ratio));
      }
    }
    points += surfacePoints;

    if (enableDetailedLogging) {
      logSurfaceCalculation(property, buyer, surfacePoints, 20);
      scoreBreakdown.push({
        section: 'SURFACE',
        criteria: 'Habitable surface area',
        weight: 20,
        maxPoints: 20,
        earnedPoints: surfacePoints,
        percentage: Math.round((surfacePoints / 20) * 100),
        details: {
          'Property Surface': `${property.surface}m²`,
          'Desired Range': `${surfaceMin}m² - ${surfaceMax}m²`,
          'Difference': property.surface < surfaceMin ? `${(surfaceMin - property.surface)}m² below` : property.surface > surfaceMax ? `${(property.surface - surfaceMax)}m² above` : 'Within range',
          'Tolerance': `${tolerance.toFixed(0)}m²`
        },
        matched: surfacePoints >= 15
      });
    }
  } else if (buyer.surfaceHouseMin !== undefined && property.surface !== undefined) {
    maxPoints += 20;
    const deficit = buyer.surfaceHouseMin - property.surface;
    const tolerance = Math.max(buyer.surfaceHouseMin * 0.05, 5);

    if (property.surface >= buyer.surfaceHouseMin) {
      points += 20;
      surfacePoints = 20;
    } else if (deficit <= tolerance * 0.25) {
      const ratio = deficit / (tolerance * 0.25);
      surfacePoints = Math.round(20 - (2 * ratio));
      points += surfacePoints;
    } else if (deficit <= tolerance * 0.5) {
      const ratio = (deficit - tolerance * 0.25) / (tolerance * 0.25);
      surfacePoints = Math.round(18 - (6 * ratio));
      points += surfacePoints;
    } else if (deficit <= tolerance) {
      const ratio = (deficit - tolerance * 0.5) / (tolerance * 0.5);
      surfacePoints = Math.round(12 - (8 * ratio));
      points += surfacePoints;
    } else if (deficit <= tolerance * 1.5) {
      const ratio = (deficit - tolerance) / (tolerance * 0.5);
      surfacePoints = Math.round(4 - (4 * ratio));
      points += surfacePoints;
    }

    if (enableDetailedLogging) {
      logSurfaceCalculation(property, buyer, surfacePoints, 20);
      scoreBreakdown.push({
        section: 'SURFACE',
        criteria: 'Habitable surface area (minimum)',
        weight: 20,
        maxPoints: 20,
        earnedPoints: surfacePoints,
        percentage: Math.round((surfacePoints / 20) * 100),
        details: {
          'Property Surface': `${property.surface}m²`,
          'Minimum Required': `${buyer.surfaceHouseMin}m²`,
          'Difference': property.surface < buyer.surfaceHouseMin ? `${(buyer.surfaceHouseMin - property.surface)}m² below` : 'Meets minimum'
        },
        matched: surfacePoints >= 15
      });
    }
  }

  // ===== ROOMS SCORING (max 15 points) =====
  // Range-based progressive scoring with tolerance
  if (buyer.minRooms !== undefined && buyer.maxRooms !== undefined && property.rooms !== undefined) {
    maxPoints += 15;

    if (property.rooms >= buyer.minRooms && property.rooms <= buyer.maxRooms) {
      // Within range: full points
      points += 15;
      roomsPoints = 15;
    } else if (property.rooms < buyer.minRooms) {
      const deficit = buyer.minRooms - property.rooms;
      if (deficit === 1) {
        points += 10;  // 1 room short: 10 points
        roomsPoints = 10;
      } else if (deficit === 2) {
        points += 5;   // 2 rooms short: 5 points
        roomsPoints = 5;
      }
      // 3+ rooms short: 0 points
    } else if (property.rooms > buyer.maxRooms) {
      const excess = property.rooms - buyer.maxRooms;
      if (excess === 1) {
        points += 10;  // 1 room extra: 10 points
        roomsPoints = 10;
      } else if (excess === 2) {
        points += 5;   // 2 rooms extra: 5 points
        roomsPoints = 5;
      }
      // 3+ rooms extra: 0 points
    }

    if (enableDetailedLogging) {
      logRoomsCalculation(property, buyer, roomsPoints, 15);
      scoreBreakdown.push({
        section: 'ROOMS',
        criteria: 'Number of rooms',
        weight: 15,
        maxPoints: 15,
        earnedPoints: roomsPoints,
        percentage: Math.round((roomsPoints / 15) * 100),
        details: {
          'Property Rooms': `${property.rooms}`,
          'Desired Range': `${buyer.minRooms} - ${buyer.maxRooms}`,
          'Difference': property.rooms < buyer.minRooms ? `${(buyer.minRooms - property.rooms)} short` : property.rooms > buyer.maxRooms ? `${(property.rooms - buyer.maxRooms)} extra` : 'Within range'
        },
        matched: roomsPoints >= 10
      });
    }
  } else if (buyer.minRooms !== undefined && property.rooms !== undefined) {
    // Only minimum specified
    maxPoints += 15;

    if (property.rooms >= buyer.minRooms) {
      // Meets minimum: full points
      points += 15;
      roomsPoints = 15;
    } else if (property.rooms === buyer.minRooms - 1) {
      // 1 room short: partial points
      points += 10;
      roomsPoints = 10;
    } else if (property.rooms === buyer.minRooms - 2) {
      // 2 rooms short: small points
      points += 5;
      roomsPoints = 5;
    }

    if (enableDetailedLogging) {
      logRoomsCalculation(property, buyer, roomsPoints, 15);
      scoreBreakdown.push({
        section: 'ROOMS',
        criteria: 'Number of rooms (minimum)',
        weight: 15,
        maxPoints: 15,
        earnedPoints: roomsPoints,
        percentage: Math.round((roomsPoints / 15) * 100),
        details: {
          'Property Rooms': `${property.rooms}`,
          'Minimum Required': `${buyer.minRooms}`,
          'Difference': property.rooms < buyer.minRooms ? `${(buyer.minRooms - property.rooms)} short` : 'Meets minimum'
        },
        matched: roomsPoints >= 10
      });
    }
  }

  // ===== RADIUS PROXIMITY BONUS (max 5 points) =====
  // Reduced bonus for properties within buyer's preferred search radius
  // OPTIMIZATION: Reduced from 15 to 5 points to balance distance weight
  if (
    buyer.latitude !== undefined &&
    buyer.longitude !== undefined &&
    buyer.searchRadiusKm !== undefined &&
    property.latitude !== undefined &&
    property.longitude !== undefined
  ) {
    maxPoints += 5;
    const distance = haversine(
      property.latitude,
      property.longitude,
      buyer.latitude,
      buyer.longitude
    );
    const searchRadius = buyer.searchRadiusKm;

    if (distance <= searchRadius) {
      // Within radius: full bonus
      points += 5;
    } else if (distance <= searchRadius * 1.2) {
      // Slightly outside: partial bonus
      points += 3;
    } else if (distance <= searchRadius * 1.5) {
      // Moderately outside: small bonus
      points += 1;
    }
    // Beyond 1.5x: 0 bonus points
  }

  // ===== LAND SURFACE SCORING (max 10 points) =====
  // CRITICAL: Strict penalties for land surface mismatches - this is a MANDATORY criterion
  // Properties significantly below minimum land surface should NOT be classified as perfect matches
  if (buyer.landSurfaceMin !== undefined && buyer.landSurfaceMax !== undefined && property.landSurface !== undefined) {
    maxPoints += 10;
    const landMin = buyer.landSurfaceMin;
    const landMax = buyer.landSurfaceMax;
    const landRange = landMax - landMin;
    // STRICTER: 5% of range or 25m² (was 10% or 50m²)
    const tolerance = Math.max(landRange * 0.05, 25);

    if (property.landSurface >= landMin && property.landSurface <= landMax) {
      // Within range: full points
      points += 10;
    } else if (property.landSurface < landMin) {
      // CRITICAL: Much stricter penalties for undersized land
      const deficit = landMin - property.landSurface;
      if (deficit <= tolerance * 0.25) {
        // Very slightly below: 10 to 8 points
        const ratio = deficit / (tolerance * 0.25);
        points += Math.round(10 - (2 * ratio));
      } else if (deficit <= tolerance * 0.5) {
        // Slightly below: 8 to 5 points
        const ratio = (deficit - tolerance * 0.25) / (tolerance * 0.25);
        points += Math.round(8 - (3 * ratio));
      } else if (deficit <= tolerance) {
        // Moderately below: 5 to 1 point
        const ratio = (deficit - tolerance * 0.5) / (tolerance * 0.5);
        points += Math.round(5 - (4 * ratio));
      }
      // Beyond tolerance: 0 points (was 1.5x)
    } else if (property.landSurface > landMax) {
      // Oversized land gets less penalty (buyers can live with extra land)
      const excess = property.landSurface - landMax;
      if (excess <= tolerance * 0.5) {
        // Slightly above: 10 to 7 points
        const ratio = excess / (tolerance * 0.5);
        points += Math.round(10 - (3 * ratio));
      } else if (excess <= tolerance) {
        // Moderately above: 7 to 4 points
        const ratio = (excess - tolerance * 0.5) / (tolerance * 0.5);
        points += Math.round(7 - (3 * ratio));
      } else if (excess <= tolerance * 1.5) {
        // Significantly above: 4 to 1 point
        const ratio = (excess - tolerance) / (tolerance * 0.5);
        points += Math.round(4 - (3 * ratio));
      }
    }
  } else if (buyer.landSurfaceMin !== undefined && property.landSurface !== undefined) {
    // Only minimum specified - CRITICAL: Strict penalties
    maxPoints += 10;
    const deficit = buyer.landSurfaceMin - property.landSurface;
    // STRICTER: 5% or 25m² (was 10% or 50m²)
    const tolerance = Math.max(buyer.landSurfaceMin * 0.05, 25);

    if (property.landSurface >= buyer.landSurfaceMin) {
      // Meets minimum: full points
      points += 10;
    } else if (deficit <= tolerance * 0.25) {
      // Very slightly below: 10 to 8 points
      const ratio = deficit / (tolerance * 0.25);
      points += Math.round(10 - (2 * ratio));
    } else if (deficit <= tolerance * 0.5) {
      // Slightly below: 8 to 5 points
      const ratio = (deficit - tolerance * 0.25) / (tolerance * 0.25);
      points += Math.round(8 - (3 * ratio));
    } else if (deficit <= tolerance) {
      // Moderately below: 5 to 1 point
      const ratio = (deficit - tolerance * 0.5) / (tolerance * 0.5);
      points += Math.round(5 - (4 * ratio));
    }
  }

  // ===== BEDROOMS SCORING (max 10 points) =====
  // Range-based progressive scoring with tolerance
  if (buyer.bedroomsMin !== undefined && buyer.bedroomsMax !== undefined && property.bedrooms !== undefined) {
    maxPoints += 10;

    if (property.bedrooms >= buyer.bedroomsMin && property.bedrooms <= buyer.bedroomsMax) {
      // Within range: full points
      points += 10;
      bedroomsPoints = 10;
    } else if (property.bedrooms < buyer.bedroomsMin) {
      const deficit = buyer.bedroomsMin - property.bedrooms;
      if (deficit === 1) {
        points += 7;  // 1 bedroom short: 7 points
        bedroomsPoints = 7;
      } else if (deficit === 2) {
        points += 3;  // 2 bedrooms short: 3 points
        bedroomsPoints = 3;
      }
      // 3+ bedrooms short: 0 points
    } else if (property.bedrooms > buyer.bedroomsMax) {
      const excess = property.bedrooms - buyer.bedroomsMax;
      if (excess === 1) {
        points += 7;  // 1 bedroom extra: 7 points
        bedroomsPoints = 7;
      } else if (excess === 2) {
        points += 3;  // 2 bedrooms extra: 3 points
        bedroomsPoints = 3;
      }
      // 3+ bedrooms extra: 0 points
    }

    if (enableDetailedLogging) {
      logBedroomsCalculation(property, buyer, bedroomsPoints, 10);
      scoreBreakdown.push({
        section: 'BEDROOMS',
        criteria: 'Number of bedrooms',
        weight: 10,
        maxPoints: 10,
        earnedPoints: bedroomsPoints,
        percentage: Math.round((bedroomsPoints / 10) * 100),
        details: {
          'Property Bedrooms': `${property.bedrooms}`,
          'Desired Range': `${buyer.bedroomsMin} - ${buyer.bedroomsMax}`,
          'Difference': property.bedrooms < buyer.bedroomsMin ? `${(buyer.bedroomsMin - property.bedrooms)} short` : property.bedrooms > buyer.bedroomsMax ? `${(property.bedrooms - buyer.bedroomsMax)} extra` : 'Within range'
        },
        matched: bedroomsPoints >= 7
      });
    }
  } else if (buyer.bedroomsMin !== undefined && property.bedrooms !== undefined) {
    // Only minimum specified
    maxPoints += 10;

    if (property.bedrooms >= buyer.bedroomsMin) {
      // Meets minimum: full points
      points += 10;
      bedroomsPoints = 10;
    } else if (property.bedrooms === buyer.bedroomsMin - 1) {
      // 1 bedroom short: partial points
      points += 7;
      bedroomsPoints = 7;
    } else if (property.bedrooms === buyer.bedroomsMin - 2) {
      // 2 bedrooms short: small points
      points += 3;
      bedroomsPoints = 3;
    }

    if (enableDetailedLogging) {
      logBedroomsCalculation(property, buyer, bedroomsPoints, 10);
      scoreBreakdown.push({
        section: 'BEDROOMS',
        criteria: 'Number of bedrooms (minimum)',
        weight: 10,
        maxPoints: 10,
        earnedPoints: bedroomsPoints,
        percentage: Math.round((bedroomsPoints / 10) * 100),
        details: {
          'Property Bedrooms': `${property.bedrooms}`,
          'Minimum Required': `${buyer.bedroomsMin}`,
          'Difference': property.bedrooms < buyer.bedroomsMin ? `${(buyer.bedroomsMin - property.bedrooms)} short` : 'Meets minimum'
        },
        matched: bedroomsPoints >= 7
      });
    }
  }

  // ===== BATHROOMS SCORING (max 5 points) =====
  // Threshold-based scoring
  if (buyer.bathroomsMin !== undefined && property.bathrooms !== undefined) {
    maxPoints += 5;

    if (property.bathrooms >= buyer.bathroomsMin) {
      // Meets minimum: full points
      points += 5;
    } else if (property.bathrooms === buyer.bathroomsMin - 1) {
      // 1 bathroom short: partial points
      points += 3;
    }
    // 2+ bathrooms short: 0 points
  }

  // ===== OPTIONAL BONUS CRITERIA (not counted in max) =====
  let bonusPoints = 0;

  // Property Type Match: +5 bonus points
  if (buyer.propertyType && property.propertyType) {
    if (normalizePropertyType(property.propertyType) === normalizePropertyType(buyer.propertyType)) {
      bonusPoints += 5;
      bonusesApplied.push({ name: 'Property type match', points: 5 });
    }
  }

  // City Match: +5 bonus points
  if (property.city && buyer.city) {
    if (property.city.toLowerCase() === buyer.city.toLowerCase()) {
      bonusPoints += 5;
      bonusesApplied.push({ name: 'City match', points: 5 });
    }
  }

  // Secondary Postal Code Match: +3 bonus points
  // Check if property postal code is in buyer's secondary postal codes
  if (buyer.secondaryPostalCodes && property.postalCode) {
    const secondaryPostalCodesArray = buyer.secondaryPostalCodes.split(',').map(pc => pc.trim());
    if (secondaryPostalCodesArray.includes(property.postalCode)) {
      bonusPoints += 3;
      bonusesApplied.push({ name: 'Secondary postal code match', points: 3 });
    }
  }

  // ===== DESIRED CRITERIA SCORING (soft bonuses) =====
  // These criteria improve the score but do NOT exclude properties
  // Priority: Check new boolean fields FIRST, then fall back to CSV features
  let desiredCriteriaBonus = 0;

  // Ground Floor Bedroom: +2 bonus points
  if (buyer.wantsGroundFloorBedroom && property.hasGroundFloorBedroom === true) {
    desiredCriteriaBonus += 2;
  }

  // Ground Floor Bathroom: +2 bonus points
  if (buyer.wantsGroundFloorBathroom && property.hasGroundFloorBathroom === true) {
    desiredCriteriaBonus += 2;
  }

  // Separate WC: +1 bonus point
  if (buyer.wantsSeparateWc && property.hasSeparateWc === true) {
    desiredCriteriaBonus += 1;
  }

  // Carport: +1 bonus point
  if (buyer.wantsCarport && property.hasCarport === true) {
    desiredCriteriaBonus += 1;
  }

  // Fenced Land: +1 bonus point
  if (buyer.wantsFencedLand && property.isLandFenced === true) {
    desiredCriteriaBonus += 1;
  }

  bonusPoints += Math.min(desiredCriteriaBonus, 7); // Cap desired criteria at 7 points

  // Extra Features: +5 bonus points
  let featureBonus = 0;
  const featuresApplied: string[] = [];
  if (buyer.wantsGarage && property.hasGarage) {
    featureBonus += 2;
    featuresApplied.push('Garage');
  }
  if ((buyer.wantsAnnexe || buyer.wantsAnnex) && (property.hasAnnexe || property.hasAnnex)) {
    featureBonus += 2;
    featuresApplied.push('Annex');
  }
  if ((buyer.wantsPiscine || buyer.wantsSwimmingPool) && (property.hasPiscine || property.hasSwimmingPool)) {
    featureBonus += 1;
    featuresApplied.push('Pool');
  }
  const cappedFeatureBonus = Math.min(featureBonus, 5);
  bonusPoints += cappedFeatureBonus;
  if (cappedFeatureBonus > 0) {
    bonusesApplied.push({ name: `Features match (${featuresApplied.join(', ')})`, points: cappedFeatureBonus });
  }

  // Cellier Match: +3 bonus points
  if ((buyer?.wantsCellier ?? false) && (property?.hasCellier ?? false)) {
    bonusPoints += 3;
    bonusesApplied.push({ name: 'Cellier match', points: 3 });
  }

  // Recent Property Match: +5 bonus points
  if ((buyer?.wantsRecent ?? false) && isRecentProperty(property)) {
    bonusPoints += 5;
    bonusesApplied.push({ name: 'Recent property match', points: 5 });
  }

  // ===== CAP TOTAL BONUS POINTS AT 15 =====
  // Limit the total bonus points to a maximum of 15 to prevent excessive score inflation
  const cappedBonusPoints = Math.min(bonusPoints, 15);

  if (enableDetailedLogging && bonusesApplied.length > 0) {
    logBonusPoints(bonusesApplied);
  }

  // ===== CALCULATE BASE SCORE =====
  if (maxPoints === 0) {
    return 0;
  }

  const baseScore = (points / maxPoints) * 100;

  // ===== CRITICAL: APPLY MANDATORY CRITERIA PENALTY =====
  // If surface or land surface are significantly below minimum (>20% deficit),
  // apply a SEVERE penalty to prevent high scores for non-compliant properties
  let mandatoryCriteriaPenalty = 0;

  if (buyer.surfaceHouseMin !== undefined && property.surface !== undefined) {
    const surfaceDeficit = buyer.surfaceHouseMin - property.surface;
    const surfaceTolerance = Math.max(buyer.surfaceHouseMin * 0.05, 5);

    // If deficit exceeds 20% of minimum surface, apply severe penalty
    if (surfaceDeficit > buyer.surfaceHouseMin * 0.2) {
      // Penalty increases with deficit severity
      const deficitPercentage = (surfaceDeficit / buyer.surfaceHouseMin) * 100;
      const penalty = Math.min(deficitPercentage * 0.5, 30); // Up to 30% penalty
      mandatoryCriteriaPenalty += penalty;
      penaltiesApplied.push({
        name: 'Surface deficit penalty',
        amount: Math.round(penalty),
        reason: `Surface ${surfaceDeficit.toFixed(0)}m² below minimum (${deficitPercentage.toFixed(1)}% deficit)`
      });
    }
  }

  if (buyer.landSurfaceMin !== undefined && property.landSurface !== undefined) {
    const landDeficit = buyer.landSurfaceMin - property.landSurface;
    const landTolerance = Math.max(buyer.landSurfaceMin * 0.05, 25);

    // If deficit exceeds 20% of minimum land surface, apply severe penalty
    if (landDeficit > buyer.landSurfaceMin * 0.2) {
      // Penalty increases with deficit severity
      const deficitPercentage = (landDeficit / buyer.landSurfaceMin) * 100;
      const penalty = Math.min(deficitPercentage * 0.5, 30); // Up to 30% penalty
      mandatoryCriteriaPenalty += penalty;
      penaltiesApplied.push({
        name: 'Land surface deficit penalty',
        amount: Math.round(penalty),
        reason: `Land ${landDeficit.toFixed(0)}m² below minimum (${deficitPercentage.toFixed(1)}% deficit)`
      });
    }
  }

  // Apply the mandatory criteria penalty
  const scoreAfterMandatoryPenalty = Math.max(baseScore - mandatoryCriteriaPenalty, 0);

  // ===== APPLY STYLE BONUS (BEFORE global cap) =====
  // Property Style Match: +20 bonus points (applied BEFORE global cap for maximum impact)
  // Only applied if BOTH buyer AND property have style specified
  let styleBonus = 0;
  if (buyer.propertyStylePreferences && property.propertyStyle) {
    // Normalize function: trim, lowercase, remove accents
    const normalizeStyle = (s: string) =>
      s.trim()
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '');

    const stylePreferences = buyer.propertyStylePreferences
      .split(',')
      .map(s => normalizeStyle(s))
      .filter(s => s.length > 0);
    const propertyStyleNormalized = normalizeStyle(property.propertyStyle);

    if (stylePreferences.includes(propertyStyleNormalized)) {
      styleBonus = 20;
      bonusesApplied.push({ name: 'Property style match', points: 20 });
    }
  }

  // ===== APPLY OTHER BONUSES (capped at 10% of base score) =====
  // Construction Year Range Match: +10 bonus points
  let otherBonus = 0;
  if (property.constructionYear) {
    const yearMin = buyer.constructionYearMin || 0;
    const yearMax = buyer.constructionYearMax || new Date().getFullYear();

    if (property.constructionYear >= yearMin && property.constructionYear <= yearMax) {
      otherBonus += 10;
      bonusesApplied.push({ name: 'Construction year match', points: 10 });
    }
  }

  // Cap other bonuses at 10% of base score
  const cappedOtherBonus = Math.min(otherBonus, scoreAfterMandatoryPenalty * 0.1);

  // Final score: base (after mandatory penalty) + capped bonus points + style bonus (uncapped) + other bonuses (capped)
  const finalScore = Math.min(scoreAfterMandatoryPenalty + cappedBonusPoints + styleBonus + cappedOtherBonus, 100);

  if (enableDetailedLogging && penaltiesApplied.length > 0) {
    logPenalties(penaltiesApplied);
  }

  // CRITICAL: Wrap logger in try/catch to prevent logging errors from breaking the matching score
  // The logger is informational only and must NEVER crash the matching calculation
  if (enableDetailedLogging) {
    try {
      logMatchingScoreCalculation(
        property,
        buyer,
        scoreBreakdown,
        maxPoints,
        points,
        cappedBonusPoints,
        penaltiesApplied,
        Math.round(finalScore),
        true
      );
    } catch (logError) {
      console.warn('[MATCHING LOGGER ERROR - IGNORED]', logError);
      // Continue execution - logging errors must not affect the score
    }
  }

  return Math.round(finalScore);
  } catch (error) {
    console.error('[MATCHING SCORE ERROR] Critical error in calculateMatchingScore:', error);
    return 0;
  }
}
export function calculateWixMatchingScore(property: BiensProfessionnels, buyer: BuyerProfiles): number {
  return calculateMatchingScore(property, buyer, false);
}
export function passesWixStrictMatchingFilters(property: BiensProfessionnels, buyer: BuyerProfiles): boolean {
  return preFilterProperties([property], buyer).length > 0;
}

type PrivateProperty = Record<string, any>;
type BuyerSearchLocation = { city?: string; postalCode?: string; latitude?: number; longitude?: number };

function normalizeLocationText(value: unknown): string {
  return String(value ?? "").trim().toLocaleLowerCase("fr-FR");
}

function normalizePostalCode(value: unknown): string {
  return String(value ?? "").trim();
}

function privateSecondaryLocations(buyer: BuyerProfiles): BuyerSearchLocation[] {
  const value = buyer.secondaryLocations;
  if (Array.isArray(value)) return value.filter((location) => location && typeof location === "object");
  if (typeof value === "string" && value.trim()) {
    try {
      const parsed: unknown = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.filter((location) => location && typeof location === "object");
    } catch { /* Invalid legacy JSON means no secondary location. */ }
  }
  return [];
}

function privateExplicitPostalCodes(buyer: BuyerProfiles): string[] {
  const value = buyer.postalCodes;
  if (Array.isArray(value)) return value.map(normalizePostalCode).filter(Boolean);
  if (typeof value === "string") return value.split(/[,\n;|]+/).map(normalizePostalCode).filter(Boolean);
  return [];
}

function matchesPrivateExactLocation(
  property: PrivateProperty,
  buyer: BuyerProfiles,
  secondaryLocations: BuyerSearchLocation[],
  explicitPostalCodes: string[],
): boolean {
  const propertyCity = normalizeLocationText(property.city);
  const propertyPostalCode = normalizePostalCode(property.postalCode);
  const locations = [{ city: buyer.city, postalCode: buyer.postalCode }, ...secondaryLocations];
  if (locations.some((location) =>
    (Boolean(propertyCity) && Boolean(normalizeLocationText(location.city)) && propertyCity === normalizeLocationText(location.city)) ||
    (Boolean(propertyPostalCode) && Boolean(normalizePostalCode(location.postalCode)) && propertyPostalCode === normalizePostalCode(location.postalCode))
  )) return true;
  return Boolean(propertyPostalCode) && explicitPostalCodes.includes(propertyPostalCode);
}

function isPrivatePropertyInBuyerArea(property: PrivateProperty, buyer: BuyerProfiles): boolean {
  const radius = Number(buyer.searchRadiusKm ?? 0);
  const hasRadius = Number.isFinite(radius) && radius > 0;
  const secondaryLocations = privateSecondaryLocations(buyer);
  const postalCodes = privateExplicitPostalCodes(buyer);
  if (!hasRadius && secondaryLocations.length === 0 && postalCodes.length === 0) return false;
  if (!hasRadius) return matchesPrivateExactLocation(property, buyer, secondaryLocations, postalCodes);

  const propertyLat = property.latitude, propertyLon = property.longitude;
  const centers: BuyerSearchLocation[] = [
    { city: buyer.city, postalCode: buyer.postalCode, latitude: buyer.latitude, longitude: buyer.longitude },
    ...secondaryLocations,
  ];
  let distanceComputed = false;
  if (typeof propertyLat === "number" && Number.isFinite(propertyLat) &&
      typeof propertyLon === "number" && Number.isFinite(propertyLon)) {
    for (const center of centers) {
      if (typeof center.latitude !== "number" || !Number.isFinite(center.latitude) ||
          typeof center.longitude !== "number" || !Number.isFinite(center.longitude)) continue;
      const distance = getDistance(center.latitude, center.longitude, propertyLat, propertyLon);
      if (distance !== null && Number.isFinite(distance)) {
        distanceComputed = true;
        if (distance <= radius) return true;
      }
    }
  }
  if (distanceComputed) return false;
  return matchesPrivateExactLocation(property, buyer, secondaryLocations, postalCodes);
}

export function calculateWixPrivatePropertyBuyerScore(property: PrivateProperty, buyer: BuyerProfiles): number {
  if (!isPrivatePropertyInBuyerArea(property, buyer)) return 0;
  const converted: BiensProfessionnels = {
    _id: property._id,
    latitude: property.latitude || 0,
    longitude: property.longitude || 0,
    propertyType: property.propertyType || "",
    transactionType: "vente",
    price: property.sellingPrice || property.estimatedPrice || 0,
    surface: property.surface || 0,
    bedrooms: property.bedrooms || 0,
    bathrooms: property.bathrooms || 0,
    rooms: property.rooms || 0,
    landSurface: property.landSurface || 0,
    garageSurface: 0,
    surfaceHouse: property.surface || 0,
    surfaceLand: property.landSurface || 0,
    constructionYear: property.constructionYear || 0,
    mainImageUrl: property.mainImage || "",
    title: property.title || "",
    description: property.description || "",
    features: property.features || "",
    propertyStyle: property.propertyStyle || "",
    hasCellier: property.hasCellier || false,
    hasGroundFloorBathroom: property.hasGroundFloorBathroom || false,
    hasGroundFloorBedroom: property.hasGroundFloorBedroom || false,
    isLandFenced: property.isLandFenced || false,
    hasCarport: property.hasCarport || false,
    hasSeparateWc: property.hasSeparateWc || false,
    hasAnnex: property.hasAnnexe || false,
    hasSwimmingPool: property.hasPiscine || false,
    hasGarage: property.hasGarage || false,
    hasPiscine: property.hasPiscine || false,
    hasAnnexe: property.hasAnnexe || false,
    hasCrawlSpace: property.hasCrawlSpace || false,
    hotWaterType: property.hotWaterType || "",
    solarPanels: property.solarPanels || "",
    anneeConstruction: property.constructionYear || 0,
  };
  return calculateMatchingScore(converted, buyer, false);
}
