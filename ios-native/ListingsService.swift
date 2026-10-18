import Foundation
import Combine

@MainActor
final class ListingsService: ObservableObject {
    @Published private(set) var listings: [Listing] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingImported = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var warningMessage: String?
    @Published private(set) var hasLoaded = false

    private enum Source {
        case privateOwner
        case professional
    }

    private var importedSource: [Listing]?
    private var privateOwnerSource: [Listing]?
    private var professionalSource: [Listing]?
    private var pendingSources = 0
    private var sourceFailures: [String] = []

    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-real-estate-listings-public")!

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading, !isLoadingImported else { return }
        isLoading = true
        errorMessage = nil
        warningMessage = nil
        pendingSources = 2
        sourceFailures = []

        // The Wix catalog finishes before optional imported feeds start.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { self.finish(.privateOwner, items: try await WixAuthStore.shared.fetchPublicPrivateListings(), failure: nil) }
            catch { self.finish(.privateOwner, items: nil, failure: "les biens de particuliers (\(error.localizedDescription))") }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { self.finish(.professional, items: try await WixAuthStore.shared.fetchPublicProfessionalListings(), failure: nil) }
            catch { self.finish(.professional, items: nil, failure: "les biens de professionnels (\(error.localizedDescription))") }
        }
    }

    private func finish(_ source: Source, items: [Listing]?, failure: String?) {
        pendingSources = max(0, pendingSources - 1)
        if let items {
            switch source {
            case .privateOwner: privateOwnerSource = items
            case .professional: professionalSource = items
            }
        } else if let failure, !sourceFailures.contains(failure) {
            sourceFailures.append(failure)
        }
        publishCatalog()

        guard pendingSources == 0 else { return }
        isLoading = false
        hasLoaded = true
        startImportedLoad()
    }

    private func startImportedLoad() {
        guard !isLoadingImported else { return }
        isLoadingImported = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var accumulated = self.importedSource ?? []
            var seen = Set(accumulated.map(\.id))
            do {
                try await self.loadImportedListings { [weak self] page in
                    guard let self else { return }
                    let fresh = page.filter { seen.insert($0.id).inserted }
                    guard !fresh.isEmpty else { return }
                    accumulated.append(contentsOf: fresh)
                    self.importedSource = accumulated
                    self.appendImportedPage(fresh)
                }
                self.finishImported(items: accumulated, failure: nil)
            } catch {
                self.finishImported(items: nil, failure: "les annonces importées (\(error.localizedDescription))")
            }
        }
    }

    private func finishImported(items: [Listing]?, failure: String?) {
        if let items { importedSource = items }
        if let failure, !sourceFailures.contains(failure) { sourceFailures.append(failure) }
        isLoadingImported = false
        publishCatalog()

        let successfulSources = [importedSource, privateOwnerSource, professionalSource].compactMap { $0 }.count
        if successfulSources > 0 {
            hasLoaded = true
            warningMessage = sourceFailures.isEmpty
                ? nil
                : "Certaines sources sont indisponibles : \(sourceFailures.joined(separator: ", "))."
        } else if listings.isEmpty {
            errorMessage = "Les annonces ne sont pas disponibles pour le moment. Réessayez dans quelques instants."
        } else {
            warningMessage = "Actualisation impossible. Les biens déjà chargés restent affichés."
        }
    }

    private func appendImportedPage(_ page: [Listing]) {
        var seen = Set(listings.map(\.id))
        let fresh = page.filter { seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        listings.append(contentsOf: ListingCatalogOrdering.ordered(fresh))
        hasLoaded = true
    }

    private func publishCatalog() {
        var seen = Set<String>()
        listings = ListingCatalogOrdering.ordered(
            (importedSource ?? []) + (privateOwnerSource ?? []) + (professionalSource ?? [])
        ).filter { seen.insert($0.id).inserted }
        if !listings.isEmpty { hasLoaded = true }
    }

    private func loadImportedListings(onPage: @escaping @MainActor ([Listing]) -> Void) async throws {
        let limit = 50
        var offset = 0

        while true {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ListingFeedError.httpStatus(http.statusCode)
            }
            let page = try JSONDecoder().decode(ListingFeedResponse.self, from: data)
            if !page.items.isEmpty { await onPage(page.items) }
            guard !page.items.isEmpty else { break }
            let nextOffset = offset + page.items.count
            guard nextOffset > offset else { break }
            offset = nextOffset
            if page.items.count < limit || (page.total.map { offset >= $0 } ?? false) { break }
            await Task.yield()
        }
    }

    private enum ListingFeedError: LocalizedError {
        case httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .httpStatus(let status): "Le service des annonces a répondu (\(status))."
            }
        }
    }
}

