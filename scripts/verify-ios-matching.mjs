import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  calculateWixMatchingScore,
  calculateWixPrivatePropertyBuyerScore,
  normalizePropertyType,
  passesWixStrictMatchingFilters,
} from "../supabase/functions/ios-native-dashboard-v2/wix-matching-engine.ts";
import { calculateBuyerSearchScore, normalizePropertyType as normalizeSavedSearchPropertyType } from "../supabase/functions/ios-native-buyer-searches/matching-scoring.ts";

const buyer = {
  propertyType: "maison",
  transactionType: "vente",
  postalCode: "44130",
  latitude: 47.42,
  longitude: -1.74,
  searchRadiusKm: 25,
  budgetMin: 100_000,
  budgetMax: 250_000,
  minSurface: 80,
  maxSurface: 160,
  minRooms: 3,
  minBedrooms: 2,
};

const nearbyHome = {
  transactionType: "vente",
  postalCode: "44130",
  latitude: 47.43,
  longitude: -1.74,
  propertyType: "Maison",
  price: 180_000,
  surface: 110,
  rooms: 4,
  bedrooms: 3,
};

assert.equal(normalizePropertyType("  Maison   "), "maison");
assert.equal(normalizePropertyType("fonds_de_commerce"), "fonds-commerce");
assert.equal(normalizeSavedSearchPropertyType("Garage / Parking"), "garage");
assert.equal(passesWixStrictMatchingFilters(nearbyHome, buyer), true,
  "a same-postcode sale should pass the professional matching gates");
assert.equal(passesWixStrictMatchingFilters({ ...nearbyHome, transactionType: "location" }, buyer), false,
  "a rental must not pass a sale buyer's strict transaction gate");
assert.equal(passesWixStrictMatchingFilters({ ...nearbyHome, propertyType: "appartement" }, buyer), false,
  "a different property type must not pass the strict type gate");
assert.equal(passesWixStrictMatchingFilters(nearbyHome, { ...buyer, transactionType: undefined }), true,
  "a typed buyer record without a transaction field should still match its property type");
assert.equal(passesWixStrictMatchingFilters(nearbyHome, { ...buyer, transactionType: undefined, propertyType: "vente" }), true,
  "legacy buyer records that stored transaction intent in propertyType should remain supported");
assert.equal(passesWixStrictMatchingFilters({ ...nearbyHome, postalCode: "75001", latitude: undefined, longitude: undefined }, buyer), false,
  "a different postcode without coordinates cannot satisfy the strict location gate");
assert.equal(passesWixStrictMatchingFilters({ ...nearbyHome, postalCode: "75001", latitude: 48.86, longitude: 2.35 }, buyer), false,
  "a property outside the buyer radius must be rejected");
assert.ok(calculateWixMatchingScore(nearbyHome, buyer) > 0,
  "a compatible property should receive a positive Wix-compatible score");

const privateBuyer = {
  city: "Bouvron",
  postalCode: "44130",
  searchRadiusKm: 10,
  latitude: 47.42,
  longitude: -1.74,
  budgetMin: 100_000,
  budgetMax: 250_000,
  minSurface: 80,
  maxSurface: 160,
  minRooms: 3,
  minBedrooms: 2,
};
const privateHome = {
  city: "Bouvron",
  postalCode: "44130",
  latitude: 47.42,
  longitude: -1.74,
  propertyType: "Maison",
  sellingPrice: 180_000,
  surface: 110,
  rooms: 4,
  bedrooms: 3,
};
assert.ok(calculateWixPrivatePropertyBuyerScore(privateHome, privateBuyer) > 0,
  "a private listing in a buyer's exact location should be eligible");
assert.equal(calculateWixPrivatePropertyBuyerScore({ ...privateHome, city: "Paris", postalCode: "75001", latitude: 48.86, longitude: 2.35 }, privateBuyer), 0,
  "a private listing outside the buyer's radius must be excluded");

const savedSearch = {
  transactionType: "buy", propertyTypes: "Maison", latitude: 0, longitude: 0, radius: 10,
  minBudget: 100_000, maxBudget: 250_000, minSurface: 100, maxSurface: 120,
  minRooms: 3, minBedrooms: 2, minBathrooms: 1,
};
const savedSearchProperty = {
  transactionType: "sale", propertyType: "Maison", latitude: 0, longitude: 0,
  price: 200_000, surface: 110, rooms: 3, bedrooms: 2, bathrooms: 1,
};
assert.equal(calculateBuyerSearchScore(savedSearch, savedSearchProperty), 100,
  "an exact saved-search match with no optional features should not be penalized for unset features");
assert.ok(calculateBuyerSearchScore({ ...savedSearch, terrace: true }, { ...savedSearchProperty, hasAnnexe: true }) < 100,
  "an annex must not be mistaken for a terrace");
assert.equal(calculateBuyerSearchScore({ ...savedSearch, terrace: true }, { ...savedSearchProperty, hasTerrace: true }), 100,
  "a property with a terrace should receive the saved-search feature score");
