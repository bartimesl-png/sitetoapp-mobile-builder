import Foundation
import Combine
import CryptoKit

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var listingIDs: Set<String>
    @Published private(set) var syncMessage: String?
    private let storageKey = "partenairefoyer.favoriteListingIDs.v1"
    private let sourceStorageKey = "partenairefoyer.favoriteSources.v1"
    private let pendingRemovalStorageKey = "partenairefoyer.favoritePendingRemovals.v1"
    private let pendingAdditionStorageKey = "partenairefoyer.favoritePendingAdditions.v1"
    private let anonymousPendingAdditionStorageKey = "partenairefoyer.favoriteAnonymousPendingAdditions.v1"
    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-favorites")!
    private var sources: [String: String]
    private var currentAccountEmail: String?
    private var pendingRemovalIDs: Set<String>
    private var pendingAdditionIDs: Set<String>
    private var anonymousPendingAdditionIDs: Set<String>
    private var favoriteSyncTask: Task<Void, Never>?

    private init() {
        listingIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        sources = UserDefaults.standard.dictionary(forKey: sourceStorageKey) as? [String: String] ?? [:]
        pendingRemovalIDs = []
        pendingAdditionIDs = []
        anonymousPendingAdditionIDs = Set(UserDefaults.standard.stringArray(forKey: anonymousPendingAdditionStorageKey) ?? [])
        currentAccountEmail = nil
        favoriteSyncTask = nil
        if let member = WixAuthStore.shared.member, member.loginEmailVerified == true {
            activateAccount(member.loginEmail)
        }
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
        saveState()
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
            if currentAccountEmail != nil {
                if pendingAdditionIDs.remove(localID) == nil {
                    pendingRemovalIDs.insert(localID)
                } else {
                    pendingRemovalIDs.remove(localID)
                }
            } else {
                anonymousPendingAdditionIDs.remove(localID)
                saveAnonymousPendingAdditions()
            }
        } else {
            listingIDs.insert(localID)
            action = "add"
            sources[localID] = sourceCollection
            pendingRemovalIDs.remove(localID)
            if currentAccountEmail != nil { pendingAdditionIDs.insert(localID) }
            else {
                anonymousPendingAdditionIDs.insert(localID)
                saveAnonymousPendingAdditions()
            }
        }
        saveState()
        let expectedAccountEmail = currentAccountEmail
        let previousSync = favoriteSyncTask
        favoriteSyncTask = Task { @MainActor [weak self] in
            await previousSync?.value
            guard let self else { return }
            _ = await syncFavorite(action: action, localID: localID, listingID: wixID,
                                   sourceCollection: sourceCollection, expectedAccountEmail: expectedAccountEmail)
        }
    }

    func syncFromWix() async {
        guard let member = WixAuthStore.shared.member, member.loginEmailVerified == true else { return }
        activateAccount(member.loginEmail)
        let accountEmail = member.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let payload = try await send(["action": "list"], expectedAccountEmail: accountEmail)
            guard currentAccountEmail == accountEmail,
                  WixAuthStore.shared.member?.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == accountEmail else { return }
            let remote = payload["favorites"] as? [[String: Any]] ?? []
            var remoteIDs = Set<String>()
            for item in remote {
                guard let id = item["listingId"] as? String,
                      let source = item["sourceCollection"] as? String else { continue }
                let localID = source == "classifiedads-1" ? "wix-classified-\(id)" : id
                remoteIDs.insert(localID)
                sources[localID] = source
            }
            listingIDs = remoteIDs.union(pendingAdditionIDs).subtracting(pendingRemovalIDs)
            pendingAdditionIDs.subtract(remoteIDs)
            saveState()
            syncMessage = "Favoris synchronisés avec votre espace Wix."

            for localID in Array(pendingRemovalIDs) {
                guard let source = sources[localID],
                      remote.contains(where: { ($0["sourceCollection"] as? String) == source && ($0["listingId"] as? String) == Self.wixID(localID, source: source) }) else {
                    pendingRemovalIDs.remove(localID)
                    sources.removeValue(forKey: localID)
                    saveState()
                    continue
                }
                _ = await syncFavorite(action: "remove", localID: localID, listingID: Self.wixID(localID, source: source),
                                       sourceCollection: source, expectedAccountEmail: accountEmail)
            }
            for localID in Array(pendingAdditionIDs) {
                guard let source = sources[localID] else { continue }
                _ = await syncFavorite(action: "add", localID: localID, listingID: Self.wixID(localID, source: source),
                                       sourceCollection: source, expectedAccountEmail: accountEmail)
            }
        } catch {
            syncMessage = "Les favoris restent disponibles sur cet iPhone. Synchronisation Wix indisponible pour le moment."
        }
    }

    func switchToAnonymousFavorites() {
        saveState()
        currentAccountEmail = nil
        loadState()
        syncMessage = nil
    }

    private func activateAccount(_ email: String) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, currentAccountEmail != normalizedEmail else { return }
        saveState()
        currentAccountEmail = normalizedEmail
        loadState()
        if !anonymousPendingAdditionIDs.isEmpty {
            let anonymousSources = UserDefaults.standard.dictionary(forKey: sourceStorageKey) as? [String: String] ?? [:]
            for localID in anonymousPendingAdditionIDs {
                guard !pendingRemovalIDs.contains(localID), let source = anonymousSources[localID] else { continue }
                listingIDs.insert(localID)
                sources[localID] = source
                pendingAdditionIDs.insert(localID)
            }
            anonymousPendingAdditionIDs.removeAll()
            saveAnonymousPendingAdditions()
            saveState()
        }
        syncMessage = nil
    }

    private func saveAnonymousPendingAdditions() {
        UserDefaults.standard.set(Array(anonymousPendingAdditionIDs).sorted(), forKey: anonymousPendingAdditionStorageKey)
    }

    private var activeStorageKeys: (favorites: String, sources: String, removals: String, additions: String) {
        guard let email = currentAccountEmail else { return (storageKey, sourceStorageKey, pendingRemovalStorageKey, pendingAdditionStorageKey) }
        let digest = SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        let prefix = "partenairefoyer.favoriteAccount.\(digest)"
        return ("\(prefix).ids", "\(prefix).sources", "\(prefix).pendingRemovals", "\(prefix).pendingAdditions")
    }

    private func loadState() {
        let keys = activeStorageKeys
        listingIDs = Set(UserDefaults.standard.stringArray(forKey: keys.favorites) ?? [])
        sources = UserDefaults.standard.dictionary(forKey: keys.sources) as? [String: String] ?? [:]
        pendingRemovalIDs = Set(UserDefaults.standard.stringArray(forKey: keys.removals) ?? [])
        pendingAdditionIDs = Set(UserDefaults.standard.stringArray(forKey: keys.additions) ?? [])
    }

    private func saveState() {
        let keys = activeStorageKeys
        UserDefaults.standard.set(Array(listingIDs).sorted(), forKey: keys.favorites)
        UserDefaults.standard.set(sources, forKey: keys.sources)
        UserDefaults.standard.set(Array(pendingRemovalIDs).sorted(), forKey: keys.removals)
        UserDefaults.standard.set(Array(pendingAdditionIDs).sorted(), forKey: keys.additions)
    }

    @discardableResult
    private func syncFavorite(action: String, localID: String, listingID: String, sourceCollection: String,
                              expectedAccountEmail: String?) async -> Bool {
        guard let expectedAccountEmail,
              currentAccountEmail == expectedAccountEmail,
              WixAuthStore.shared.member?.loginEmailVerified == true,
              WixAuthStore.shared.member?.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expectedAccountEmail else { return false }
        do {
            _ = try await send(["action": action, "listingId": listingID, "sourceCollection": sourceCollection],
                               expectedAccountEmail: expectedAccountEmail)
            guard currentAccountEmail == expectedAccountEmail else { return true }
            if action == "remove" {
                pendingRemovalIDs.remove(localID)
                pendingAdditionIDs.remove(localID)
                sources.removeValue(forKey: localID)
                saveState()
            } else if action == "add" {
                pendingAdditionIDs.remove(localID)
                saveState()
            }
            syncMessage = "Favoris synchronisés avec votre espace Wix."
            return true
        } catch {
            syncMessage = "Le favori est conservé sur cet iPhone ; la synchronisation Wix sera réessayée."
            return false
        }
    }

    private func send(_ body: [String: String], expectedAccountEmail: String? = nil) async throws -> [String: Any] {
        if let expectedAccountEmail,
           WixAuthStore.shared.member?.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != expectedAccountEmail {
            throw FavoriteError.api("Le compte actif a changé. Relancez la synchronisation des favoris.")
        }
        let token = try await WixAuthStore.shared.validAccessToken()
        if let expectedAccountEmail,
           WixAuthStore.shared.member?.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != expectedAccountEmail {
            throw FavoriteError.api("Le compte actif a changé. Relancez la synchronisation des favoris.")
        }
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