/// Native equivalent of the website's property promotion cycle.
private enum ListingCatalogOrdering {
    static func ordered(_ listings: [Listing], now: Date = Date()) -> [Listing] {
        listings.sorted { left, right in
            let leftCreated = left.catalogCreatedDate
            let rightCreated = right.catalogCreatedDate
            let leftAge = leftCreated.map { now.timeIntervalSince($0) / 86_400 }
            let rightAge = rightCreated.map { now.timeIntervalSince($0) / 86_400 }
            let leftIsNew = leftAge.map { $0 < 2 } ?? false
            let rightIsNew = rightAge.map { $0 < 2 } ?? false
            let leftCreatedTime = leftCreated?.timeIntervalSince1970 ?? 0
            let rightCreatedTime = rightCreated?.timeIntervalSince1970 ?? 0

            if leftIsNew != rightIsNew { return leftIsNew }
            if leftIsNew {
                if leftCreatedTime != rightCreatedTime { return leftCreatedTime > rightCreatedTime }
                return left.id < right.id
            }

            let leftDrop = left.catalogPriceDropDate
            let rightDrop = right.catalogPriceDropDate
            let leftHasRecentDrop = leftAge != nil && leftDrop.map { now.timeIntervalSince($0) / 86_400 < 7 } == true
            let rightHasRecentDrop = rightAge != nil && rightDrop.map { now.timeIntervalSince($0) / 86_400 < 7 } == true
            if leftHasRecentDrop != rightHasRecentDrop { return leftHasRecentDrop }
            if leftHasRecentDrop, rightHasRecentDrop {
                let leftDropTime = leftDrop?.timeIntervalSince1970 ?? 0
                let rightDropTime = rightDrop?.timeIntervalSince1970 ?? 0
                if leftDropTime != rightDropTime { return leftDropTime > rightDropTime }
                if leftCreatedTime != rightCreatedTime { return leftCreatedTime > rightCreatedTime }
                return left.id < right.id
            }

            let leftPromotionTime = promotionTime(created: leftCreated, ageDays: leftAge)
            let rightPromotionTime = promotionTime(created: rightCreated, ageDays: rightAge)
            if leftPromotionTime != rightPromotionTime { return leftPromotionTime > rightPromotionTime }
            if leftCreatedTime != rightCreatedTime { return leftCreatedTime > rightCreatedTime }
            return left.id < right.id
        }
    }

    private static func promotionTime(created: Date?, ageDays: Double?) -> TimeInterval {
        guard let created, let ageDays, ageDays >= 2 else { return 0 }
        let cycle = floor(ageDays / 7)
        let promoted = Calendar.current.date(byAdding: .day, value: Int(cycle) * 7, to: created) ?? created
        return promoted.timeIntervalSince1970
    }
}

@MainActor
final class ClassifiedAdsService: ObservableObject {
    @Published private(set) var ads: [ClassifiedAd] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var warningMessage: String?
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        warningMessage = nil
        defer { isLoading = false }
        do {
            let result = try await WixAuthStore.shared.fetchPublicClassifiedAds { [weak self] partialAds, warning in
                self?.ads = partialAds
                self?.warningMessage = warning
                self?.hasLoaded = true
            }
            ads = result.ads
            warningMessage = result.warningMessage
            hasLoaded = true
        } catch {
            if ads.isEmpty {
                errorMessage = "Les petites annonces ne sont pas disponibles pour le moment. Réessayez."
            } else {
                warningMessage = "Impossible d’actualiser les annonces. Les résultats déjà chargés restent affichés."
            }
        }
    }
}

@MainActor
final class PublicBuyerSearchesService: ObservableObject {
    @Published private(set) var searches: [WixPublicBuyerSearch] = []
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
            searches = try await WixAuthStore.shared.fetchPublicBuyerSearches()
            hasLoaded = true
        } catch {
            errorMessage = "Les demandes de recherche ne sont pas disponibles pour le moment. Réessayez."
        }
    }
}

@MainActor
final class BuyerSearchService: ObservableObject {
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-buyer-searches")!

