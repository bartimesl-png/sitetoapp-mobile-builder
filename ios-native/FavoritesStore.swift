import Foundation
import Observation

@Observable
final class FavoritesStore {
    private(set) var listings: [Listing] = []

    var ids: Set<String> {
        Set(listings.map(\.?id))
    }

    private let key = "partenairefoyer.favorite-listings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Listing].self, from: data) {
            listings = decoded
        }
    }

    func contains(_ listing: Listing) -> Bool {
        ids.contains(listing.id)
    }

    func toggle(_ listing: Listing) {
        if ids.contains(listing.id) {
            listings.removeAll { $0.id == listing.id }
        } else {
            listings.insert(listing, at: 0)
        }

        if let data = try? JSONEncoder().encode(listings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
