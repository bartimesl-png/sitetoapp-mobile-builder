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
    let landSurface: Double?
    let rooms: Int?
    let bedrooms: Int?
    let bathrooms: Int?
    let images: [String]?
    let imageUrl: String?
    let transactionType: String?
    let propertyType: String?
    let sourceUrl: String?
    let ownerType: String?
    let importedProId: String?
    let professionalID: String?
    let createdAt: String?
    let firstSeenAt: String?
    let updatedAt: String?
    let lastSeenAt: String?

    var canContactImportedProfessional: Bool {
        ownerType == "professional_imported" && importedProId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// ISO-8601 timestamps sort lexically when returned in the API's UTC form.
    /// Use each source's best available publication/creation timestamp, with
    /// deterministic ID ordering for records that have no timestamp.
    var sortDateKey: String {
        createdAt ?? firstSeenAt ?? updatedAt ?? lastSeenAt ?? ""
    }

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

struct WixRawDirectoryResponse: Decodable {
    let dataItems: [WixRawDirectoryItem]
}

struct WixRawDirectoryItem: Decodable {
    let id: String
    let data: [String: AnyCodableValue]
}

struct AnyCodableValue: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self.value = value }
        else if let value = try? container.decode(Bool.self) { self.value = value }
        else if let value = try? container.decode(Double.self) { self.value = value }
        else if let value = try? container.decode(Int.self) { self.value = value }
        else if let value = try? container.decode([AnyCodableValue].self) { self.value = value.map(\.value) }
        else if let value = try? container.decode([String: AnyCodableValue].self) { self.value = value.mapValues(\.value) }
        else if try container.decodeNil() { self.value = NSNull() }
        else { self.value = NSNull() }
    }
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
    let mainPostalCode: String?
    let coveredPostalCodes: String?
    let secondaryPostalCodes: String?
    let email: String?
    let phone: String?

    func professional(id: String) -> WixPublicProfessional {
        WixPublicProfessional(
            id: id,
            cmsProfileID: id,
            companyName: companyName,
            firstName: firstName,
            lastName: lastName,
            network: network,
            city: city,
            postalCode: postalCode,
            businessSector: businessSector,
            description: description,
            logo: photo,
            website: website,
            professionalEmail: email,
            publicPhone: phone
        )
    }
}

struct WixPublicProfessional: Identifiable {
    let id: String
    var cmsProfileID: String? = nil
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
    var importedID: String? = nil
    var importedCategory: String? = nil
    var professionalEmail: String? = nil
    var publicPhone: String? = nil
    var dedupeEmail: String? = nil
    var dedupePhone: String? = nil
    var isLocalProsProfile: Bool = false

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

struct ProfessionalDirectoryResult {
    let professionals: [WixPublicProfessional]
    let warning: String?
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
    let landSurface: Double?
    let rooms: Double?
    let bedrooms: Double?
    let bathrooms: Double?
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
    let createdAt: String?

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
            landSurface: landSurface,
            rooms: rooms.map(Int.init),
            bedrooms: bedrooms.map(Int.init),
            bathrooms: bathrooms.map(Int.init),
            images: photos,
            imageUrl: photos.first,
            transactionType: transactionType,
            propertyType: propertyType,
            sourceUrl: nil,
            ownerType: "particulier",
            importedProId: nil,
            professionalID: nil,
            createdAt: createdAt,
            firstSeenAt: nil,
            updatedAt: nil,
            lastSeenAt: nil
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
    let professionalId: String?
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
    let photo1: String?
    let photo2: String?
    let photo3: String?
    let photo4: String?
    let photo5: String?
    let createdAt: String?
    let updatedAt: String?
    let commercialStatus: String?
    let status: String?
    let slug: String?