    func create(
        searchName: String,
        transactionType: String,
        propertyTypes: [String],
        city: String,
        postalCode: String,
        radius: Double,
        minBudget: Double,
        maxBudget: Double,
        minSurface: Double,
        maxSurface: Double?,
        minLandSurface: Double,
        maxLandSurface: Double?,
        minRooms: Double,
        minBedrooms: Double,
        minBathrooms: Double,
        singleStory: Bool,
        garage: Bool,
        garden: Bool,
        terrace: Bool,
        pool: Bool,
        parking: Bool,
        latitude: Double?,
        longitude: Double?,
        emailAlertsEnabled: Bool,
        searchID: String? = nil
    ) async -> Bool {
        var body: [String: Any] = [
            "action": searchID == nil ? "create" : "update",
            "searchName": searchName,
            "transactionType": transactionType,
            "propertyTypes": propertyTypes,
            "city": city,
            "postalCode": postalCode,
            "radius": radius,
            "minBudget": minBudget,
            "maxBudget": maxBudget,
            "minSurface": minSurface,
            "minLandSurface": minLandSurface,
            "minRooms": minRooms,
            "minBedrooms": minBedrooms,
            "minBathrooms": minBathrooms,
            "singleStory": singleStory,
            "garage": garage,
            "garden": garden,
            "terrace": terrace,
            "pool": pool,
            "parking": parking,
            "emailAlertsEnabled": emailAlertsEnabled
        ]
        if let searchID { body["searchId"] = searchID }
        if let maxSurface { body["maxSurface"] = maxSurface }
        if let maxLandSurface { body["maxLandSurface"] = maxLandSurface }
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        return await perform(body, successMessage: searchID == nil
            ? "Votre recherche a été enregistrée dans votre espace Wix."
            : "Votre recherche a été mise à jour dans votre espace Wix.")
    }

    func deactivate(searchID: String) async {
        _ = await perform(["action": "deactivate", "searchId": searchID],
                          successMessage: "La recherche a été désactivée.")
    }

    func activate(searchID: String) async -> Bool {
        await perform(["action": "activate", "searchId": searchID],
                      successMessage: "La recherche a été réactivée.")
    }

    func setEmailAlerts(searchID: String, enabled: Bool) async -> Bool {
        await perform(["action": "alerts", "searchId": searchID, "enabled": enabled],
                      successMessage: enabled ? "Les alertes e-mail sont activées." : "Les alertes e-mail sont désactivées.")
    }

    func delete(searchID: String) async -> Bool {
        await perform(["action": "delete", "searchId": searchID],
                      successMessage: "La recherche a été supprimée de votre espace Wix.")
    }

    func dismissMatching(matchingID: String) async -> Bool {
        await perform(["action": "dismiss_matching", "matchingId": matchingID],
                      successMessage: "Le matching a été masqué de votre espace.")
    }

    private func perform(_ body: [String: Any], successMessage: String) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        errorMessage = nil
        statusMessage = nil
        defer { isSubmitting = false }
        do {
            let token = try await WixAuthStore.shared.validAccessToken()
            var request = URLRequest(url: endpoint, timeoutInterval: 35)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BuyerSearchError.invalidResponse }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (200..<300).contains(http.statusCode) else {
                throw BuyerSearchError.rejected(payload["error"] as? String ?? "Le service de recherche a refusé la demande (\(http.statusCode)).")
            }
            statusMessage = successMessage
            await WixAuthStore.shared.loadDashboard(role: "particulier")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private enum BuyerSearchError: LocalizedError {
        case invalidResponse
        case rejected(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Réponse invalide du service de recherche."
            case .rejected(let message): message
            }
        }
    }
}

@MainActor
final class ProfessionalsService: ObservableObject {
    @Published private(set) var professionals: [WixPublicProfessional] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var warningMessage: String?
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        warningMessage = nil
        defer { isLoading = false }
        do {
            let result = try await WixAuthStore.shared.fetchPublicProfessionals { [weak self] partial, warning in
                // Show opted-in Wix professionals immediately; optional imported
                // feeds can finish afterward and append behind registered profiles.
                self?.professionals = partial
                self?.warningMessage = warning
            }
            professionals = result.professionals
            warningMessage = result.warning
            hasLoaded = true
        } catch {
            errorMessage = "L’annuaire n’a pas pu être chargé : \(error.localizedDescription)"
        }
    }
}

