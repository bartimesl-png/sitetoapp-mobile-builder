import Foundation

enum WixImageSource {
    static func url(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") || value.hasPrefix("http://") { return URL(string: value) }
        for prefix in ["wix:image://v1/", "image://v1/"] where value.hasPrefix(prefix) {
            let remainder = value.dropFirst(prefix.count)
            guard let mediaId = remainder.split(separator: "/", maxSplits: 1).first,
                  !mediaId.isEmpty else { return nil }
            return URL(string: "https://static.wixstatic.com/media/\(mediaId)")
        }
        return nil
    }
}

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
            return WixImageSource.url(value)
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

struct WixPublicPropertiesResponse: Decodable {
    let dataItems: [WixPublicPropertyItem]
}

struct WixPublicProfessionalsResponse: Decodable {
    let dataItems: [WixPublicProfessionalItem]
}

struct WixPublicProfessionalItem: Decodable {
    let id: String
    let data: WixPublicProfessionalData
}

struct WixPublicProfessionalData: Decodable {
    let companyName: String?
    let firstName: String?
    let lastName: String?
    let network: String?
    let city: String?
    let postalCode: String?
    let businessSector: String?
    let description: String?
    let photo: String?
    let website: String?
    let memberId: String?
    let isVisibleInDirectory: Bool?
    let isActive: Bool?

    func professional(id: String) -> WixPublicProfessional {
        WixPublicProfessional(
            id: id,
            companyName: companyName,
            firstName: firstName,
            lastName: lastName,
            network: network,
            city: city,
            postalCode: postalCode,
            businessSector: businessSector,
            description: description,
            logo: photo,
            website: website
        )
    }
}

struct WixPublicProfessional: Identifiable {
    let id: String
    let companyName: String?
    let firstName: String?
    let lastName: String?
    let network: String?
    let city: String?
    let postalCode: String?
    let businessSector: String?
    let description: String?
    let logo: String?
    let website: String?

    var resolvedName: String {
        let company = companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !company.isEmpty { return company }
        let person = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return person.isEmpty ? "Professionnel immobilier" : person
    }
    var resolvedActivity: String? {
        [businessSector, network]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
    var locationLabel: String {
        [postalCode, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct WixPublicPropertyItem: Decodable {
    let id: String
    let data: WixPublicProperty
}

struct WixPublicProperty: Decodable {
    let title: String?
    let description: String?
    let city: String?
    let postalCode: String?
    let sellingPrice: Double?
    let estimatedPrice: Double?
    let status: String?
    let surface: Double?
    let rooms: Double?
    let bedrooms: Double?
    let propertyType: String?
    let transactionType: String?
    let mainImage: String?
    let isPublic: Bool?
    let photo1: String?
    let photo2: String?
    let photo3: String?
    let photo4: String?
    let photo5: String?
    let photo6: String?
    let photo7: String?
    let photo8: String?
    let photo9: String?
    let photo10: String?
    let photo11: String?
    let photo12: String?
    let photo13: String?
    let photo14: String?
    let photo15: String?
    let photo16: String?
    let photo17: String?
    let photo18: String?
    let photo19: String?
    let photo20: String?
    let galleryImages: String?

    var photos: [String] {
        var result = [mainImage, photo1, photo2, photo3, photo4, photo5,
                      photo6, photo7, photo8, photo9, photo10, photo11,
                      photo12, photo13, photo14, photo15, photo16, photo17,
                      photo18, photo19, photo20].compactMap { $0 }
        if let galleryImages, let data = galleryImages.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for image in decoded {
                if let url = image as? String {
                    result.append(url)
                } else if let object = image as? [String: Any],
                          let url = (object["url"] as? String) ?? (object["src"] as? String) {
                    result.append(url)
                }
            }
        }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var listing: Listing {
        Listing(
            id: "wix-private-\(id)",
            title: title,
            description: description,
            city: city,
            postalCode: postalCode,
            price: sellingPrice ?? estimatedPrice,
            surface: surface,
            rooms: rooms.map(Int.init),
            bedrooms: bedrooms.map(Int.init),
            bathrooms: nil,
            images: photos,
            imageUrl: photos.first,
            transactionType: transactionType,
            propertyType: propertyType,
            sourceUrl: nil,
            ownerType: "particulier"
        )
    }
}

struct WixPublicProfessionalPropertiesResponse: Decodable {
    let dataItems: [WixPublicProfessionalPropertyItem]
}

struct WixPublicProfessionalPropertyItem: Decodable {
    let id: String
    let data: WixPublicProfessionalProperty
}

struct WixPublicProfessionalProperty: Decodable {
    let title: String?
    let description: String?
    let city: String?
    let postalCode: String?
    let price: Double?
    let surface: Double?
    let surfaceHouse: Double?
    let surfaceLand: Double?
    let landSurface: Double?
    let rooms: Double?
    let bedrooms: Double?
    let bathrooms: Double?
    let propertyType: String?
    let transactionType: String?
    let mainImageUrl: String?
    let galleryImages: String?
    let commercialStatus: String?
    let status: String?
    let slug: String?

    func listing(id: String) -> Listing {
        var gallery: [String] = []
        if let galleryImages, let data = galleryImages.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for value in values {
                if let url = value as? String {
                    gallery.append(url)
                } else if let object = value as? [String: Any],
                          let url = (object["url"] as? String) ?? (object["src"] as? String) {
                    gallery.append(url)
                }
            }
        }
        if let mainImageUrl, !gallery.contains(mainImageUrl) { gallery.insert(mainImageUrl, at: 0) }
        var seen = Set<String>()
        gallery = gallery.filter { !$0.isEmpty && seen.insert($0).inserted }
        return Listing(
            id: "wix-pro-\(id)",
            title: title,
            description: description,
            city: city,
            postalCode: postalCode,
            price: price,
            surface: surfaceHouse ?? surface,
            rooms: rooms.map(Int.init),
            bedrooms: bedrooms.map(Int.init),
            bathrooms: bathrooms.map(Int.init),
            images: gallery,
            imageUrl: mainImageUrl ?? gallery.first,
            transactionType: transactionType,
            propertyType: propertyType,
            sourceUrl: nil,
            ownerType: "professionnel"
        )
    }
}
