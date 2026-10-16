import Foundation

/// Public listing DTO returned by the existing PartenaireFoyer Supabase feed.
/// Unknown fields from the API are intentionally ignored for forward compatibility.
struct Listing: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let description: String?
    let city: String?
    let postalCode: String?
    let price: Double?
    let surface: Double?
    let rooms: Int?
    let bedrooms: Int?
    let bathrooms: Int?
    let images: [String]?
    let imageUrl: String?
    let transactionType: String?
    let propertyType: String?
    let sourceUrl: String?
    let ownerType: String?

    var gallery: [URL] {
        var candidates = images ?? []
        if let imageUrl { candidates.insert(imageUrl, at: 0) }
        var seen = Set<String>()
        return candidates.compactMap { value in
            guard seen.insert(value).inserted else { return nil }
            return URL(string: value)
        }
    }

    var locationLabel: String {
        [postalCode, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var formattedPrice: String {
        guard let price else { return "Prix sur demande" }
        return price.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }

    var formattedSurface: String? {
        guard let surface, surface > 0 else { return nil }
        return "\(surface.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))) m²"
    }
}

struct ListingFeedResponse: Decodable {
    let items: [Listing]
    let total: Int?
}