    func listing(id: String) -> Listing {
        var gallery: [String] = [photo1, photo2, photo3, photo4, photo5].compactMap { $0 }
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
            landSurface: surfaceLand ?? landSurface,
            rooms: rooms.map(Int.init),
            bedrooms: bedrooms.map(Int.init),
            bathrooms: bathrooms.map(Int.init),
            images: gallery,
            imageUrl: mainImageUrl ?? gallery.first,
            transactionType: transactionType,
            propertyType: propertyType,
            sourceUrl: nil,
            ownerType: "professionnel",
            importedProId: nil,
            professionalID: professionalId,
            createdAt: createdAt,
            firstSeenAt: nil,
            updatedAt: updatedAt,
            lastSeenAt: nil
        )
    }
}
/// Public classified-ad content loaded from the existing Wix CMS collection.
struct ClassifiedAd: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let price: Double?
    let category: String?
    let subcategory: String?
    let condition: String?
    let city: String?
    let postalCode: String?
    let images: [URL]
    var externalURL: URL? = nil
    var isImported: Bool = false
    var importedAttributesJSON: String? = nil
    var importedProviderName: String? = nil
    var listingType: String? = nil
    var wixSlug: String? = nil

    var wixDetailURL: URL? {
        guard !isImported,
              id.hasPrefix("wix-classified-") else { return nil }
        let cmsID = String(id.dropFirst("wix-classified-".count))
        let trimmedSlug = wixSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identifier = trimmedSlug.isEmpty ? cmsID : trimmedSlug
        guard identifier.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.partenairefoyer.com/petites-annonces/\(identifier)")
    }

    var locationLabel: String {
        [postalCode, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var listingTypeLabel: String? {
        switch listingType {
        case "sell": return "À vendre"
        case "give": return "À donner"
        case "exchange": return "À échanger"
        case "rent": return "À louer"
        default: return nil
        }
    }

    var formattedPrice: String {
        switch listingType {
        case "give": return "Gratuit"
        case "exchange": return "Échange"
        case "rent":
            let unit = rentalUnit
            return "\(currencyPrice) / \(unit)"
        default:
            return currencyPrice
        }
    }

    private var currencyPrice: String {
        guard let price else { return "Prix sur demande" }
        return price.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }

    private var rentalUnit: String {
        guard let raw = importedAttributesJSON?.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let unit = values["rentalUnit"] as? String else { return "jour" }
        switch unit {
        case "hour": return "heure"
        case "day": return "jour"
        case "weekend": return "week-end"
        case "week": return "semaine"
        case "month": return "mois"
        default: return unit
        }
    }
}

struct WixPublicClassifiedAdsResponse: Decodable {
    let dataItems: [WixPublicClassifiedAdItem]
}

struct WixPublicClassifiedAdItem: Decodable {
    let id: String
    let data: WixPublicClassifiedAdData
}

enum WixFlexibleJSON: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: WixFlexibleJSON])
    case array([WixFlexibleJSON])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let object = try? value.decode([String: WixFlexibleJSON].self) { self = .object(object) }
        else if let array = try? value.decode([WixFlexibleJSON].self) { self = .array(array) }
        else { self = .null }
    }

    var jsonString: String? {
        if case .string(let string) = self { return string }
        func objectValue(_ item: WixFlexibleJSON) -> Any {
            switch item {
            case .string(let raw): return raw
            case .number(let raw): return raw
            case .bool(let raw): return raw
            case .object(let raw): return raw.mapValues { objectValue($0) }
            case .array(let raw): return raw.map(objectValue)
            case .null: return NSNull()
            }
        }
        let object = objectValue(self)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]) else {
            if case .string(let string) = self { return string }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct WixPublicClassifiedAdData: Decodable {
    let itemName: String?
    let itemDescription: String?
    let itemPrice: Double?
    let category: String?
    let subcategory: String?
    let itemCondition: String?
    let adListingType: String?
    let attributesJSON: WixFlexibleJSON?
    let slug: String?
    let city: String?
    let postalCode: String?
    let status: String?
    let itemImage: String?
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

    func classifiedAd(id: String) -> ClassifiedAd? {
        guard status == "published" || status == "active",
              let title = itemName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        var seen = Set<String>()
        let images = [itemImage, photo2, photo3, photo4, photo5, photo6, photo7, photo8,
                      photo9, photo10, photo11, photo12, photo13, photo14, photo15, photo16,
                      photo17, photo18, photo19, photo20]
            .compactMap { $0 }
            .compactMap(WixImageSource.url)
            .filter { seen.insert($0.absoluteString).inserted }
        return ClassifiedAd(
            id: "wix-classified-\(id)",
            title: title,
            description: itemDescription,
            price: itemPrice,
            category: category,
            subcategory: subcategory,
            condition: itemCondition,
            city: city,
            postalCode: postalCode,
            images: images,
            externalURL: nil,
            isImported: false,
            importedAttributesJSON: attributesJSON?.jsonString,
            listingType: adListingType,
            wixSlug: slug
        )
    }
}

