import Foundation
import Combine

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var listingIDs: Set<String>
    private let storageKey = "partenairefoyer.favoriteListingIDs.v1"

    private init() {
        listingIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    func contains(_ listing: Listing) -> Bool {
        listingIDs.contains(listing.id)
    }

    func toggle(_ listing: Listing) {
        if listingIDs.contains(listing.id) {
            listingIDs.remove(listing.id)
        } else {
            listingIDs.insert(listing.id)
        }
        UserDefaults.standard.set(Array(listingIDs).sorted(), forKey: storageKey)
    }
}
