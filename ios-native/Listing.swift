import Foundation

struct Listing: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let city: String
    let postalCode: String
    let price: Double?
    let livingArea: Double?
    let rooms: Int?
    let propertyType: String
    let transactionType: String
    let summary: String
    let imageURL: URL?
    let galleryImageURLs: [URL]
    let sourceURL: URL?
    let phone: String?
    let latitude: Double?
    let longitude: Double?

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)

        func value(_ names: [String]) -> Any? {
            for name in names {
                guard let key = AnyKey(stringValue: name),
                      let decoded = try? container.decode(AnyCodable.self, forKey: key)
                else {
                    continue
                }
                return decoded.value
            }
            return nil
        }

        func string(_ names: [String], default fallback: String = "") -> String {
            guard let raw = value(names) else { return fallback }
            if let text = raw as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(describing: raw)
        }

        func number(_ names: [String]) -> Double? {
            guard let raw = value(names) else { return nil }
            if let number = raw as? NSNumber {
                return number.doubleValue
            }
            if let text = raw as? String {
                let normalized = text
                    .replacingOccurrences(of: "\u{00A0}", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                return Double(normalized.filter {
                    $0.isNumber || $0 == "." || $0 == "-"
                })
            }
            return nil
        }

        id = string(
            ["id", "listing_id", "property_id", "external_id", "url"],
            default: UUID().uuidString
        )
        title = string(
            ["title", "name", "headline", "titre"],
            default: "Annonce immobilière"
        )
        city = string(["city", "city_name", "ville", "locality"])
        postalCode = string([
            "postal_code", "postalCode", "zip_code", "zipcode", "code_postal"
        ])
        price = number(["price", "price_eur", "prix", "amount"])
        livingArea = number([
            "living_area", "surface", "surface_area", "area", "surface_habitable"
        ])
        rooms = number([
            "rooms", "room_count", "pieces", "number_of_rooms"
        ]).map(Int.init)
        propertyType = string([
            "property_type", "propertyType", "type", "type_bien"
        ])
        transactionType = string([
            "transaction_type", "transactionType", "offer_type",
            "deal_type", "transaction"
        ])
        summary = string([
            "description", "summary", "description_text", "details", "resume"
        ])

        let imageValue = string([
            "image_url", "imageUrl", "photo_url", "main_image",
            "cover_image", "image"
        ])
        imageURL = imageValue.isEmpty ? nil : URL(string: imageValue)

        var gallery: [URL] = []
        for name in ["galleryImages", "gallery_images", "images", "photos", "photo_urls",
                     "photo1", "photo2", "photo3", "photo4", "photo5"] {
            guard let key = AnyKey(stringValue: name) else { continue }
            if let strings = try? container.decode([String].self, forKey: key) {
                gallery.append(contentsOf: strings.compactMap(URL.init(string:)))
            } else if let objects = try? container.decode([[String: String]].self, forKey: key) {
                gallery.append(contentsOf: objects.compactMap {
                    URL(string: $0["url"] ?? $0["src"] ?? $0["imageUrl"] ?? "")
                })
            } else if let text = try? container.decode(String.self, forKey: key),
                      let url = URL(string: text), !text.isEmpty {
                gallery.append(url)
            }
        }
        var seen = Set<String>()
        galleryImageURLs = gallery.filter { seen.insert($0.absoluteString).inserted }

        let sourceValue = string([
            "source_url", "sourceUrl", "listing_url", "url", "permalink", "link"
        ])
        sourceURL = sourceValue.isEmpty ? nil : URL(string: sourceValue)

        let phoneValue = string(["phone", "telephone", "contact_phone"])
        phone = phoneValue.isEmpty ? nil : phoneValue

        latitude = number(["latitude", "lat", "geo_lat"])
        longitude = number(["longitude", "lng", "lon", "geo_lng"])
    }

    var imageURLs: [URL] {
        var values = [imageURL].compactMap { $0 } + galleryImageURLs
        var seen = Set<String>()
        values = values.filter { seen.insert($0.absoluteString).inserted }
        return values
    }

    var locationLabel: String {
        [postalCode, city]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var priceLabel: String {
        guard let price else { return "Prix sur demande" }
        return price.formatted(
            .currency(code: "EUR")
                .locale(Locale(identifier: "fr_FR"))
        )
    }
}

private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let boolean = try? container.decode(Bool.self) {
            value = boolean
        } else {
            value = ""
        }
    }
}
