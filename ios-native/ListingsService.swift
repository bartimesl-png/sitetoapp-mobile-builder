import Foundation

struct ListingFilters {
    var city = ""
    var transactionType = ""
    var propertyType = ""
    var minPrice = ""
    var maxPrice = ""
}

struct ListingsResponse: Decodable {
    let items: [Listing]
    let total: Int?

    init(items: [Listing], total: Int?) {
        self.items = items
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case data
        case results
        case total
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = (try? container.decode([Listing].self, forKey: .items))
            ?? (try? container.decode([Listing].self, forKey: .data))
            ?? (try? container.decode([Listing].self, forKey: .results))
            ?? []

        total = (try? container.decode(Int.self, forKey: .total))
            ?? (try? container.decode(Int.self, forKey: .count))
    }
}

enum ListingsError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "La réponse du service d’annonces est illisible."
        case .server(let message):
            return message
        }
    }
}

struct ListingsService {
    func fetch(
        filters: ListingFilters,
        offset: Int = 0
    ) async throws -> ListingsResponse {
        var components = URLComponents(
            url: AppConfig.listingsEndpoint,
            resolvingAgainstBaseURL: false
        )!

        var query = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        func add(_ name: String, _ value: String) {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                query.append(URLQueryItem(name: name, value: trimmed))
            }
        }

        add("city", filters.city)
        add("transactionType", filters.transactionType)
        add("propertyType", filters.propertyType)
        add("minPrice", filters.minPrice)
        add("maxPrice", filters.maxPrice)

        components.queryItems = query

        var request = URLRequest(url: components.url!, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ListingsError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(
                [String: String].self,
                from: data
            )
            let message = payload?["error"]
                ?? "Le service d’annonces répond avec le code \(http.statusCode)."
            throw ListingsError.server(message)
        }

        do {
            return try JSONDecoder().decode(ListingsResponse.self, from: data)
        } catch {
            throw ListingsError.invalidResponse
        }
    }
}
