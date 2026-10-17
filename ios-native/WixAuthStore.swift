import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

struct WixMember: Codable, Equatable {
    let id: String
    let loginEmail: String
    let loginEmailVerified: Bool?
    let status: String?
    let firstName: String?
    let lastName: String?
}

@MainActor
final class WixAuthStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WixAuthStore()

    @Published private(set) var member: WixMember?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?
    @Published private(set) var infoMessage: String?
    @Published private(set) var dashboardData: [String: Any]?
    @Published private(set) var dashboardError: String?
    @Published private(set) var isLoadingDashboard = false

    private let clientID = "694d7a57-f31a-4a5d-9bdd-8829f8f89b4e"
    private let redirectURI = "https://www.partenairefoyer.com/api/auth/callback"
    private let keychainService = "com.partenairefoyer.app.wix-session"
    private var authSession: ASWebAuthenticationSession?
    private var dashboardRequestID = UUID()

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let member: WixMember
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct LoginResponse: Decodable {
        let state: String?
        let sessionToken: String?
        let message: String?
    }

    private struct RegistrationResponse: Decodable {
        let state: String?
        let sessionToken: String?
        let stateToken: String?
        let message: String?
    }

    private struct RedirectResponse: Decodable {
        struct Session: Decodable {
            let fullUrl: String
        }
        let redirectSession: Session
    }

    private struct MemberResponse: Decodable {
        struct MemberPayload: Decodable {
            let id: String
            let loginEmail: String
            let loginEmailVerified: Bool?
            let status: String?
            let contact: Contact?
            struct Contact: Decodable {
                let firstName: String?
                let lastName: String?
            }
        }
        let member: MemberPayload
    }

    override private init() {
        super.init()
        restoreMember()
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        infoMessage = nil
        defer { isSigningIn = false }

        do {
            let visitor = try await requestToken([
                "clientId": clientID,
                "grantType": "anonymous"
            ])

            let login = try await post(
                "https://www.wixapis.com/_api/iam/authentication/v2/login",
                bearer: visitor.accessToken,
                body: ["login_id": ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)], "password": password],
                as: LoginResponse.self
            )
            guard let sessionToken = login.sessionToken, login.state?.uppercased() == "SUCCESS" else {
                throw AuthError.login(login.message ?? login.state ?? "La connexion Wix a été refusée.")
            }

            let verifier = Self.randomURLSafeString(byteCount: 48)
            let challenge = Self.sha256URLSafe(verifier)
            let state = Self.randomURLSafeString(byteCount: 24)
            let redirect = try await post(
                "https://www.wixapis.com/_api/redirects-api/v1/redirect-session",
                bearer: visitor.accessToken,
                body: [
                    "auth": [
                        "authRequest": [
                            "clientId": clientID,
                            "codeChallenge": challenge,
                            "codeChallengeMethod": "S256",
                            "responseMode": "fragment",
                            "responseType": "code",
                            "scope": "offline_access",
                            "sessionToken": sessionToken,
                            "state": state,
                            "redirectUri": redirectURI
                        ]
                    ]
                ],
                as: RedirectResponse.self
            )
            guard let loginURL = URL(string: redirect.redirectSession.fullUrl) else {
                throw AuthError.invalidResponse
            }

            let callbackURL = try await authenticate(url: loginURL)
            guard let (code, returnedState) = Self.authorizationValues(from: callbackURL), returnedState == state else {
                throw AuthError.invalidResponse
            }

            let tokens = try await requestToken([
                "clientId": clientID,
                "grantType": "authorization_code",
                "redirectUri": redirectURI,
                "code": code,
                "codeVerifier": verifier
            ])
            let memberPayload = try await getMember(accessToken: tokens.accessToken)
            let member = WixMember(
                id: memberPayload.id,
                loginEmail: memberPayload.loginEmail,
                loginEmailVerified: memberPayload.loginEmailVerified,
                status: memberPayload.status,
                firstName: memberPayload.contact?.firstName,
                lastName: memberPayload.contact?.lastName
            )
            let stored = StoredSession(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: Date().addingTimeInterval(tokens.expiresIn),
                member: member
            )
            try save(stored)
            self.member = member
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, role: String, profile: [String: String]) async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        errorMessage = nil
        infoMessage = nil
        defer { isSigningIn = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let givenName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), givenName.count >= 2, familyName.count >= 2,
              member != nil || password.count >= 8 else {
            errorMessage = "Indiquez un e-mail valide, vos prénom et nom, et un mot de passe d’au moins 8 caractères pour un nouveau compte."
            return false
        }
        if let member, member.loginEmail.caseInsensitiveCompare(normalizedEmail) != .orderedSame {
            errorMessage = "Un compte Wix est déjà connecté. Utilisez l’adresse e-mail de ce compte pour terminer son inscription."
            return false
        }

        do {
            if member == nil {
                let visitor = try await requestToken([
                    "clientId": clientID,
                    "grantType": "anonymous"
                ])
                let registration = try await post(
                    "https://www.wixapis.com/_api/iam/authentication/v2/register",
                    bearer: visitor.accessToken,
                    body: [
                        "login_id": ["email": normalizedEmail],
                        "password": password,
                        "profile": [
                            "firstName": givenName,
                            "lastName": familyName,
                            "nickname": "\(givenName) \(familyName)",
                            "privacyStatus": "PRIVATE"
                        ]
                    ],
                    as: RegistrationResponse.self
                )
                guard registration.state?.uppercased() == "SUCCESS",
                      let sessionToken = registration.sessionToken, !sessionToken.isEmpty else {
                    let state = registration.state?.uppercased() ?? ""
                    if state.contains("EMAIL") || state.contains("VERIFY") {
                        infoMessage = "Un code de vérification a été envoyé à \(normalizedEmail). Après validation, connectez-vous avec vos identifiants."
                        return false
                    }
                    throw AuthError.login(registration.message ?? "L’inscription n’a pas abouti (\(registration.state ?? "état inconnu")).")
                }
                try await establishMemberSession(sessionToken: sessionToken, visitorAccessToken: visitor.accessToken)
            }
            try await createRoleProfile(role: role, profile: profile)
            return true
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func createRoleProfile(role: String, profile: [String: String]) async throws {
        var body: [String: Any] = ["role": role, "acceptedTerms": true]
        body.merge(profile) { _, new in new }
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-role-registration")!, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible de créer votre espace métier Wix.")
        }
    }

    private func establishMemberSession(sessionToken: String, visitorAccessToken: String) async throws {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.sha256URLSafe(verifier)
        let state = Self.randomURLSafeString(byteCount: 24)
        let redirect = try await post(
            "https://www.wixapis.com/_api/redirects-api/v1/redirect-session",
            bearer: visitorAccessToken,
            body: [
                "auth": [
                    "authRequest": [
                        "clientId": clientID,
                        "codeChallenge": challenge,
                        "codeChallengeMethod": "S256",
                        "responseMode": "fragment",
                        "responseType": "code",
                        "scope": "offline_access",
                        "sessionToken": sessionToken,
                        "state": state,
                        "redirectUri": redirectURI
                    ]
                ]
            ],
            as: RedirectResponse.self
        )
        guard let loginURL = URL(string: redirect.redirectSession.fullUrl) else { throw AuthError.invalidResponse }
        let callbackURL = try await authenticate(url: loginURL)
        guard let (code, returnedState) = Self.authorizationValues(from: callbackURL), returnedState == state else {
            throw AuthError.invalidResponse
        }
        let tokens = try await requestToken([
            "clientId": clientID,
            "grantType": "authorization_code",
            "redirectUri": redirectURI,
            "code": code,
            "codeVerifier": verifier
        ])
        let payload = try await getMember(accessToken: tokens.accessToken)
        let member = WixMember(
            id: payload.id,
            loginEmail: payload.loginEmail,
            loginEmailVerified: payload.loginEmailVerified,
            status: payload.status,
            firstName: payload.contact?.firstName,
            lastName: payload.contact?.lastName
        )
        try save(StoredSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(tokens.expiresIn),
            member: member
        ))
        self.member = member
    }

    func signOut() {
        if let session = readStoredSession(),
           let installationID = UserDefaults.standard.string(forKey: "partenairefoyer.pushDeviceID.v1"),
           !installationID.isEmpty {
            // Capture the current Wix bearer before removing the local session;
            // cleanup runs best-effort and never delays the visible sign-out.
            Task { await disablePushDevices(installationID: installationID, accessToken: session.accessToken) }
        }
        resetDashboard()
        deleteStoredSession()
        member = nil
        errorMessage = nil
        infoMessage = nil
    }

    private func disablePushDevices(installationID: String, accessToken: String) async {
        do {
            let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-push-registration")!
            var request = URLRequest(url: endpoint, timeoutInterval: 25)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "action": "disable",
                "installationId": installationID
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
                throw AuthError.api(message ?? "Désactivation des notifications impossible.")
            }
        } catch {
            NSLog("Notifications iOS : désactivation différée (%@).", error.localizedDescription)
        }
    }

    func resetDashboard() {
        dashboardRequestID = UUID()
        dashboardData = nil
        dashboardError = nil
        isLoadingDashboard = false
    }

    func loadDashboard(role: String) async {
        let requestID = UUID()
        dashboardRequestID = requestID
        isLoadingDashboard = true
        dashboardData = nil
        dashboardError = nil
        defer {
            if dashboardRequestID == requestID {
                isLoadingDashboard = false
            }
        }
        do {
            let token = try await validAccessToken()
            var components = URLComponents(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
            components.queryItems = [URLQueryItem(name: "role", value: role)]
            var request = URLRequest(url: components.url!, timeoutInterval: 35)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw AuthError.api(payload?["error"] as? String ?? "Impossible de charger le tableau de bord.")
            }
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dashboard = payload["dashboard"] as? [String: Any] else {
                throw AuthError.invalidResponse
            }
            guard dashboardRequestID == requestID else { return }
            dashboardData = dashboard
        } catch {
            guard dashboardRequestID == requestID else { return }
            dashboardData = nil
            dashboardError = error.localizedDescription
        }
    }

    func createProfessionalProperty(
        title: String,
        description: String,
        propertyType: String,
        transactionType: String,
        price: Double,
        surface: Double,
        rooms: Int,
        bedrooms: Int,
        address: String,
        city: String,
        postalCode: String,
        photos: [String],
        publishImmediately: Bool
    ) async throws {
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
        var request = URLRequest(url: endpoint, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "create_professional_property",
            "role": "professionnel",
            "title": title,
            "description": description,
            "propertyType": propertyType,
            "transactionType": transactionType,
            "price": price,
            "surface": surface,
            "rooms": rooms,
            "bedrooms": bedrooms,
            "address": address,
            "city": city,
            "postalCode": postalCode,
            "photos": photos,
            "publishImmediately": publishImmediately
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible d’enregistrer le bien dans votre espace Wix.")
        }
    }

    func createPrivateProperty(
        title: String,
        description: String,
        propertyType: String,
        transactionType: String,
        price: Double,
        surface: Double,
        landSurface: Double?,
        rooms: Int,
        bedrooms: Int,
        bathrooms: Int,
        city: String,
        postalCode: String,
        photos: [String],
        publishImmediately: Bool
    ) async throws {
        var payload: [String: Any] = [
            "action": "create_private_property", "role": "particulier",
            "title": title, "description": description, "propertyType": propertyType,
            "transactionType": transactionType, "price": price, "surface": surface,
            "rooms": rooms, "bedrooms": bedrooms, "bathrooms": bathrooms,
            "city": city, "postalCode": postalCode, "publishImmediately": publishImmediately,
            "photos": photos,
        ]
        if let landSurface { payload["landSurface"] = landSurface }
        try await sendDashboardAction(payload, fallback: "Impossible d’enregistrer le bien dans votre espace Wix.")
    }

    func createClassifiedAd(
        itemName: String,
        itemDescription: String,
        itemPrice: Double,
        category: String,
        subcategory: String,
        itemCondition: String,
        city: String,
        postalCode: String,
        photos: [String]
    ) async throws {
        var payload: [String: Any] = [
            "action": "create_classified_ad", "role": "particulier",
            "itemName": itemName, "itemDescription": itemDescription, "itemPrice": itemPrice,
            "category": category, "subcategory": subcategory, "itemCondition": itemCondition,
            "city": city, "postalCode": postalCode,
            "photos": photos,
        ]
        try await sendDashboardAction(payload, fallback: "Impossible de publier la petite annonce dans Wix.")
    }

    func uploadListingPhotos(_ photos: [Data], role: String) async throws -> [String] {
        guard ["particulier", "professionnel"].contains(role), photos.count <= 12 else {
            throw AuthError.api("La sélection de photos pour l’annonce est invalide.")
        }
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
        var urls: [String] = []
        for photo in photos {
            guard !photo.isEmpty, photo.count <= 3 * 1024 * 1024 else {
                throw AuthError.api("Chaque photo doit faire moins de 3 Mo.")
            }
            var request = URLRequest(url: endpoint, timeoutInterval: 50)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "action": "upload_listing_photo", "role": role,
                "mimeType": "image/jpeg", "contentBase64": photo.base64EncodedString(),
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw AuthError.api(result?["error"] as? String ?? "Une photo n’a pas pu être envoyée.")
            }
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = result["url"] as? String,
                  url.hasPrefix("https://krvwwavxmuwieemubhdj.supabase.co/storage/v1/object/public/pf-ios-listing-photos/") else {
                throw AuthError.invalidResponse
            }
            urls.append(url)
        }
        return urls
    }

    private func sendDashboardAction(_ payload: [String: Any], fallback: String) async throws {
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
        var request = URLRequest(url: endpoint, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(result?["error"] as? String ?? fallback)
        }
    }

    func markInquiryRead(role: String, messageID: String) async {
        errorMessage = nil
        do {
            let token = try await validAccessToken()
            let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
            var request = URLRequest(url: endpoint, timeoutInterval: 35)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "action": "mark_inquiry_read", "role": role, "messageId": messageID
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw AuthError.api(payload?["error"] as? String ?? "Impossible de marquer ce message comme lu.")
            }
            if var dashboard = dashboardData, let currentMessages = dashboard["messages"] as? [[String: Any]] {
                dashboard["messages"] = currentMessages.map { item in
                    guard (item["_id"] as? String ?? item["id"] as? String) == messageID else { return item }
                    var updated = item
                    updated["isRead"] = true
                    return updated
                }
                dashboardData = dashboard
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markMatchingSeen(list: String, itemID: String) async {
        errorMessage = nil
        guard ["matchings", "demands"].contains(list) else { return }
        do {
            let token = try await validAccessToken()
            let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard-v2")!
            var request = URLRequest(url: endpoint, timeoutInterval: 35)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "action": "mark_matching_seen", "role": "professionnel", "list": list, "itemId": itemID
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw AuthError.api(payload?["error"] as? String ?? "Impossible d’actualiser ce matching.")
            }
            guard var dashboard = dashboardData, var items = dashboard[list] as? [[String: Any]] else { return }
            items = items.map { item in
                guard (item["_id"] as? String ?? item["id"] as? String) == itemID else { return item }
                var updated = item
                updated["seen"] = true
                if list == "demands" { updated["isViewed"] = true }
                return updated
            }
            dashboard[list] = items
            dashboardData = dashboard
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func registerPushDevice(role: String) async {
        // The host dashboard has no push owner type in the current notification
        // service. Do not register a token against an unrelated Wix profile.
        guard ["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire"].contains(role),
              let fcmToken = UserDefaults.standard.string(forKey: "partenairefoyer.fcmRegistrationToken"),
              !fcmToken.isEmpty else { return }

        let defaults = UserDefaults.standard
        let installationID: String
        if let existingID = defaults.string(forKey: "partenairefoyer.pushDeviceID.v1"), !existingID.isEmpty {
            installationID = existingID
        } else {
            installationID = UUID().uuidString.lowercased()
            defaults.set(installationID, forKey: "partenairefoyer.pushDeviceID.v1")
        }

        do {
            let token = try await validAccessToken()
            let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-push-registration")!
            var request = URLRequest(url: endpoint, timeoutInterval: 25)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "role": role,
                "deviceId": "\(installationID)-\(role)",
                "fcmToken": fcmToken
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw AuthError.api(payload?["error"] as? String ?? "Enregistrement des notifications impossible.")
            }
            NSLog("Notifications iOS : appareil associé à l’espace %@.", role)
        } catch {
            // Push is an optional capability; it must never block dashboard use.
            NSLog("Notifications iOS : enregistrement différé (%@).", error.localizedDescription)
        }
    }

    func loadProfessionalConversation(id: String) async throws -> [[String: Any]] {
        let conversationID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationID.isEmpty, conversationID.count <= 160 else {
            throw AuthError.api("Identifiant de conversation invalide.")
        }
        let token = try await validAccessToken()
        var components = URLComponents(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-conversation")!
        components.queryItems = [URLQueryItem(name: "conversationId", value: conversationID)]
        var request = URLRequest(url: components.url!, timeoutInterval: 35)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible de charger cette conversation.")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = payload["messages"] as? [[String: Any]] else {
            throw AuthError.invalidResponse
        }
        return messages.sorted {
            String(describing: $0["createdAt"] ?? "") < String(describing: $1["createdAt"] ?? "")
        }
    }

    func sendProfessionalMessage(conversationID: String, content: String) async throws -> [String: Any] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else {
            throw AuthError.api("Le message doit contenir entre 1 et 4 000 caractères.")
        }
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-conversation")!
        var request = URLRequest(url: endpoint, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["conversationId": conversationID, "content": text])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Le message n’a pas pu être envoyé.")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = payload["message"] as? [String: Any] else {
            throw AuthError.invalidResponse
        }
        return message
    }

    func markProfessionalConversationRead(conversationID: String) async throws {
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-conversation")!
        var request = URLRequest(url: endpoint, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "mark_read", "conversationId": conversationID])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible de marquer la conversation comme lue.")
        }
        if var dashboard = dashboardData, let currentMessages = dashboard["messages"] as? [[String: Any]] {
            dashboard["messages"] = currentMessages.map { item in
                guard (item["conversationId"] as? String) == conversationID else { return item }
                var updated = item
                updated["isRead"] = true
                updated["seen"] = true
                return updated
            }
            dashboardData = dashboard
        }
    }

    func loadHostConversation(id: String) async throws -> (hostID: String, messages: [[String: Any]]) {
        let conversationID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationID.isEmpty, conversationID.count <= 160 else {
            throw AuthError.api("Identifiant de conversation invalide.")
        }
        let token = try await validAccessToken()
        var components = URLComponents(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-host-conversation")!
        components.queryItems = [URLQueryItem(name: "conversationId", value: conversationID)]
        var request = URLRequest(url: components.url!, timeoutInterval: 35)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible de charger cette conversation.")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hostID = payload["hostId"] as? String,
              let messages = payload["messages"] as? [[String: Any]] else {
            throw AuthError.invalidResponse
        }
        return (hostID, messages)
    }

    func sendHostMessage(conversationID: String, content: String) async throws -> [String: Any] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else {
            throw AuthError.api("Le message doit contenir entre 1 et 4 000 caractères.")
        }
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-host-conversation")!
        var request = URLRequest(url: endpoint, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "send", "conversationId": conversationID, "content": text,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Le message n’a pas pu être envoyé.")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = payload["message"] as? [String: Any] else {
            throw AuthError.invalidResponse
        }
        return message
    }

    func markHostConversationRead(conversationID: String) async throws {
        let token = try await validAccessToken()
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-host-conversation")!
        var request = URLRequest(url: endpoint, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "mark_read", "conversationId": conversationID,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible de marquer cette conversation comme lue.")
        }
    }

    func submitEstimationRequest(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        address: String,
        city: String,
        postalCode: String,
        propertyType: String,
        propertyCondition: String,
        occupancyStatus: String,
        projectTimeline: String,
        livingArea: Double?,
        landArea: Double?,
        rooms: Double?,
        bedrooms: Double?,
        budget: Double?
    ) async throws {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        var data: [String: Any] = [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "requesterEmail": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "phoneNumber": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "address": address.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "postalCode": postalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "propertyType": propertyType,
            "propertyCondition": propertyCondition,
            "occupancyStatus": occupancyStatus,
            "projectTimeline": projectTimeline,
            "requestDate": ISO8601DateFormatter().string(from: Date())
        ]
        if let livingArea { data["livingArea"] = livingArea }
        if let landArea { data["landArea"] = landArea }
        if let rooms { data["numberOfRooms"] = rooms }
        if let bedrooms { data["numberOfBedrooms"] = bedrooms }
        if let budget { data["budget"] = budget }

        let result = try await post(
            "https://www.wixapis.com/wix-data/v2/items",
            bearer: visitor.accessToken,
            body: [
                "dataCollectionId": "demandesestimation",
                "dataItem": ["data": data]
            ],
            as: WixInsertDataItemResponse.self
        )
        guard let id = result.dataItem?.id, !id.isEmpty else {
            throw AuthError.invalidResponse
        }
    }

    func fetchPublicClassifiedAds() async throws -> [ClassifiedAd] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let fields = [
            "itemName", "itemDescription", "itemPrice", "category", "subcategory",
            "itemCondition", "city", "postalCode", "status", "itemImage",
            "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8",
            "photo9", "photo10", "photo11", "photo12", "photo13", "photo14",
            "photo15", "photo16", "photo17", "photo18", "photo19", "photo20"
        ]
        var offset = 0
        var ads: [ClassifiedAd] = []
        let pageSize = 100
        for _ in 0..<20 {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "classifiedads-1",
                    "query": [
                        "filter": ["status": ["$eq": "published"]],
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicClassifiedAdsResponse.self
            )
            ads.append(contentsOf: response.dataItems.compactMap { $0.data.classifiedAd(id: $0.id) })
            guard response.dataItems.count == pageSize else { break }
            offset += pageSize
        }
        return ads
    }

    func fetchPublicPrivateListings() async throws -> [Listing] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])

        let pageSize = 100
        var offset = 0
        var properties: [WixPublicPropertyItem] = []
        let fields = [
            "title", "description", "city", "postalCode", "sellingPrice", "estimatedPrice",
            "surface", "rooms", "bedrooms", "propertyType", "transactionType", "mainImage", "isPublic", "status",
            "galleryImages", "photo1", "photo2", "photo3", "photo4", "photo5", "photo6",
            "photo7", "photo8", "photo9", "photo10", "photo11", "photo12", "photo13",
            "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20"
        ]

        // Offset paging is capped at 2,000 public records per refresh to bound
        // network and memory use on the device.
        for _ in 0..<20 {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "privateproperties",
                    "query": [
                        "filter": [
                            "isPublic": ["$eq": true],
                            "status": ["$eq": "active"]
                        ],
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicPropertiesResponse.self
            )
            properties.append(contentsOf: response.dataItems)
            guard response.dataItems.count == pageSize else { break }
            offset += pageSize
        }

        return properties
            .filter { $0.data.isPublic == true && $0.data.status == "active" }
            .map(\.listing)
    }

    func fetchPublicProfessionals() async throws -> [WixPublicProfessional] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let records = try await fetchVisibleProfessionalRecords(accessToken: visitor.accessToken)
        return records.map { $0.data.professional(id: $0.id) }
    }

    func fetchPublicProfessionalListings() async throws -> [Listing] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let professionals = try await fetchVisibleProfessionalRecords(accessToken: visitor.accessToken)
        let professionalIDs = Array(Set(professionals.compactMap { $0.data.memberId }))
        guard !professionalIDs.isEmpty else { return [] }

        let pageSize = 100
        var listings: [Listing] = []
        let fields = [
            "title", "description", "city", "postalCode", "price", "surface", "surfaceHouse",
            "surfaceLand", "landSurface", "rooms", "bedrooms", "bathrooms", "propertyType",
            "transactionType", "mainImageUrl", "galleryImages", "commercialStatus", "slug", "status"
        ]

        // Listings are connected to Wix Members through `wixMemberId`, while
        // public directory records store the same ID as `memberId`. Query only
        // active listings for visible profiles and recheck the status in-app.
        for start in stride(from: 0, to: professionalIDs.count, by: 100) {
            let end = min(start + 100, professionalIDs.count)
            let batch = Array(professionalIDs[start..<end])
            var offset = 0
            for _ in 0..<20 {
                let response = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: visitor.accessToken,
                    body: [
                        "dataCollectionId": "biensprofessionnels",
                        "query": [
                            "filter": [
                                "wixMemberId": ["$in": batch],
                                "status": ["$eq": "active"]
                            ],
                            "paging": ["limit": pageSize, "offset": offset],
                            "fields": fields
                        ]
                    ],
                    as: WixPublicProfessionalPropertiesResponse.self
                )
                let activeItems = response.dataItems.filter { $0.data.status == "active" }
                listings.append(contentsOf: activeItems.map { $0.data.listing(id: $0.id) })
                guard response.dataItems.count == pageSize else { break }
                offset += pageSize
            }
        }
        return listings
    }

    private func fetchVisibleProfessionalRecords(accessToken: String) async throws -> [WixPublicProfessionalItem] {
        let pageSize = 100
        var offset = 0
        var records: [WixPublicProfessionalItem] = []
        let fields = [
            "companyName", "firstName", "lastName", "network", "city", "postalCode",
            "businessSector", "description", "photo", "website", "memberId", "isActive", "isVisibleInDirectory"
        ]

        for _ in 0..<20 {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: accessToken,
                body: [
                    "dataCollectionId": "professionnels",
                    "query": [
                        "filter": [
                            "isVisibleInDirectory": ["$eq": true],
                            "isActive": ["$eq": true]
                        ],
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicProfessionalsResponse.self
            )
            records.append(contentsOf: response.dataItems.filter {
                $0.data.isVisibleInDirectory == true && $0.data.isActive == true
            })
            guard response.dataItems.count == pageSize else { break }
            offset += pageSize
        }
        return records
    }

    func validAccessToken() async throws -> String {
        guard var session = readStoredSession() else { throw AuthError.login("Connectez-vous pour accéder à cet espace.") }
        guard session.expiresAt <= Date().addingTimeInterval(60) else { return session.accessToken }
        let refreshed = try await requestToken([
            "clientId": clientID,
            "grantType": "refresh_token",
            "refreshToken": session.refreshToken
        ])
        session = StoredSession(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: Date().addingTimeInterval(refreshed.expiresIn),
            member: session.member
        )
        try save(session)
        return session.accessToken
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: "www.partenairefoyer.com", path: "/api/auth/callback")
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            guard session.start() else {
                continuation.resume(throwing: AuthError.browserUnavailable)
                return
            }
        }
    }

    private func requestToken(_ body: [String: String]) async throws -> TokenResponse {
        try await post("https://www.wixapis.com/oauth2/token", bearer: nil, body: body, as: TokenResponse.self)
    }

    private func getMember(accessToken: String) async throws -> MemberResponse.MemberPayload {
        let url = URL(string: "https://www.wixapis.com/members/v1/members/my?fieldSet=FULL")!
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: MemberResponse = try await decode(request)
        return result.member
    }

    private func post<T: Decodable>(_ urlString: String, bearer: String?, body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: urlString)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await decode(request)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = (try? JSONDecoder().decode(WixAPIError.self, from: data))
            throw AuthError.api(apiError?.details ?? apiError?.message ?? "La connexion au service de comptes a échoué (\(http.statusCode)).")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AuthError.invalidResponse }
    }

    private struct WixAPIError: Decodable {
        let message: String?
        let details: String?
    }

    private enum AuthError: LocalizedError {
        case login(String)
        case api(String)
        case browserUnavailable
        case invalidResponse
        var errorDescription: String? {
            switch self {
            case .login(let message): return message
            case .api(let message): return message
            case .browserUnavailable: return "La fenêtre de connexion sécurisée n’a pas pu s’ouvrir. Réessayez."
            case .invalidResponse: return "La réponse de connexion n’a pas pu être vérifiée. Réessayez."
            }
        }
    }

    private static func authorizationValues(from url: URL) -> (String, String)? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else { return nil }
        var values = URLComponents()
        values.query = fragment
        guard let items = values.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else { return nil }
        return (code, state)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256URLSafe(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow(frame: .zero)
    }

    private func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: keychainService,
                                   kSecAttrAccount as String: "member-session"]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AuthError.invalidResponse }
    }

    private func restoreMember() {
        guard let session = readStoredSession() else { return }
        member = session.member
    }

    private func readStoredSession() -> StoredSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: "member-session",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func deleteStoredSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: "member-session"]
        SecItemDelete(query as CFDictionary)
    }
}

private struct WixInsertDataItemResponse: Decodable {
    let dataItem: WixInsertedDataItem?
}

private struct WixInsertedDataItem: Decodable {
    let id: String?
}