assert.ok(calculateBuyerSearchScore({ ...savedSearch, garden: true }, { ...savedSearchProperty, isLandFenced: true }) < 100,
  "a fenced lot must not be mistaken for the presence of a garden");
assert.equal(calculateBuyerSearchScore({ ...savedSearch, parking: true }, { ...savedSearchProperty, hasParking: true }), 100,
  "parking preference should use the property parking field");
assert.ok(calculateBuyerSearchScore({ ...savedSearch, singleStory: true }, { ...savedSearchProperty, hasGroundFloorBedroom: true }) < 100,
  "a ground-floor bedroom without a ground-floor bathroom must not qualify as single-story living");
assert.equal(calculateBuyerSearchScore({ ...savedSearch, singleStory: true }, {
  ...savedSearchProperty, hasGroundFloorBedroom: true, hasGroundFloorBathroom: true,
}), 100, "both ground-floor facilities should satisfy the single-story preference");

const matrix = await readFile(new URL("../ios-native/WIX_IOS_PARITY_MATRIX.md", import.meta.url), "utf8");
const source = await readFile(new URL("../ios-native/RootView.swift", import.meta.url), "utf8");
const favoritesSource = await readFile(new URL("../ios-native/FavoritesStore.swift", import.meta.url), "utf8");
const appDelegateSource = await readFile(new URL("../ios-native/AppDelegate.swift", import.meta.url), "utf8");
const accountRoleSource = source.slice(source.indexOf("private enum AccountRole"), source.indexOf("private struct RoleEntryView"));
const roleEntrySource = source.slice(source.indexOf("private struct RoleEntryView"), source.indexOf("private static func primarySubcategory"));
const declaredRoutes = [...matrix.matchAll(/^\|\s*\d+\s*\|/gm)].length;
const sourceViews = [...source.matchAll(/^\s*(?:private\s+)?struct\s+(\w+)\s*:\s*View\b/gm)].map((match) => match[1]);
const viewInventory = matrix.split("## Inventaire SwiftUI complet")[1] ?? "";
const matrixViews = [...viewInventory.matchAll(/^- `([A-Za-z0-9_]+)`/gm)].map((match) => match[1]);
assert.equal(declaredRoutes, 207, "the parity matrix must retain all inventoried Wix route declarations");
assert.deepEqual(matrixViews, sourceViews, "the SwiftUI view list in the parity matrix must match RootView.swift");
assert.ok(favoritesSource.includes("partenairefoyer.favoriteAccount."),
  "signed-in listing favorites must use an account-scoped storage namespace");
assert.ok(favoritesSource.includes("func switchToAnonymousFavorites()"),
  "sign-out must switch the visible favorites state away from the signed-in account");
assert.ok(favoritesSource.includes("pendingRemovalIDs"),
  "offline favorite removals must remain queued for retry");
assert.ok(favoritesSource.includes("pendingAdditionIDs"),
  "offline favorite additions must remain queued for retry without restoring remote deletions");
assert.ok(favoritesSource.includes("anonymousPendingAdditionIDs"),
  "only explicitly tracked guest favorites should transfer into an account on sign-in");
assert.ok(favoritesSource.includes("saveAnonymousPendingAdditions()"),
  "guest favorite transfer intent must survive app restarts");
assert.ok(appDelegateSource.includes("didReceive response: UNNotificationResponse"),
  "notification taps must be handled by the app delegate");
assert.ok(appDelegateSource.includes("allowedKeys: Set<String>"),
  "only routing identifiers, not notification message text, should be stored for cold-launch routing");
assert.ok(source.includes("partenaireFoyerPushNotificationTapped") && source.includes("openPushDestination(fields)"),
  "a notification tap must route into the in-app account menu");
for (const route of [
  "/vendeur-login", "/vendeur-signup", "/vendeur-dashboard",
  "/pro-app-login", "/broker-login", "/broker-signup", "/broker-dashboard",
  "/artisan-login", "/artisan-signup", "/artisan-dashboard",
  "/connexion-prestataire", "/inscription-prestataire", "/espace-prestataire",
  "/hebergeur-connexion", "/hebergeur-inscription", "/hebergeur-dashboard",
]) {
  assert.ok(accountRoleSource.includes(route), `the iOS role routing must retain ${route}`);
}
assert.equal([...roleEntrySource.matchAll(/\.sheet\(isPresented: \$showSiteLogin\)/g)].length, 1,
  "each role login action must present only the shared WKWebView flow");
assert.equal([...roleEntrySource.matchAll(/\.sheet\(isPresented: \$showSiteSignup\)/g)].length, 1,
  "each role signup action must present only the shared WKWebView flow");
assert.ok(roleEntrySource.includes("siteFlow(url: role.loginURL") && roleEntrySource.includes("siteFlow(url: role.signupURL"),
  "role login and signup must use the shared WKWebView session flow");
assert.ok(source.includes("expectedDashboardRole.dashboardURL.path"),
  "legacy role login must only hand off after the selected role dashboard route is reached");
assert.ok(source.includes("configuration.websiteDataStore = .default()"),
  "role dashboards and login flows must share persistent website cookies");

console.log("Matching rules and parity inventory checks passed.");
