import Foundation
import Combine

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var listingIDs: Set<String>
    @Published private(set) var syncMessage: String?
    private let storageKey = "partenairefoyer.favoriteListingIDs.v1"
    private let sourceStorageKey = "partenairefoyer.favoriteSources.v1"
    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-favorites")!
    private var sources: [String: String]

    private init() {
        listingIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        sources = UserDefaults.standard.dictionary(forKey: sourceStorageKey) as? [String: String] ?? [:]
    }

    func contains(_ listing: Listing) -> Bool {
        listingIDs.contains(listing.id)
    }

    func contains(_ ad: ClassifiedAd) -> Bool {
        listingIDs.contains(ad.id)
    }

    func inferSources(listings: [Listing], ads: [ClassifiedAd]) {
        for listing in listings where listingIDs.contains(listing.id) && sources[listing.id] == nil {
            switch listing.ownerType?.lowercased() {
            case "particulier": sources[listing.id] = "privateproperties"
            case "professionnel": sources[listing.id] = "biensprofessionnels"
            default: sources[listing.id] = "imported-listings"
            }
        }
        for ad in ads where listingIDs.contains(ad.id) && sources[ad.id] == nil {
            sources[ad.id] = "classifiedads-1"
        }
        UserDefaults.standard.set(sources, forKey: sourceStorageKey)
    }

    func toggle(_ ad: ClassifiedAd) {
        let wixID = ad.id.hasPrefix("wix-classified-") ? String(ad.id.dropFirst("wix-classified-".count)) : ad.id
        toggle(localID: ad.id, wixID: wixID, sourceCollection: "classifiedads-1")
    }

    func toggle(_ listing: Listing) {
        let source: String
        switch listing.ownerType?.lowercased() {
        case "particulier": source = "privateproperties"
        case "professionnel": source = "biensprofessionnels"
        default: source = "imported-listings"
        }
        toggle(localID: listing.id, wixID: listing.id, sourceCollection: source)
    }

    private func toggle(localID: String, wixID: String, sourceCollection: String) {
        let action: String
        if listingIDs.contains(localID) {
            listingIDs.remove(localID)
            action = "remove"
        } else {
            listingIDs.insert(localID)
            action = "add"
            sources[localID] = sourceCollection
        }
        UserDefaults.standard.set(Array(listingIDs).sorted(), forKey: storageKey)
        UserDefaults.standard.set(sources, forKey: sourceStorageKey)
        Task { await syncFavorite(action: action, listingID: wixID, sourceCollection: sourceCollection) }
    }

    func syncFromWix() async {
        guard WixAuthStore.shared.member != nil else { return }
        do {
            let payload = try await send(["action": "list"])
            let remote = payload["favorites"] as? [[String: Any]] ?? []
            var remoteIDs = Set<String>()
            for item in remote {
                guard let id = item["listingId"] as? String,
                      let source = item["sourceCollection"] as? String else { continue }
                let localID = source == "classifiedads-1" ? "wix-classified-\(id)" : id
                remoteIDs.insert(localID)
                sources[localID] = source
            }
            listingIDs.formUnion(remoteIDs)
            UserDefaults.standard.set(Array(listingIDs).sorted(), forKey: storageKey)
            UserDefaults.standard.set(sources, forKey: sourceStorageKey)
            syncMessage = "Favoris synchronisés avec votre espace Wix."

            // Transfer favorites saved on this device before the Wix account was connected.
            for localID in listingIDs {
                guard let source = sources[localID],
                      !remote.contains(where: { ($0["sourceCollection"] as? String) == source && ($0["listingId"] as? String) == Self.wixID(localID, source: source) }) else { continue }
                await syncFavorite(action: "add", listingID: Self.wixID(localID, source: source), sourceCollection: source)
            }
        } catch {
            syncMessage = "Les favoris restent disponibles sur cet iPhone. Synchronisation Wix indisponible pour le moment."
        }
    }

    private func syncFavorite(action: String, listingID: String, sourceCollection: String) async {
        guard WixAuthStore.shared.member != nil else { return }
        do {
            _ = try await send(["action": action, "listingId": listingID, "sourceCollection": sourceCollection])
            syncMessage = "Favoris synchronisés avec votre espace Wix."
        } catch {
            syncMessage = "Le favori est conservé sur cet iPhone ; la synchronisation Wix sera réessayée."
        }
    }

    private func send(_ body: [String: String]) async throws -> [String: Any] {
        let token = try await WixAuthStore.shared.validAccessToken()
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            throw FavoriteError.api(message ?? "Synchronisation des favoris impossible.")
        }
        return payload
    }

    private static func wixID(_ localID: String, source: String) -> String {
        source == "classifiedads-1" && localID.hasPrefix("wix-classified-")
            ? String(localID.dropFirst("wix-classified-".count))
            : localID
    }

    private enum FavoriteError: LocalizedError {
        case api(String)
        var errorDescription: String? { if case .api(let message) = self { return message }; return nil }
    }
}