/// Client for the existing referral workflow. Candidate creation is a live,
/// rate-limited operation; it is only invoked from the user's submit action.
@MainActor
final class ReferralService: ObservableObject {
    @Published private(set) var candidates: [[String: Any]] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-mandataire-opportunities")!

    private enum ServiceError: LocalizedError {
        case invalidResponse
        case rejected(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Réponse invalide du service de parrainage."
            case .rejected(let message): message
            }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await WixAuthStore.shared.validAccessToken()
            let payload = try await send(["action": "list"], token: token)
            candidates = (payload["candidates"] as? [[String: Any]]) ?? (payload["data"] as? [[String: Any]]) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(firstName: String, lastName: String, email: String, phone: String,
                city: String, postalCode: String, experience: String, project: String,
                message: String, consent: Bool) async -> Bool {
        errorMessage = nil
        statusMessage = nil
        do {
            _ = try await send([
                "action": "create", "firstName": firstName, "lastName": lastName,
                "email": email, "phone": phone, "city": city, "postalCode": postalCode,
                "experience": experience, "project": project, "message": message,
                "consent": consent
            ], token: nil)
            statusMessage = "Votre proposition a été transmise."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(action: String, candidateID: String) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let token = try await WixAuthStore.shared.validAccessToken()
            _ = try await send(["action": action, "candidateId": candidateID], token: token)
            statusMessage = action == "claim" ? "Contact attribué à votre espace." : "Profil masqué de votre liste."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(_ body: [String: Any], token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let code = payload["error"] as? String ?? ""
            let message: String
            switch code {
            case "SUBSCRIPTION_REQUIRED": message = "L’accès aux candidatures nécessite un espace professionnel éligible."
            case "VALIDATION": message = "Vérifiez les coordonnées, le code postal et votre accord avant l’envoi."
            case "RATE_LIMIT": message = "Une recommandation similaire a déjà été envoyée récemment. Réessayez plus tard."
            case "FULL": message = "Cette candidature a déjà reçu le nombre maximal d’attributions."
            case "CLAIM_FAILED": message = "L’attribution n’a pas abouti. Actualisez la liste puis réessayez."
            default: message = "Le service de parrainage n’a pas pu traiter la demande (\(http.statusCode))."
            }
            throw ServiceError.rejected(message)
        }
        return payload
    }
}

/// Native interface to the existing consent and imported-listing controls.
@MainActor
final class ProfessionalImportService: ObservableObject {
    @Published private(set) var state: [String: Any]?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-real-estate-pro-self-service")!

    var isLinked: Bool { state?["linked"] as? Bool == true }
    var isAuthorized: Bool { (state?["consent"] as? [String: Any])?["granted"] as? Bool == true }
    var consentStatus: String { (state?["consent"] as? [String: Any])?["status"] as? String ?? "not_requested" }
    var autoImportEnabled: Bool { state?["autoImportEnabled"] as? Bool ?? true }
    var listings: [[String: Any]] { state?["listings"] as? [[String: Any]] ?? [] }

    func load() async { await perform(["action": "get"], status: nil) }

    func setConsent(_ granted: Bool) async {
        await perform(["action": "set_consent", "granted": granted], status: granted
            ? "Autorisation enregistrée. L’import va être relancé en priorité."
            : "Autorisation retirée. Les annonces importées ne seront plus diffusées ni utilisées pour le matching.")
    }

    func setAutoImport(_ enabled: Bool) async {
        await perform(["action": "set_auto_import", "enabled": enabled], status: enabled
            ? "Import automatique activé."
            : "Import automatique suspendu.")
    }

    func setListingVisible(_ id: String, visible: Bool) async {
        await perform(["action": "set_listing_visibility", "listingId": id, "visible": visible], status: visible
            ? "Visibilité de l’annonce mise à jour."
            : "Annonce masquée de l’application et du matching.")
    }

    private func perform(_ body: [String: Any], status: String?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }
        do {
            let token = try await WixAuthStore.shared.validAccessToken()
            var request = URLRequest(url: endpoint, timeoutInterval: 40)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ImportError.invalidResponse }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (200..<300).contains(http.statusCode) else {
                throw ImportError.rejected(payload["error"] as? String ?? "Le service d’import a refusé la demande (\(http.statusCode)).")
            }
            state = payload
            statusMessage = status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum ImportError: LocalizedError {
        case invalidResponse
        case rejected(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Réponse invalide du service d’import."
            case .rejected(let message): message
            }
        }
    }
}
