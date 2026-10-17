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
