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

    func contains(_ ad: ClassifiedAd) -> Bool {
        listingIDs.contains(ad.id)
    }

    func toggle(_ ad: ClassifiedAd) {
        toggle(id: ad.id)
    }

    func toggle(_ listing: Listing) {
        toggle(id: listing.id)
    }

    private func toggle(id: String) {
        if listingIDs.contains(id) {
            listingIDs.remove(id)
        } else {
            listingIDs.insert(id)
        }
        UserDefaults.standard.set(Array(listingIDs).sorted(), forKey: storageKey)
    }
}
