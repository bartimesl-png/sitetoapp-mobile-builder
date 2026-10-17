import Foundation
import Combine

@MainActor
final class ListingsService: ObservableObject {
    @Published private(set) var listings: [Listing] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-real-estate-listings-public")!

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var successfulSources = 0
            let imported: [Listing]
            do {
                imported = try await loadImportedListings()
                successfulSources += 1
            } catch {
                imported = []
            }

            let privateListings: [Listing]
            do {
                privateListings = try await WixAuthStore.shared.fetchPublicPrivateListings()
                successfulSources += 1
            } catch {
                privateListings = []
            }

            guard successfulSources > 0 else { throw URLError(.badServerResponse) }
            var seen = Set<String>()
            listings = (imported + privateListings).filter { seen.insert($0.id).inserted }
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = "Les annonces ne sont pas disponibles pour le moment. Réessayez dans quelques instants."
        }
    }

    private func loadImportedListings() async throws -> [Listing] {
        let limit = 250
        var offset = 0
        var allItems: [Listing] = []

        // The public feed caps each request at 250; this keeps the native list
        // complete for normal catalogue sizes without an unbounded fetch loop.
        for _ in 0..<20 {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let page = try JSONDecoder().decode(ListingFeedResponse.self, from: data)
            allItems.append(contentsOf: page.items)
            offset += page.items.count
            if page.items.count < limit || (page.total.map { offset >= $0 } ?? false) { break }
        }
        return allItems
    }
}

@MainActor
final class ProfessionalsService: ObservableObject {
    @Published private(set) var professionals: [WixPublicProfessional] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let results = try await WixAuthStore.shared.fetchPublicProfessionals()
            professionals = results.sorted {
                $0.resolvedName.localizedStandardCompare($1.resolvedName) == .orderedAscending
            }
            hasLoaded = true
        } catch {
            errorMessage = "L’annuaire des professionnels n’est pas disponible pour le moment."
        }
    }
}
