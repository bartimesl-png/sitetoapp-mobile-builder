import AuthenticationServices
import Combine
import CoreLocation
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
    @Published private(set) var professionalPortalToken: String?
    @Published private(set) var professionalPortalEmail: String?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?
    @Published private(set) var infoMessage: String?
    @Published private(set) var dashboardData: [String: Any]?
    @Published private(set) var dashboardError: String?
    @Published private(set) var isLoadingDashboard = false

    private let clientID = "694d7a57-f31a-4a5d-9bdd-8829f8f89b4e"
    private let redirectURI = "https://www.partenairefoyer.com/api/auth/callback"
    private let keychainService = "com.partenairefoyer.app.wix-session"
    private let professionalPortalKeychainService = "com.partenairefoyer.app.pro-session"
    private var authSession: ASWebAuthenticationSession?
    private var dashboardRequestID = UUID()
    private var postalCommunesCache: [String: [PostalCommune]] = [:]

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

    private struct ProfessionalPortalLoginResponse: Decodable {
        struct Profile: Decodable {
            let email: String?
            let loginEmail: String?
        }
        let success: Bool?
        let sessionToken: String?
        let member: Profile?
        let error: String?
        let message: String?
        let code: String?
    }

    private struct RegistrationResponse: Decodable {
        let state: String?
        let sessionToken: String?
        let stateToken: String?
        let message: String?
    }

    private struct PostalCommune: Decodable {
        struct Center: Decodable {
            let coordinates: [Double]?
        }
        let nom: String
        let centre: Center?
    }

    private struct RedirectResponse: Decodable {
        struct Session: Decodable {
            let fullUrl: String
        }
        let redirectSession: Session
    }

    private struct WixDataItemWriteResponse: Decodable {
        struct DataItem: Decodable {
            let id: String?
        }
        let dataItem: DataItem?
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
        restoreProfessionalPortalSession()
    }

    func signInProfessionalPortal(email: String, password: String) async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        errorMessage = nil
        infoMessage = nil
        defer { isSigningIn = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), !password.isEmpty else {
            errorMessage = "Saisissez l’adresse e-mail et le mot de passe de votre espace professionnel."
            return false
        }

        do {
            var request = URLRequest(url: URL(string: "https://www.partenairefoyer.com/api/pro-app-login")!, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": normalizedEmail, "password": password])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            let payload = try? JSONDecoder().decode(ProfessionalPortalLoginResponse.self, from: data)
            guard (200..<300).contains(http.statusCode), payload?.success == true,
                  let token = payload?.sessionToken, !token.isEmpty else {
                if payload?.code?.uppercased() == "ACTIVATION_REQUIRED" {
                    infoMessage = payload?.message ?? "Votre espace professionnel doit être activé avant la première connexion. Utilisez le parcours d’activation."
                }
                throw AuthError.api(payload?.error ?? payload?.message ?? "La connexion à l’espace professionnel a été refusée.")
            }
            try saveProfessionalPortalSession(token: token, email: payload?.member?.email ?? payload?.member?.loginEmail ?? normalizedEmail)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func adoptProfessionalPortalSession(token: String, email: String? = nil) {
        guard !token.isEmpty else {
            deleteProfessionalPortalSession()
            professionalPortalToken = nil
            professionalPortalEmail = nil
            return
        }
        do {
            try saveProfessionalPortalSession(token: token, email: email ?? professionalPortalEmail ?? "")
            errorMessage = nil
            infoMessage = nil
        } catch {
            errorMessage = "La session professionnelle n’a pas pu être enregistrée sur cet appareil. Réessayez la connexion."
        }
    }

    private func saveProfessionalPortalSession(token: String, email: String) throws {
        let data = try JSONEncoder().encode(["token": token, "email": email])
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: professionalPortalKeychainService,
                                   kSecAttrAccount as String: "professional-portal-session"]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AuthError.invalidResponse }
        professionalPortalToken = token
        professionalPortalEmail = email
    }

    private func restoreProfessionalPortalSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: professionalPortalKeychainService,
                                    kSecAttrAccount as String: "professional-portal-session",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode([String: String].self, from: data),
              let token = session["token"], !token.isEmpty else { return }
        professionalPortalToken = token
        professionalPortalEmail = session["email"]
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
                body: ["login_id": ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()], "password": password],
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
            errorMessage = userFacingAuthError(error)
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, role: String, profile: [String: String], acceptedCGU: Bool, acceptedCGV: Bool) async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        errorMessage = nil
        infoMessage = nil
        defer { isSigningIn = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let givenName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard acceptedCGU && acceptedCGV else {
            errorMessage = "Vous devez consulter et accepter les CGU et les CGV applicables à votre espace."
            return false
        }
        guard normalizedEmail.contains("@"), givenName.count >= 2, familyName.count >= 2,
              password.count >= 8 || (member != nil && !["artisan", "diagnostiqueur"].contains(role)) else {
            errorMessage = "Indiquez un e-mail valide, vos prénom et nom, et un mot de passe d’au moins 8 caractères pour créer votre compte métier."
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
            try await createRoleProfile(role: role, profile: profile, password: password, acceptedCGU: acceptedCGU, acceptedCGV: acceptedCGV)
            return true
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = userFacingAuthError(error)
        }
        return false
    }

    private func createRoleProfile(role: String, profile: [String: String], password: String, acceptedCGU: Bool, acceptedCGV: Bool) async throws {
        var body: [String: Any] = [
            "role": role,
            "acceptedTerms": acceptedCGU && acceptedCGV,
            "cguAccepted": acceptedCGU,
            "cgvAccepted": acceptedCGV,
            "legalAcceptanceSource": "ios-native"
        ]
        body.merge(profile) { _, new in new }
        // The Wix site still authenticates artisan/diagnostician accounts in
        // its legacy prosaccounts collection. The edge function hashes this
        // value before storing it; never persist or log the clear-text value.
        if ["artisan", "diagnostiqueur"].contains(role) {
            body["legacyPassword"] = password
        }
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
            let message = payload?["error"] as? String ?? "Impossible de créer votre espace métier Wix."
            if message.localizedCaseInsensitiveContains("vérifié") {
                infoMessage = "Wix doit confirmer votre adresse e-mail avant la création de l’espace. Vérifiez votre boîte de réception, puis reconnectez-vous."
            }
            throw AuthError.api(message)
        }
        if role == "professionnel",
           let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let notifications = payload["emailNotifications"] as? [String: Any],
           notifications.values.contains(where: { $0 as? Bool == false }) {
            infoMessage = "Votre compte est créé, mais au moins un e-mail de bienvenue n’a pas pu être déclenché. Vérifiez votre boîte e-mail et contactez PartenaireFoyer si vous n’avez rien reçu."
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
        if let installationID = UserDefaults.standard.string(forKey: "partenairefoyer.pushDeviceID.v1"),
           !installationID.isEmpty {
            // Capture available credentials before clearing Keychain; cleanup is
            // best effort and never delays the visible sign-out.
            let wixToken = readStoredSession()?.accessToken
            let proToken = professionalPortalToken
            if let proToken {
                Task { await disablePushDevices(installationID: installationID, accessToken: proToken) }
            }
            if let wixToken, wixToken != proToken {
                Task { await disablePushDevices(installationID: installationID, accessToken: wixToken) }
            }
        }
        FavoritesStore.shared.switchToAnonymousFavorites()
        resetDashboard()
        deleteStoredSession()
        deleteProfessionalPortalSession()
        member = nil
        professionalPortalToken = nil
        professionalPortalEmail = nil
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
        landSurface: Double?,
        rooms: Int,
        bedrooms: Int,
        bathrooms: Int,
        hasGarage: Bool,
        hasSwimmingPool: Bool,
        hasAnnex: Bool,
        address: String,
        city: String,
        postalCode: String,
        latitude: Double?,
        longitude: Double?,
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
        var payload: [String: Any] = [
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
            "bathrooms": bathrooms,
            "hasGarage": hasGarage,
            "hasSwimmingPool": hasSwimmingPool,
            "hasAnnex": hasAnnex,
            "address": address,
            "city": city,
            "postalCode": postalCode,
            "photos": photos,
            "publishImmediately": publishImmediately
        ]
        if let landSurface { payload["landSurface"] = landSurface }
        if let latitude { payload["latitude"] = latitude }
        if let longitude { payload["longitude"] = longitude }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
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
        hasGarage: Bool,
        hasSwimmingPool: Bool,
        hasAnnex: Bool,
        city: String,
        postalCode: String,
        latitude: Double?,
        longitude: Double?,
        photos: [String],
        publishImmediately: Bool
    ) async throws {
        var payload: [String: Any] = [
            "action": "create_private_property", "role": "particulier",
            "title": title, "description": description, "propertyType": propertyType,
            "transactionType": transactionType, "price": price, "surface": surface,
            "rooms": rooms, "bedrooms": bedrooms, "bathrooms": bathrooms,
            "hasGarage": hasGarage, "hasPiscine": hasSwimmingPool, "hasAnnexe": hasAnnex,
            "city": city, "postalCode": postalCode, "publishImmediately": publishImmediately,
            "photos": photos,
        ]
        if let landSurface { payload["landSurface"] = landSurface }
        if let latitude { payload["latitude"] = latitude }
        if let longitude { payload["longitude"] = longitude }
        try await sendDashboardAction(payload, fallback: "Impossible d’enregistrer le bien dans votre espace Wix.")
    }

    func createClassifiedAd(
        itemName: String,
        itemDescription: String,
        itemPrice: Double,
        category: String,
        subcategory: String,
        listingType: String,
        rentalUnit: String,
        itemCondition: String,
        city: String,
        postalCode: String,
        photos: [String],
        attributes: [String: String]
    ) async throws {
        var payload: [String: Any] = [
            "action": "create_classified_ad", "role": "particulier",
            "itemName": itemName, "itemDescription": itemDescription, "itemPrice": itemPrice,
            "category": category, "subcategory": subcategory, "adListingType": listingType, "itemCondition": itemCondition,
            "rentalUnit": rentalUnit,
            "city": city, "postalCode": postalCode,
            "photos": photos,
            "attributes": attributes,
        ]
        try await sendDashboardAction(payload, fallback: "Impossible de publier la petite annonce dans Wix.")
    }

    func reportClassifiedAd(
        adID: String,
        reason: String,
        details: String,
        clientReportKey: String
    ) async throws -> String {
        guard let member, member.loginEmailVerified != false else {
            throw AuthError.api("Connectez-vous à votre compte PartenaireFoyer pour signaler une annonce.")
        }
        let adIdentifier = adID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard adIdentifier.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else {
            throw AuthError.api("Identifiant d’annonce invalide.")
        }
        let role = UserDefaults.standard.string(forKey: "partenairefoyer.activeRole") ?? ""
        guard ["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire"].contains(role) else {
            throw AuthError.api("Ouvrez votre espace PartenaireFoyer pour confirmer votre profil avant le signalement.")
        }
        if dashboardData?["role"] as? String != role {
            await loadDashboard(role: role)
        }
        guard let dashboard = dashboardData, dashboard["role"] as? String == role else {
            throw AuthError.api(dashboardError ?? "Impossible de vérifier votre profil. Ouvrez votre espace puis réessayez.")
        }
        let profile = dashboard["profile"] as? [String: Any] ?? [:]
        let account = dashboard["account"] as? [String: Any] ?? [:]
        let reporterOwnerID: String
        let reporterOwnerType: String
        switch role {
        case "particulier":
            reporterOwnerID = (account["id"] as? String) ?? ""
            reporterOwnerType = "private"
        case "professionnel":
            reporterOwnerID = (profile["_id"] as? String) ?? ""
            reporterOwnerType = "professional"
        case "artisan", "diagnostiqueur":
            reporterOwnerID = (profile["_id"] as? String) ?? ""
            reporterOwnerType = "artisan"
        case "courtier":
            reporterOwnerID = (profile["_id"] as? String) ?? ""
            reporterOwnerType = "broker"
        case "prestataire":
            reporterOwnerID = (profile["_id"] as? String) ?? ""
            reporterOwnerType = "service_provider"
        default:
            reporterOwnerID = ""
            reporterOwnerType = ""
        }
        guard !reporterOwnerID.isEmpty else {
            throw AuthError.api("Votre profil ne permet pas de confirmer votre identité pour ce signalement.")
        }
        let displayName = [
            profile["firstName"] as? String,
            profile["lastName"] as? String
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let resolvedName = displayName.isEmpty
            ? (profile["companyName"] as? String ?? profile["businessName"] as? String ?? profile["fullName"] as? String ?? member.firstName ?? "Membre PartenaireFoyer")
            : displayName
        let email = (profile["email"] as? String ?? profile["contactEmail"] as? String ?? member.loginEmail)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let endpoint = URL(string: "https://www.partenairefoyer.com/api/classified-report")!
        var request = URLRequest(url: endpoint, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "adId": adIdentifier,
            "reason": reason,
            "details": String(details.prefix(2000)),
            "reporterOwnerId": reporterOwnerID,
            "reporterOwnerType": reporterOwnerType,
            "reporterDisplayName": String(resolvedName.prefix(160)),
            "reporterEmail": String(email.prefix(320)),
            "clientReportKey": String(clientReportKey.prefix(160)),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode), payload["success"] as? Bool == true else {
            throw AuthError.api(payload["error"] as? String ?? "Impossible d’envoyer le signalement.")
        }
        return payload["message"] as? String ?? "Merci. Votre signalement a été transmis à l’administration."
    }

    func archiveListing(role: String, list: String, itemID: String) async {
        errorMessage = nil
        guard ["particulier", "professionnel"].contains(role),
              ["properties", "classifieds"].contains(list),
              role == "particulier" || list == "properties" else { return }
        do {
            try await sendDashboardAction([
                "action": "archive_listing", "role": role, "list": list, "itemId": itemID,
            ], fallback: "Impossible d’archiver cette annonce.")
            if var dashboard = dashboardData, let items = dashboard[list] as? [[String: Any]] {
                dashboard[list] = items.filter { ($0["_id"] as? String ?? $0["id"] as? String) != itemID }
                dashboardData = dashboard
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateListing(role: String, list: String, itemID: String, fields: [String: Any]) async throws {
        try await sendDashboardAction([
            "action": "update_listing", "role": role, "list": list,
            "itemId": itemID, "fields": fields,
        ], fallback: "Impossible de modifier cette annonce.")
    }

    func updateRoleProfile(role: String, profileID: String, fields: [String: Any]) async throws {
        guard !isSigningIn else { throw AuthError.api("Une opération est déjà en cours.") }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await sendDashboardAction([
                "action": "update_profile", "role": role,
                "profileId": profileID, "fields": fields,
            ], fallback: "Impossible de modifier votre profil.")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func uploadListingPhotos(_ photos: [Data], role: String) async throws -> [String] {
        let maximumPhotos = role == "hebergeur" ? 35 : 12
        guard ["particulier", "professionnel", "hebergeur"].contains(role), photos.count <= maximumPhotos else {
            throw AuthError.api("La sélection de photos est invalide.")
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

    private func sendDashboardAction(_ payload: [String: Any], fallback: String) async throws -> [String: Any] {
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
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
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

    func acceptNetworkOpportunity(opportunityID: String) async {
        errorMessage = nil
        let cleanID = opportunityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "accept_matching_opportunity",
                "role": "professionnel",
                "opportunityId": cleanID,
            ], fallback: "Impossible d’accepter cette opportunité réseau.")
            await loadDashboard(role: "professionnel")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func hidePrivatePropertyMatching(role: String, matchingID: String) async {
        errorMessage = nil
        let cleanID = matchingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["particulier", "professionnel"].contains(role), !cleanID.isEmpty else { return }
        let list = role == "particulier" ? "vendorMatchings" : "privatePropertyMatchings"
        do {
            try await sendDashboardAction([
                "action": "hide_private_property_matching",
                "role": role,
                "matchingId": cleanID,
            ], fallback: "Impossible de masquer ce matching.")
            guard var dashboard = dashboardData, let items = dashboard[list] as? [[String: Any]] else { return }
            dashboard[list] = items.filter { ($0["_id"] as? String ?? $0["id"] as? String) != cleanID }
            dashboardData = dashboard
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProfessionalMatching(matchingID: String) async {
        errorMessage = nil
        let cleanID = matchingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "delete_professional_matching",
                "role": "professionnel",
                "matchingId": cleanID,
            ], fallback: "Impossible de supprimer ce matching.")
            guard var dashboard = dashboardData, let items = dashboard["matchings"] as? [[String: Any]] else { return }
            dashboard["matchings"] = items.filter { ($0["_id"] as? String ?? $0["id"] as? String) != cleanID }
            dashboardData = dashboard
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func claimDemand(demandID: String) async {
        errorMessage = nil
        let cleanID = demandID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "claim_demand", "role": "professionnel", "demandId": cleanID,
            ], fallback: "Impossible d’accepter cette demande.")
            await loadDashboard(role: "professionnel")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func hideHostBookingRequest(requestID: String) async {
        errorMessage = nil
        let cleanID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "hide_booking_request", "role": "hebergeur", "requestId": cleanID,
            ], fallback: "Impossible de masquer cette demande de réservation.")
            if var dashboard = dashboardData, let requests = dashboard["bookingRequests"] as? [[String: Any]] {
                dashboard["bookingRequests"] = requests.filter { ($0["_id"] as? String ?? $0["id"] as? String) != cleanID }
                dashboardData = dashboard
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transitionHostBookingRequest(requestID: String, status: String) async {
        errorMessage = nil
        let cleanID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, ["accepted", "rejected"].contains(status) else { return }
        do {
            let result = try await sendDashboardAction([
                "action": "transition_booking_request", "role": "hebergeur",
                "requestId": cleanID, "status": status,
            ], fallback: "Impossible de mettre à jour cette réservation.")
            await loadDashboard(role: "hebergeur")
            if result["emailSent"] as? Bool == false {
                errorMessage = "La réservation a été mise à jour, mais l’e-mail de notification n’a pas pu être envoyé."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSeasonalCalendarDates(accommodationID: String, dates: [String], availabilityStatus: String, pricePerNight: Double?, minimumStay: Int?) async throws {
        let cleanAccommodationID = accommodationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccommodationID.isEmpty, !dates.isEmpty, dates.count <= 31,
              ["available", "blocked"].contains(availabilityStatus),
              dates.allSatisfy({ $0.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil }),
              pricePerNight.map({ $0 >= 0 && $0 <= 100_000 }) ?? true,
              minimumStay.map({ (1...365).contains($0) }) ?? true else {
            throw AuthError.api("Vérifiez les dates, le tarif et le séjour minimum.")
        }
        var payload: [String: Any] = [
            "action": "save_seasonal_calendar_dates", "role": "hebergeur",
            "accommodationId": cleanAccommodationID, "dates": dates,
            "availabilityStatus": availabilityStatus,
        ]
        if let pricePerNight { payload["pricePerNight"] = pricePerNight }
        if let minimumStay { payload["minimumStay"] = minimumStay }
        try await sendDashboardAction(payload, fallback: "Impossible de modifier ces disponibilités.")
        await loadDashboard(role: "hebergeur")
    }

    func saveSeasonalRate(rateID: String?, accommodationID: String, seasonName: String, startDate: String, endDate: String, pricePerNight: Double, minimumStayNights: Int) async throws {
        let cleanAccommodationID = accommodationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRateID = rateID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = seasonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccommodationID.isEmpty, cleanName.count >= 2,
              startDate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              endDate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              startDate <= endDate, pricePerNight > 0, pricePerNight <= 100_000,
              (1...365).contains(minimumStayNights) else {
            throw AuthError.api("Vérifiez le nom, les dates et les critères du tarif.")
        }
        var payload: [String: Any] = [
            "action": "save_seasonal_rate", "role": "hebergeur",
            "accommodationId": cleanAccommodationID,
            "seasonName": cleanName,
            "startDate": startDate,
            "endDate": endDate,
            "pricePerNight": pricePerNight,
            "minimumStayNights": minimumStayNights,
        ]
        if let cleanRateID, !cleanRateID.isEmpty { payload["rateId"] = cleanRateID }
        try await sendDashboardAction(payload, fallback: "Impossible d’enregistrer ce tarif.")
        await loadDashboard(role: "hebergeur")
    }

    func deleteSeasonalRate(rateID: String) async throws {
        let cleanID = rateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { throw AuthError.api("Tarif saisonnier invalide.") }
        try await sendDashboardAction([
            "action": "delete_seasonal_rate", "role": "hebergeur", "rateId": cleanID,
        ], fallback: "Impossible de supprimer ce tarif.")
        await loadDashboard(role: "hebergeur")
    }

    func saveHostAccommodation(accommodationID: String?, fields: [String: Any], status: String) async throws {
        var payload = fields
        payload["action"] = "save_host_accommodation"
        payload["role"] = "hebergeur"
        payload["status"] = status
        if let accommodationID, !accommodationID.isEmpty { payload["accommodationId"] = accommodationID }
        try await sendDashboardAction(payload, fallback: "Impossible d’enregistrer cet hébergement.")
        await loadDashboard(role: "hebergeur")
    }

    func deleteHostAccommodation(accommodationID: String) async throws {
        let cleanID = accommodationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { throw AuthError.api("Hébergement invalide.") }
        try await sendDashboardAction([
            "action": "delete_host_accommodation", "role": "hebergeur", "accommodationId": cleanID,
        ], fallback: "Impossible de supprimer cet hébergement.")
        await loadDashboard(role: "hebergeur")
    }

    func markMinisiteRequestProcessed(requestID: String) async {
        errorMessage = nil
        let cleanID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "mark_minisite_request_processed", "role": "professionnel", "requestId": cleanID,
            ], fallback: "Impossible de mettre à jour cette demande mini-site.")
            await loadDashboard(role: "professionnel")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMinisiteRequest(requestID: String) async {
        errorMessage = nil
        let cleanID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        do {
            try await sendDashboardAction([
                "action": "delete_minisite_request", "role": "professionnel", "requestId": cleanID,
            ], fallback: "Impossible de supprimer cette demande mini-site.")
            if var dashboard = dashboardData, let requests = dashboard["minisiteRequests"] as? [[String: Any]] {
                dashboard["minisiteRequests"] = requests.filter { ($0["_id"] as? String ?? $0["id"] as? String) != cleanID }
                dashboardData = dashboard
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func registerPushDevice(role: String) async {
        // The host dashboard has no push owner type in the current notification
        // service. Do not register a token against an unrelated Wix profile.
        guard ["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire"].contains(role) else { return }
        guard await AppDelegate.requestPushAuthorization() else { return }
        guard let fcmToken = UserDefaults.standard.string(forKey: "partenairefoyer.fcmRegistrationToken"),
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
            let token: String
            if role == "professionnel", let portalToken = professionalPortalToken, !portalToken.isEmpty {
                token = portalToken
            } else {
                token = try await validAccessToken()
            }
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
        if let coordinate = await coordinates(city: city, postalCode: postalCode) {
            data["latitude"] = coordinate.latitude
            data["longitude"] = coordinate.longitude
        }

        let demandLatitude = data["latitude"] as? Double
        let demandLongitude = data["longitude"] as? Double
        let hasDirectMatch = try await hasDemandMatch(
            postalCode: postalCode,
            latitude: demandLatitude,
            longitude: demandLongitude,
            accessToken: visitor.accessToken
        )
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

        var estimationDemand: [String: Any] = [
            "demandType": "estimation_bien",
            "senderName": "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))",
            "senderEmail": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "senderPhone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "postalCode": postalCode,
            "department": String(postalCode.prefix(2)),
            "hasDirectMatch": hasDirectMatch,
            "propertyType": propertyType,
            "description": "\(propertyCondition) · Occupation : \(occupancyStatus) · Délai : \(projectTimeline)",
            "projectDescription": "Demande d’estimation"
        ]
        if let livingArea { estimationDemand["livingArea"] = livingArea }
        if let landArea { estimationDemand["landArea"] = landArea }
        if let rooms { estimationDemand["rooms"] = rooms }
        if let bedrooms { estimationDemand["bedrooms"] = bedrooms }
        if let budget { estimationDemand["budget"] = budget }
        if let latitude = data["latitude"] { estimationDemand["latitude"] = latitude }
        if let longitude = data["longitude"] { estimationDemand["longitude"] = longitude }
        estimationDemand["department"] = departmentFromPostalCode(postalCode)

        let demand = try await post(
            "https://www.wixapis.com/wix-data/v2/items",
            bearer: visitor.accessToken,
            body: [
                "dataCollectionId": "particuliersprives",
                "dataItem": ["data": estimationDemand]
            ],
            as: WixInsertDataItemResponse.self
        )
        guard let demandID = demand.dataItem?.id, !demandID.isEmpty else { throw AuthError.invalidResponse }
        await notifyPublicDemand(
            demandType: "estimation_bien", postalCode: postalCode, email: email,
            firstName: firstName, lastName: lastName, propertyType: propertyType,
            budgetMin: nil, budgetMax: nil, latitude: demandLatitude, longitude: demandLongitude,
            accessToken: visitor.accessToken
        )
    }

    func submitPublicDemand(_ fields: [String: Any], demandType: String, postalCode: String) async throws {
        guard ["recherche_achat", "recherche_location", "mise_en_location"].contains(demandType),
              postalCode.count == 5, postalCode.allSatisfy(\.isNumber) else {
            throw AuthError.api("Vérifiez le type de demande et le code postal (5 chiffres).")
        }
        let visitor = try await requestToken(["clientId": clientID, "grantType": "anonymous"])
        var entry = fields
        entry["demandType"] = demandType
        entry["postalCode"] = postalCode
        entry["department"] = departmentFromPostalCode(postalCode)
        if let city = entry["city"] as? String,
           let coordinate = await coordinates(city: city, postalCode: postalCode) {
            entry["latitude"] = coordinate.latitude
            entry["longitude"] = coordinate.longitude
        }
        let hasDirectMatch = try await hasDemandMatch(
            postalCode: postalCode,
            latitude: entry["latitude"] as? Double,
            longitude: entry["longitude"] as? Double,
            accessToken: visitor.accessToken
        )
        entry["hasDirectMatch"] = hasDirectMatch
        let created = try await post(
            "https://www.wixapis.com/wix-data/v2/items",
            bearer: visitor.accessToken,
            body: ["dataCollectionId": "particuliersprives", "dataItem": ["data": entry]],
            as: WixInsertDataItemResponse.self
        )
        guard let id = created.dataItem?.id, !id.isEmpty else { throw AuthError.invalidResponse }
        await notifyPublicDemand(
            demandType: demandType,
            postalCode: postalCode,
            email: (entry["email"] as? String) ?? (entry["senderEmail"] as? String) ?? "",
            firstName: (entry["firstName"] as? String) ?? (entry["senderName"] as? String) ?? "",
            lastName: (entry["lastName"] as? String) ?? "",
            propertyType: (entry["propertyType"] as? String) ?? "",
            budgetMin: entry["budgetMin"] as? Double,
            budgetMax: entry["budgetMax"] as? Double,
            latitude: entry["latitude"] as? Double,
            longitude: entry["longitude"] as? Double,
            accessToken: visitor.accessToken
        )
    }

    func postalCommunes(postalCode: String) async -> [String] {
        let communes = await loadPostalCommunes(postalCode: postalCode)
        return communes.map(\.nom)
    }

    private func notifyPublicDemand(
        demandType: String,
        postalCode: String,
        email: String,
        firstName: String,
        lastName: String,
        propertyType: String,
        budgetMin: Double?,
        budgetMax: Double?,
        latitude: Double?,
        longitude: Double?,
        accessToken: String
    ) async {
        let recipients = await matchingProfessionalEmails(
            postalCode: postalCode, latitude: latitude, longitude: longitude, accessToken: accessToken
        )
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let budget: String
        if let budgetMin, let budgetMax {
            budget = "€\(Int(budgetMin)) - €\(Int(budgetMax))"
        } else {
            budget = "Not specified"
        }
        let params: [String: Any] = [
            "buyerName": "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespacesAndNewlines),
            "postalCode": postalCode,
            "propertyType": propertyType.isEmpty ? "Not specified" : propertyType,
            "budget": budget,
        ]
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-brevo-email")
        if let endpoint {
            await withTaskGroup(of: Void.self) { group in
                for recipient in recipients {
                    group.addTask {
                        var request = URLRequest(url: endpoint, timeoutInterval: 20)
                        request.httpMethod = "POST"
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try? JSONSerialization.data(withJSONObject: [
                            "to": [["email": recipient]],
                            "sender": ["name": "PartenaireFoyer", "email": "contact@partenairefoyer.com"],
                            "templateId": 7,
                            "params": params,
                        ])
                        _ = try? await URLSession.shared.data(for: request)
                    }
                }
            }
        }

        // Keep the website's notification hook. Its failure must not undo a
        // successfully saved public request.
        if let notifyURL = URL(string: "https://www.partenairefoyer.com/api/notify") {
            var request = URLRequest(url: notifyURL, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "type": demandType,
                "postalCode": postalCode,
                "email": cleanEmail,
            ])
            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private func matchingProfessionalEmails(
        postalCode: String,
        latitude: Double?,
        longitude: Double?,
        accessToken: String
    ) async -> [String] {
        let targetPostal = postalCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let fields = ["email", "mainPostalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude"]
        var offset = 0
        var recipients = Set<String>()
        while true {
            guard let response = try? await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: accessToken,
                body: ["dataCollectionId": "professionnels", "query": [
                    "paging": ["limit": 100, "offset": offset], "fields": fields
                ]],
                as: WixRawDirectoryResponse.self
            ) else { break }
            for item in response.dataItems {
                let data = item.data.mapValues(\.value)
                let main = (importedString(data, ["mainPostalCode"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                var matches = !main.isEmpty && main == targetPostal
                let secondaryValue = data["secondaryPostalCodes"]
                let secondaryCodes: [String]
                if let values = secondaryValue as? [String] {
                    secondaryCodes = values
                } else if let values = secondaryValue as? [Any] {
                    secondaryCodes = values.compactMap { $0 as? String }
                } else if let text = secondaryValue as? String {
                    if let jsonData = text.data(using: .utf8),
                       let values = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                        secondaryCodes = values
                    } else {
                        secondaryCodes = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }).map(String.init)
                    }
                } else {
                    secondaryCodes = []
                }
                if secondaryCodes.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetPostal }) {
                    matches = true
                }
                if !matches, let latitude, let longitude,
                   let proLatitude = data["latitude"] as? Double,
                   let proLongitude = data["longitude"] as? Double,
                   let radius = data["maxRadiusKm"] as? Double, radius > 0 {
                    let professional = CLLocation(latitude: proLatitude, longitude: proLongitude)
                    let demand = CLLocation(latitude: latitude, longitude: longitude)
                    matches = professional.distance(from: demand) / 1000 <= radius
                }
                if matches, let email = data["email"] as? String {
                    let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if clean.contains("@") { recipients.insert(clean) }
                }
            }
            guard response.dataItems.count == 100 else { break }
            offset += response.dataItems.count
        }
        return recipients.sorted()
    }

    @discardableResult
    func contactImportedProfessional(id: String, category: String, senderName: String, senderEmail: String, senderPhone: String, message: String, listingID: String? = nil, pageUrl: String? = nil) async throws -> Bool {
        guard ["artisan", "diagnostiqueur", "courtier", "prestataire", "immobilier"].contains(category), !id.isEmpty else {
            throw AuthError.api("Cette fiche professionnelle ne peut pas recevoir de demande.")
        }
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-professional-contact")!
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let isRealEstate = category == "immobilier"
        var body: [String: Any] = [
            "sourceKind": isRealEstate ? "real_estate" : "local", "proId": id,
            "senderName": senderName, "senderEmail": senderEmail,
            "message": message
        ]
        if let listingID, !listingID.isEmpty { body["listingId"] = listingID }
        if let pageUrl, !pageUrl.isEmpty {
            body["pageUrl"] = pageUrl
        } else if listingID == nil {
            body["pageUrl"] = "https://www.partenairefoyer.com/professionnels"
        }
        if !isRealEstate { body["category"] = category }
        if !senderPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["senderPhone"] = senderPhone }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Impossible d’envoyer votre demande.")
        }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return payload?["notificationSent"] as? Bool ?? true
    }

    func submitProfessionalMinisiteRequest(
        professionalID: String,
        professionalName: String,
        professionalEmail: String?,
        requestType: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        message: String,
        propertyFields: [String: Any]
    ) async throws -> Bool {
        guard ["contact", "estimation", "proposition"].contains(requestType), !professionalID.isEmpty else {
            throw AuthError.api("Cette fiche ne permet pas de recevoir cette demande.")
        }
        var data: [String: Any] = [
            "professionalId": professionalID,
            "requestType": requestType,
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "phoneNumber": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "requestDate": ISO8601DateFormatter().string(from: Date()),
            "status": "new"
        ]
        data.merge(propertyFields) { _, new in new }
        let visitor = try await requestToken(["clientId": clientID, "grantType": "anonymous"])
        let created = try await post(
            "https://www.wixapis.com/wix-data/v2/items",
            bearer: visitor.accessToken,
            body: ["dataCollectionId": "demandesminisite", "dataItem": ["data": data]],
            as: WixInsertDataItemResponse.self
        )
        guard let id = created.dataItem?.id, !id.isEmpty else { throw AuthError.invalidResponse }

        // Match the Wix site's sequence: CMS write first, then push and direct email.
        if let notifyURL = URL(string: "https://www.partenairefoyer.com/api/minisite-push-notify") {
            var notify = URLRequest(url: notifyURL, timeoutInterval: 13)
            notify.httpMethod = "POST"
            notify.setValue("application/json", forHTTPHeaderField: "Content-Type")
            notify.httpBody = try? JSONSerialization.data(withJSONObject: ["requestId": id])
            URLSession.shared.dataTask(with: notify).resume()
        }

        guard let recipient = professionalEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              recipient.contains("@"), !recipient.isEmpty,
              let emailURL = URL(string: "https://www.partenairefoyer.com/api/sendMinisiteEmail") else { return false }
        let typeLabel = requestType == "contact" ? "Contact" : requestType == "estimation" ? "Estimation" : "Proposition"
        let safe = [professionalName, firstName, lastName, email, phone, message]
            .map { $0.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let html = "<h2>Nouvelle demande de \(typeLabel)</h2><p>Bonjour \(safe[0]),</p><p>Demande de \(safe[1]) \(safe[2])</p><p>E-mail : \(safe[3])<br>Téléphone : \(safe[4])</p><p>\(safe[5].replacingOccurrences(of: "\n", with: "<br>"))</p>"
        var emailRequest = URLRequest(url: emailURL, timeoutInterval: 20)
        emailRequest.httpMethod = "POST"
        emailRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        emailRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "toEmail": recipient,
            "subject": "Nouvelle demande de \(typeLabel) - \(safe[1]) \(safe[2])",
            "htmlContent": html
        ])
        do {
            let (_, emailResponse) = try await URLSession.shared.data(for: emailRequest)
            guard let http = emailResponse as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func submitProfessionalPropertyContactRequest(
        listingID: String,
        propertyTitle: String,
        recipientEmail: String,
        recipientName: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        message: String,
        requestID: String
    ) async throws -> Bool {
        let cleanID = listingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanTitle = propertyTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil,
              recipientEmail.contains("@"), cleanEmail.contains("@"), cleanMessage.count >= 5 else {
            throw AuthError.api("Vérifiez le bien, votre e-mail et votre message.")
        }

        func htmlEscaped(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        let propertyURL = "https://www.partenairefoyer.com/annonce/\(cleanID)"
        let emailURL = URL(string: "https://www.partenairefoyer.com/api/send-contact-email")!
        var emailRequest = URLRequest(url: emailURL, timeoutInterval: 25)
        emailRequest.httpMethod = "POST"
        emailRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        emailRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        emailRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "recipientEmail": recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            "recipientName": htmlEscaped(recipientName),
            "propertyTitle": htmlEscaped(cleanTitle),
            "propertyUrl": propertyURL,
            "senderName": htmlEscaped("\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))"),
            "senderEmail": htmlEscaped(cleanEmail),
            "senderPhone": htmlEscaped(phone.trimmingCharacters(in: .whitespacesAndNewlines)),
            "message": htmlEscaped(cleanMessage),
        ])
        let (emailData, emailResponse) = try await URLSession.shared.data(for: emailRequest)
        guard let emailHTTP = emailResponse as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(emailHTTP.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: emailData)) as? [String: Any]
            throw AuthError.api(payload?["error"] as? String ?? "Le message n’a pas pu être envoyé.")
        }

        return await archiveProfessionalPropertyContactRequest(
            listingID: cleanID,
            firstName: firstName,
            lastName: lastName,
            email: cleanEmail,
            phone: phone,
            message: cleanMessage,
            requestID: requestID
        )
    }

    func submitPrivatePropertyContactRequest(
        listingID: String,
        firstName: String,
        lastName: String,
        phone: String,
        message: String
    ) async throws {
        let cleanID = listingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil,
              firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              cleanMessage.count >= 5,
              member?.loginEmailVerified != false else {
            throw AuthError.api("Connectez-vous avec une adresse vérifiée et vérifiez vos coordonnées.")
        }
        let result = try await sendDashboardAction([
            "action": "contact_private_property_owner", "role": "particulier",
            "propertyId": cleanID, "firstName": firstName, "lastName": lastName,
            "phone": phone, "message": cleanMessage,
        ], fallback: "Impossible d’envoyer votre message au propriétaire.")
        guard result["sent"] as? Bool == true else {
            throw AuthError.api("L’envoi du message n’a pas été confirmé.")
        }
    }

    func archiveProfessionalPropertyContactRequest(
        listingID: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        message: String,
        requestID: String
    ) async -> Bool {
        let cleanID = listingID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil,
              cleanEmail.contains("@"), cleanMessage.count >= 5,
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        // Wix's existing public endpoint resolves the real professional owner,
        // writes the private propertycontactrequests record, and sends its push.
        let archiveURL = URL(string: "https://www.partenairefoyer.com/api/property-contact-requests")!
        var archiveRequest = URLRequest(url: archiveURL, timeoutInterval: 25)
        archiveRequest.httpMethod = "POST"
        archiveRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        archiveRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let archiveBody = try? JSONSerialization.data(withJSONObject: [
            "action": "create",
            "requestId": requestID,
            "propertyId": cleanID,
            "sourceCollection": "biensprofessionnels",
            "senderName": "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))",
            "senderEmail": cleanEmail,
            "senderPhone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": cleanMessage,
        ]) else { return false }
        archiveRequest.httpBody = archiveBody
        do {
            let (archiveData, archiveResponse) = try await URLSession.shared.data(for: archiveRequest)
            guard let archiveHTTP = archiveResponse as? HTTPURLResponse else { return false }
            if (200..<300).contains(archiveHTTP.statusCode) {
                let payload = (try? JSONSerialization.jsonObject(with: archiveData)) as? [String: Any]
                return payload?["success"] as? Bool == true
            }
            return false
        } catch {
            // The e-mail may already have been delivered; an archive failure
            // must not prompt the user to send it again.
            return false
        }
    }

    private func hasDemandMatch(postalCode: String, latitude: Double?, longitude: Double?, accessToken: String) async throws -> Bool {
        let targetPostal = postalCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let targetDepartment = departmentFromPostalCode(targetPostal)
        let fields = ["mainPostalCode", "postalCode", "secondaryPostalCodes", "maxRadiusKm", "latitude", "longitude"]
        for collection in ["professionnels"] {
            var offset = 0
            while true {
                let response = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: accessToken,
                    body: ["dataCollectionId": collection, "query": [
                        "paging": ["limit": 100, "offset": offset], "fields": fields
                    ]],
                    as: WixRawDirectoryResponse.self
                )
                let page = response.dataItems
                for item in page {
                    let data = item.data.mapValues(\.value)
                    let main = (importedString(data, ["mainPostalCode", "postalCode"]) ?? "").uppercased()
                    if !main.isEmpty && main == targetPostal { return true }
                    let secondaryValue = data["secondaryPostalCodes"]
                    let secondaryCodes: [String]
                    if let values = secondaryValue as? [String] {
                        secondaryCodes = values
                    } else if let values = secondaryValue as? [Any] {
                        secondaryCodes = values.compactMap { $0 as? String }
                    } else if let text = secondaryValue as? String {
                        if let jsonData = text.data(using: .utf8),
                           let values = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                            secondaryCodes = values
                        } else {
                            secondaryCodes = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }).map(String.init)
                        }
                    } else {
                        secondaryCodes = []
                    }
                    let normalizedSecondaryCodes = secondaryCodes
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                    if normalizedSecondaryCodes.contains(targetPostal) { return true }

                    if let latitude, let longitude,
                       let proLatitude = data["latitude"] as? Double,
                       let proLongitude = data["longitude"] as? Double {
                        let proLocation = CLLocation(latitude: proLatitude, longitude: proLongitude)
                        let demandLocation = CLLocation(latitude: latitude, longitude: longitude)
                        let radius = (data["maxRadiusKm"] as? Double) ?? 20
                        if radius > 0 && proLocation.distance(from: demandLocation) / 1000 <= radius { return true }
                    }

                    let professionalDepartment = departmentFromPostalCode(main)
                    if !professionalDepartment.isEmpty && professionalDepartment == targetDepartment { return true }
                }
                guard page.count == 100 else { break }
                offset += page.count
            }
        }
        return false
    }

    private func departmentFromPostalCode(_ postalCode: String) -> String {
        let value = postalCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("2A") || value.hasPrefix("2B") { return String(value.prefix(2)) }
        return String(value.prefix(2))
    }

    func coordinates(city: String, postalCode: String) async -> CLLocationCoordinate2D? {
        let communes = await loadPostalCommunes(postalCode: postalCode)
        guard !communes.isEmpty else { return nil }

        let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let selected = communes.first { commune in
            commune.nom.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")) == normalizedCity
        } ?? (communes.count == 1 ? communes[0] : nil)
        guard let coordinates = selected?.centre?.coordinates,
              coordinates.count >= 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func loadPostalCommunes(postalCode: String) async -> [PostalCommune] {
        let normalizedPostalCode = postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = postalCommunesCache[normalizedPostalCode] { return cached }
        guard normalizedPostalCode.count == 5,
              normalizedPostalCode.allSatisfy(\.isNumber),
              var components = URLComponents(string: "https://geo.api.gouv.fr/communes") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "codePostal", value: normalizedPostalCode),
            URLQueryItem(name: "fields", value: "nom,centre"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let communes = try? JSONDecoder().decode([PostalCommune].self, from: data) else { return [] }
        let usable = communes.filter { !$0.nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !usable.isEmpty { postalCommunesCache[normalizedPostalCode] = usable }
        return usable
    }

    func fetchPublicClassifiedAds(
        onPartialUpdate: @escaping @MainActor ([ClassifiedAd], String?) -> Void = { _, _ in }
    ) async throws -> (ads: [ClassifiedAd], warningMessage: String?) {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let fields = [
            "itemName", "itemDescription", "itemPrice", "category", "subcategory",
            "itemCondition", "adListingType", "attributesJSON", "slug", "city", "postalCode", "status", "itemImage", "isImported", "bumpedAt", "_createdDate",
            "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8",
            "photo9", "photo10", "photo11", "photo12", "photo13", "photo14",
            "photo15", "photo16", "photo17", "photo18", "photo19", "photo20"
        ]
        var offset = 0
        var wixAds: [ClassifiedAd] = []
        var warnings: [String] = []
        let pageSize = 100

        do {
            while true {
                let response = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: visitor.accessToken,
                    body: [
                        "dataCollectionId": "classifiedads-1",
                        "query": [
                            "filter": ["status": ["$in": ["published", "active"]]],
                            "paging": ["limit": pageSize, "offset": offset],
                            "fields": fields
                        ]
                    ],
                    as: WixPublicClassifiedAdsResponse.self
                )
                wixAds.append(contentsOf: response.dataItems.compactMap { $0.data.classifiedAd(id: $0.id) })
                guard response.dataItems.count == pageSize else { break }
                let nextOffset = offset + response.dataItems.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        } catch {
            warnings.append("Les petites annonces PartenaireFoyer n’ont pas pu être chargées.")
        }

        func ordered(_ values: [ClassifiedAd]) -> [ClassifiedAd] {
            var seen = Set<String>()
            let unique = values.filter { seen.insert($0.id).inserted }
            return unique.enumerated().sorted { left, right in
                let lhs = left.element.catalogOrderDate
                let rhs = right.element.catalogOrderDate
                if lhs == rhs { return left.offset < right.offset }
                return lhs > rhs
            }.map(\.element)
        }

        onPartialUpdate(ordered(wixAds), warnings.isEmpty ? nil : warnings.joined(separator: " "))
        var importedAds: [ClassifiedAd] = []
        do {
            let fetched = try await fetchImportedVehicleClassifiedAds { page in
                importedAds.append(contentsOf: page)
                onPartialUpdate(ordered(wixAds + importedAds), warnings.isEmpty ? nil : warnings.joined(separator: " "))
            }
            importedAds = fetched
        } catch {
            warnings.append("Les annonces de véhicules importées ne sont pas disponibles pour le moment.")
        }
        let final = ordered(wixAds + importedAds)
        let warning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
        onPartialUpdate(final, warning)
        return (final, warning)
    }

    func fetchPublicBuyerSearches() async throws -> [WixPublicBuyerSearch] {
        let visitor = try await requestToken(["clientId": clientID, "grantType": "anonymous"])
        let fields = [
            "searchName", "transactionType", "propertyTypes", "city", "postalCode", "radius",
            "minBudget", "maxBudget", "minSurface", "minLandSurface", "minRooms", "minBedrooms",
            "minBathrooms", "projectDescription", "isActive", "createdAt", "_createdDate"
        ]
        let pageSize = 100
        var offset = 0
        var searches: [WixPublicBuyerSearch] = []
        while true {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "particularbuyersearches",
                    "query": [
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixRawDirectoryResponse.self
            )
            searches.append(contentsOf: response.dataItems.compactMap { item in
                let data = item.data.mapValues(\.value)
                if let active = data["isActive"] as? Bool, !active { return nil }
                func string(_ key: String) -> String? {
                    guard let value = data[key], !(value is NSNull) else { return nil }
                    if let value = value as? String { return value }
                    return String(describing: value)
                }
                func number(_ key: String) -> Double? {
                    guard let value = data[key], !(value is NSNull) else { return nil }
                    if let value = value as? NSNumber { return value.doubleValue }
                    return Double(String(describing: value))
                }
                let types = (string("propertyTypes") ?? "").split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                func dateString(_ key: String) -> String? {
                    if let value = string(key) { return value }
                    guard let object = data[key] as? [String: Any] else { return nil }
                    return object["$date"] as? String
                }
                let createdAt = dateString("createdAt") ?? dateString("_createdDate")
                return WixPublicBuyerSearch(
                    id: item.id,
                    searchName: string("searchName"),
                    transactionType: string("transactionType"),
                    propertyTypes: types,
                    city: string("city"),
                    postalCode: string("postalCode"),
                    radius: number("radius"),
                    minBudget: number("minBudget"),
                    maxBudget: number("maxBudget"),
                    minSurface: number("minSurface"),
                    minLandSurface: number("minLandSurface"),
                    minRooms: number("minRooms"),
                    minBedrooms: number("minBedrooms"),
                    minBathrooms: number("minBathrooms"),
                    projectDescription: string("projectDescription"),
                    createdAt: createdAt
                )
            })
            guard response.dataItems.count == pageSize else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }
        return searches
    }

    private func fetchImportedVehicleClassifiedAds(onPage: @escaping @MainActor ([ClassifiedAd]) -> Void = { _ in }) async throws -> [ClassifiedAd] {
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-vehicle-listings-public")!
        let pageSize = 500
        var offset = 0
        var results: [ClassifiedAd] = []
        var seen = Set<String>()
        while true {
            var page: [ClassifiedAd] = []
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  payload["success"] as? Bool == true,
                  let items = payload["items"] as? [[String: Any]] else {
                throw URLError(.badServerResponse)
            }

            for item in items {
                guard let rawID = importedString(item, ["id"]),
                      rawID.range(of: "^[a-zA-Z0-9-]{1,200}$", options: .regularExpression) != nil,
                      let title = importedString(item, ["title"]),
                      let sourceValue = importedString(item, ["sourceUrl"]),
                      let source = URL(string: sourceValue),
                      ["https", "http"].contains(source.scheme?.lowercased() ?? ""),
                      source.user == nil, source.password == nil,
                      seen.insert(rawID).inserted else { continue }
                var attributes = item["attributes"] as? [String: Any] ?? [:]
                for key in ["brand", "model", "year", "mileage", "energy", "gearbox", "bodyType", "engineCapacity", "fiscalPower", "powerHp", "doors", "seats", "color", "externalReference", "partType", "partReference", "oemReference", "compatibleMake", "compatibleModel", "compatibleYearFrom", "compatibleYearTo", "engineCode", "dimensions"] {
                    if let value = item[key], !(value is NSNull), String(describing: value).isEmpty == false { attributes[key] = value }
                }
                var imageCandidates = item["images"] as? [Any] ?? []
                if let imageUrl = item["imageUrl"] { imageCandidates.insert(imageUrl, at: 0) }
                var imageURLs: [URL] = []
                for candidate in imageCandidates {
                    guard let value = candidate as? String,
                          let imageURL = URL(string: value),
                          ["https", "http"].contains(imageURL.scheme?.lowercased() ?? ""),
                          imageURL.user == nil, imageURL.password == nil,
                          !imageURLs.contains(imageURL) else { continue }
                    imageURLs.append(imageURL)
                }
                let noDescriptionConsent = attributes["noRepublishingConsent"] as? Bool == true
                let description = noDescriptionConsent
                    ? "Annonce externe. Prix et disponibilité à confirmer sur le site du vendeur."
                    : importedString(item, ["description"])
                let sourceKind = importedString(item, ["sourceKind"]) ?? ""
                let itemType = (importedString(item, ["itemType"]) ?? "").lowercased()
                let subcategory = sourceKind == "part" ? (itemType.contains("moto") ? "Pièces moto" : "Pièces auto")
                    : sourceKind == "accessory" ? "Autres accessoires auto / moto"
                    : itemType.range(of: "moto|motorcycle", options: .regularExpression) != nil ? "Motos"
                    : itemType.contains("scooter") ? "Scooters"
                    : itemType.range(of: "utilitaire|van|lcv", options: .regularExpression) != nil ? "Utilitaires"
                    : itemType.contains("quad") ? "Quads" : "Voitures"
                attributes["pfImportedVehicleListing"] = true
                attributes["importedProfessionalVehicle"] = true
                attributes["importedVehicleId"] = rawID
                attributes["sourceUrl"] = source.absoluteString
                attributes["externalProfessionalName"] = importedString(item, ["providerName"]) ?? "Vendeur externe"
                attributes["providerProfileId"] = importedString(item, ["providerProfileId"]) ?? ""
                attributes["providerSlug"] = importedString(item, ["providerSlug"]) ?? ""
                attributes["originalListingRequired"] = true
                let attributesData = try? JSONSerialization.data(withJSONObject: attributes, options: [.sortedKeys])
                let attributesJSON = attributesData.flatMap { String(data: $0, encoding: .utf8) }
                let city = importedString(item, ["city"])
                let postalCode = importedString(item, ["postalCode", "postal_code"])
                let price = (item["price"] as? NSNumber)?.doubleValue
                page.append(ClassifiedAd(
                    id: "imported-vehicle-\(rawID)",
                    title: title,
                    description: description,
                    price: price,
                    category: "Auto / Moto — accessoires",
                    subcategory: subcategory,
                    condition: nil,
                    city: city,
                    postalCode: postalCode,
                    images: imageURLs,
                    externalURL: source,
                    isImported: true,
                    importedAttributesJSON: attributesJSON,
                    importedProviderName: importedString(item, ["providerName"]) ?? "Vendeur externe",
                    listingType: "sell",
                    bumpedAt: importedString(item, ["bumpedAt"]),
                    createdAt: importedString(item, ["createdAt", "updatedAt", "lastUpdatedAt", "lastSeenAt"])
                ))
            }

            results.append(contentsOf: page)
            if !page.isEmpty { onPage(page) }
            guard let total = payload["total"] as? Int else { break }
            offset += items.count
            if offset >= total || items.isEmpty || offset >= 10000 { break }
            await Task.yield()
        }
        return results
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
            "previousPrice", "lastPriceDropDate", "_createdDate",
            "surface", "landSurface", "rooms", "bedrooms", "bathrooms", "propertyType", "transactionType", "mainImage", "isPublic", "status",
            "createdAt",
            "galleryImages", "photo1", "photo2", "photo3", "photo4", "photo5", "photo6",
            "photo7", "photo8", "photo9", "photo10", "photo11", "photo12", "photo13",
            "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20"
        ]

        while true {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "privateproperties",
                    "query": [
                        "filter": [
                            "isPublic": ["$eq": true],
                            "status": ["$in": ["active", "published"]]
                        ],
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicPropertiesResponse.self
            )
            properties.append(contentsOf: response.dataItems)
            guard response.dataItems.count == pageSize else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }

        return properties
            .filter {
                $0.data.isPublic == true &&
                    ["active", "published"].contains($0.data.status?.lowercased() ?? "")
            }
            .map { $0.data.listing(id: $0.id) }
    }

    func fetchPublicProfessionals(
        onPartialUpdate: @escaping @MainActor ([WixPublicProfessional], String?) -> Void = { _, _ in }
    ) async throws -> ProfessionalDirectoryResult {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let records = try await fetchVisibleProfessionalRecords(accessToken: visitor.accessToken)
        let registered = sortedRegisteredProfessionals(records.map { $0.data.professional(id: $0.id) })
        onPartialUpdate(registered, nil)

        var warnings: [String] = []
        var registeredGroups: [[WixPublicProfessional]] = [
            sortedRegisteredProfessionals(registered),
            [],
            [],
            []
        ]
        var visibleImported: [WixPublicProfessional] = []
        let publishPartialDirectory: () -> Void = {
            onPartialUpdate(registeredGroups.flatMap { $0 } + visibleImported, nil)
        }

        // Load Wix collections one at a time. Showing the main professional
        // directory first avoids launching several large paginated requests
        // together, which can stall or terminate the app on older devices.
        do {
            registeredGroups[1] = try await fetchPublicBrokers(accessToken: visitor.accessToken)
        } catch {
            warnings.append("l’annuaire des courtiers")
        }
        publishPartialDirectory()

        do {
            registeredGroups[2] = try await fetchRegisteredLocalProsProfiles(accessToken: visitor.accessToken)
        } catch {
            warnings.append("les fiches locales inscrites")
        }
        publishPartialDirectory()

        do {
            registeredGroups[3] = try await fetchRegisteredServiceProviders(accessToken: visitor.accessToken)
        } catch {
            warnings.append("les prestataires inscrits")
        }
        publishPartialDirectory()

        func appendImportedGroup(_ group: [WixPublicProfessional]) {
            let categories = Set(group.compactMap(\.importedCategory))
            let registered = registeredGroups.flatMap { $0 }
            let categoryRegistered = registered.filter {
                let category = $0.importedCategory ?? "immobilier"
                return categories.contains(category)
            }
            let registeredContacts = Set(categoryRegistered.flatMap { [$0.professionalEmail, $0.publicPhone] }
                .compactMap { $0 }.map(normalizedContactKey).filter { !$0.isEmpty })
            var seen = Set(categoryRegistered.map { normalizedProfessionalKey($0.resolvedName, $0.postalCode) })
            var existingIDs = Set(visibleImported.map(\.id))

            for professional in group {
                guard existingIDs.insert(professional.id).inserted else { continue }
                let contacts = [professional.dedupeEmail, professional.dedupePhone].compactMap { $0 }
                    .map(normalizedContactKey).filter { !$0.isEmpty }
                guard contacts.allSatisfy({ !registeredContacts.contains($0) }) else { continue }
                guard seen.insert(normalizedProfessionalKey(professional.resolvedName, professional.postalCode)).inserted else { continue }
                visibleImported.append(professional)
            }
            publishPartialDirectory()
        }

        // External imports start only after registered Wix profiles are visible,
        // and each feed is paged and published before the next one begins.
        do {
            try await fetchImportedLocalProfessionals(categories: ["courtier"]) { page in
                appendImportedGroup(page)
            }
        } catch {
            warnings.append("les courtiers importés")
        }
        do {
            try await fetchImportedLocalProfessionals(categories: ["prestataire"]) { page in
                appendImportedGroup(page)
            }
        } catch {
            warnings.append("les prestataires importés")
        }
        do {
            try await fetchImportedLocalProfessionals { page in
                appendImportedGroup(page)
            }
        } catch {
            warnings.append("les artisans et diagnostiqueurs importés")
        }
        do {
            try await fetchImportedRealEstateProfessionals { page in
                appendImportedGroup(page)
            }
        } catch {
            warnings.append("les professionnels immobiliers importés")
        }

        let professionals = registeredGroups.flatMap { $0 } + visibleImported
        let warning = warnings.isEmpty ? nil : "Annuaire partiellement chargé : " + warnings.joined(separator: ", ") + ". Réessayez pour actualiser les fiches manquantes."
        onPartialUpdate(professionals, warning)
        return ProfessionalDirectoryResult(professionals: professionals, warning: warning)
    }

    private func sortedRegisteredProfessionals(_ professionals: [WixPublicProfessional]) -> [WixPublicProfessional] {
        // The public site deduplicates registered profiles by email and keeps
        // the real, complete profile with the most public fields populated.
        var unique: [WixPublicProfessional] = []
        var indexByEmail: [String: Int] = [:]
        for professional in professionals {
            let email = professional.professionalEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard !email.isEmpty else {
                unique.append(professional)
                continue
            }
            guard let existingIndex = indexByEmail[email] else {
                indexByEmail[email] = unique.count
                unique.append(professional)
                continue
            }
            if profileQuality(professional) > profileQuality(unique[existingIndex]) {
                unique[existingIndex] = professional
            }
        }
        return unique.enumerated().sorted { left, right in
            let leftScore = left.element.activityScore ?? 0
            let rightScore = right.element.activityScore ?? 0
            if leftScore != rightScore { return leftScore > rightScore }
            let leftName = "\(left.element.firstName ?? "") \(left.element.lastName ?? "")"
            let rightName = "\(right.element.firstName ?? "") \(right.element.lastName ?? "")"
            let nameOrder = leftName.compare(
                rightName,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: Locale(identifier: "fr_FR")
            )
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.offset < right.offset
        }.map(\.element)
    }

    private func profileQuality(_ professional: WixPublicProfessional) -> Int {
        let isTest = professional.id.hasPrefix("test-pro-") || (professional.memberID?.hasPrefix("test-member-") == true)
        let fields = [professional.firstName, professional.lastName, professional.network,
                      professional.companyName, professional.city, professional.postalCode,
                      professional.publicPhone, professional.logo]
        return (isTest ? 0 : 1_000) +
            (professional.profileCompleted == true ? 100 : 0) +
            fields.filter { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count
    }

    private func fetchPublicBrokers(accessToken: String) async throws -> [WixPublicProfessional] {
        let pageSize = 100
        let collections: [(String, String)] = [("brokerprofiles", "broker"), ("pfcourtiers", "legacy")]
        var brokers: [WixPublicProfessional] = []
        for (collection, source) in collections {
            var offset = 0
            while true {
                let result = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: accessToken,
                    body: [
                        "dataCollectionId": collection,
                        "query": [
                            "filter": [:],
                            "paging": ["limit": pageSize, "offset": offset],
                            "fields": ["fullName", "professionalTitle", "profilePicture", "bio", "contactEmail", "phoneNumber", "city", "websiteUrl", "yearsOfExperience", "brokerTypes", "companyName", "photo", "email", "website", "slug"]
                        ]
                    ],
                    as: WixRawDirectoryResponse.self
                )
                brokers.append(contentsOf: result.dataItems.compactMap { item in
                    let data = item.data.mapValues(\.value)
                    let name = importedString(data, source == "broker" ? ["fullName"] : ["companyName"])
                    guard let name, !name.isEmpty else { return nil }
                    let title = importedString(data, source == "broker" ? ["professionalTitle"] : ["brokerTypes"])
                    let email = importedString(data, source == "broker" ? ["contactEmail"] : ["email"])
                    let picture = importedString(data, source == "broker" ? ["profilePicture"] : ["photo"])
                    let years = data["yearsOfExperience"].map { String(describing: $0) }
                    return WixPublicProfessional(
                        id: "broker-\(source)-\(item.id)",
                        companyName: name,
                        firstName: nil,
                        lastName: nil,
                        network: importedString(data, ["brokerTypes"]),
                        city: importedString(data, ["city"]),
                        postalCode: nil,
                        businessSector: title ?? "Courtier",
                        description: importedString(data, ["bio"]),
                        logo: picture,
                        website: importedString(data, source == "broker" ? ["websiteUrl"] : ["website"]),
                        miniSiteSlug: importedString(data, ["slug", "miniSiteSlug"]),
                        importedCategory: "courtier",
                        experienceYears: years,
                        professionalEmail: email,
                        publicPhone: importedString(data, ["phoneNumber"])
                    )
                })
                guard result.dataItems.count == pageSize else { break }
                let nextOffset = offset + result.dataItems.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        }
        return brokers
    }

    func fetchProfessionalFavorites() async throws -> [WixProfessionalFavorite] {
        guard let member, member.loginEmailVerified == true else {
            throw AuthError.api("Connectez-vous avec une adresse e-mail vérifiée pour voir vos professionnels favoris.")
        }
        let token = try await validAccessToken()
        let accountEmail = member.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var offset = 0
        var favorites: [WixProfessionalFavorite] = []
        while true {
            let result = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: token,
                body: [
                    "dataCollectionId": "professionalfavorites",
                    "query": [
                        "filter": ["accountId": ["$eq": accountEmail]],
                        "paging": ["limit": 100, "offset": offset],
                        "fields": ["accountId", "professionalId", "professionalType", "createdAt", "notes"]
                    ]
                ],
                as: WixRawDirectoryResponse.self
            )
            favorites.append(contentsOf: result.dataItems.compactMap { item in
                let data = item.data.mapValues(\.value)
                guard importedString(data, ["accountId"]) == accountEmail,
                      let professionalID = importedString(data, ["professionalId"]),
                      let type = importedString(data, ["professionalType"]) else { return nil }
                return WixProfessionalFavorite(id: item.id, professionalID: professionalID, professionalType: type)
            })
            guard result.dataItems.count == 100 else { break }
            let nextOffset = offset + result.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }
        return favorites
    }

    func isProfessionalFavorite(_ professionalID: String) async throws -> Bool {
        guard let member, member.loginEmailVerified == true else { return false }
        let cleanID = professionalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return false }
        let token = try await validAccessToken()
        let email = member.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await post(
            "https://www.wixapis.com/wix-data/v2/items/query",
            bearer: token,
            body: [
                "dataCollectionId": "professionalfavorites",
                "query": [
                    "filter": ["accountId": ["$eq": email], "professionalId": ["$eq": cleanID]],
                    "paging": ["limit": 2],
                    "fields": ["accountId", "professionalId"]
                ]
            ],
            as: WixRawDirectoryResponse.self
        )
        return result.dataItems.contains { item in
            let data = item.data.mapValues(\.value)
            return importedString(data, ["accountId"]) == email &&
                importedString(data, ["professionalId"]) == cleanID
        }
    }

    func toggleProfessionalFavorite(_ professionalID: String, professionalType: String) async throws -> Bool {
        guard let member, member.loginEmailVerified == true else {
            throw AuthError.api("Connectez-vous avec une adresse e-mail vérifiée pour gérer vos favoris.")
        }
        let cleanID = professionalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID.range(of: #"^[A-Za-z0-9_-]{1,200}$"#, options: .regularExpression) != nil,
              ["artisan", "diagnostiqueur", "courtier", "agent", "serviceprovider"].contains(professionalType) else {
            throw AuthError.api("Cette fiche professionnelle ne peut pas être enregistrée en favori.")
        }
        let token = try await validAccessToken()
        let email = member.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryResult = try await post(
            "https://www.wixapis.com/wix-data/v2/items/query",
            bearer: token,
            body: [
                "dataCollectionId": "professionalfavorites",
                "query": [
                    "filter": ["accountId": ["$eq": email], "professionalId": ["$eq": cleanID]],
                    "paging": ["limit": 2],
                    "fields": ["accountId", "professionalId"]
                ]
            ],
            as: WixRawDirectoryResponse.self
        )
        if let existing = queryResult.dataItems.first(where: { item in
            let data = item.data.mapValues(\.value)
            return importedString(data, ["accountId"]) == email &&
                importedString(data, ["professionalId"]) == cleanID
        }) {
            var components = URLComponents(string: "https://www.wixapis.com/wix-data/v2/items/\(existing.id)")!
            components.queryItems = [URLQueryItem(name: "dataCollectionId", value: "professionalfavorites")]
            var request = URLRequest(url: components.url!, timeoutInterval: 30)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let _: WixDataItemWriteResponse = try await decode(request)
            return false
        }
        let response = try await post(
            "https://www.wixapis.com/wix-data/v2/items",
            bearer: token,
            body: [
                "dataCollectionId": "professionalfavorites",
                "dataItem": [
                    "id": UUID().uuidString,
                    "data": [
                        "accountId": email,
                        "professionalId": cleanID,
                        "professionalType": professionalType,
                        "createdAt": ISO8601DateFormatter().string(from: Date()),
                        "notes": ""
                    ]
                ]
            ],
            as: WixDataItemWriteResponse.self
        )
        guard response.dataItem?.id != nil else { throw AuthError.api("Wix n’a pas confirmé l’enregistrement du favori.") }
        return true
    }

    func fetchPublicSeasonalAccommodations() async throws -> [WixSeasonalAccommodation] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let photoFields = (1...30).map { "photo\($0)" } + ["galleryImage2", "galleryImage3", "galleryImage4", "galleryImage5"]
        let fields = [
            "itemName", "itemPrice", "itemImage", "itemDescription", "slug", "accommodationType",
            "city", "postalCode", "department", "maxGuests", "numberOfBedrooms", "minimumStay",
            "petsAllowed", "amenities", "latitude", "longitude"
        ] + photoFields
        var offset = 0
        var accommodations: [WixSeasonalAccommodation] = []
        while true {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "seasonalaccommodations",
                    "query": [
                        "paging": ["limit": 100, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixRawDirectoryResponse.self
            )
            accommodations.append(contentsOf: response.dataItems.compactMap { item in
                let data = item.data.mapValues(\.value)
                guard let name = importedString(data, ["itemName"]), !name.isEmpty else { return nil }
                let photos = (["itemImage"] + photoFields).compactMap { importedString(data, [$0]) }
                return WixSeasonalAccommodation(
                    id: item.id,
                    slug: importedString(data, ["slug"]),
                    name: name,
                    accommodationType: importedString(data, ["accommodationType"]),
                    description: importedString(data, ["itemDescription"]),
                    city: importedString(data, ["city"]),
                    postalCode: importedString(data, ["postalCode"]),
                    department: importedString(data, ["department"]),
                    guestCapacity: (data["maxGuests"] as? NSNumber)?.intValue,
                    bedroomCount: (data["numberOfBedrooms"] as? NSNumber)?.intValue,
                    minimumStay: (data["minimumStay"] as? NSNumber)?.intValue,
                    nightlyPrice: (data["itemPrice"] as? NSNumber)?.doubleValue,
                    petsAllowed: data["petsAllowed"] as? Bool ?? false,
                    amenities: importedString(data, ["amenities"]),
                    photos: photos,
                    latitude: (data["latitude"] as? NSNumber)?.doubleValue,
                    longitude: (data["longitude"] as? NSNumber)?.doubleValue
                )
            })
            guard response.dataItems.count == 100 else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }
        return accommodations
    }

    func fetchPublicSeasonalCalendarEntries() async throws -> [WixSeasonalCalendarEntry] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        var offset = 0
        var entries: [WixSeasonalCalendarEntry] = []
        while true {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "seasonalcalendars",
                    "query": [
                        "paging": ["limit": 100, "offset": offset],
                        "fields": ["linkedEntityId", "calendarDate", "availabilityStatus"]
                    ]
                ],
                as: WixRawDirectoryResponse.self
            )
            entries.append(contentsOf: response.dataItems.compactMap { item in
                let data = item.data.mapValues(\.value)
                guard let accommodationID = importedString(data, ["linkedEntityId"]),
                      let date = importedString(data, ["calendarDate"]),
                      let status = importedString(data, ["availabilityStatus"]) else { return nil }
                return WixSeasonalCalendarEntry(
                    id: item.id,
                    accommodationID: accommodationID,
                    calendarDate: date,
                    availabilityStatus: status
                )
            })
            guard response.dataItems.count == 100 else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }
        return entries
    }

    func fetchPublicProfessionalListings() async throws -> [Listing] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let professionals = try await fetchVisibleProfessionalRecords(accessToken: visitor.accessToken)
        let ownerIDs = professionals.flatMap { professional in
            [professional.id, professional.data.memberId]
        }
        return try await fetchPublicProfessionalListings(ownerIDs: ownerIDs, accessToken: visitor.accessToken)
    }

    /// Fetch one profile's homes directly instead of loading and filtering the
    /// entire public property catalogue when a user opens a professional page.
    func fetchPublicProfessionalListings(for professional: WixPublicProfessional) async throws -> [Listing] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let ownerIDs = [professional.cmsProfileID, professional.memberID, professional.id]
        return try await fetchPublicProfessionalListings(ownerIDs: ownerIDs, accessToken: visitor.accessToken)
    }

    private func fetchPublicProfessionalListings(ownerIDs: [String?], accessToken: String) async throws -> [Listing] {
        let professionalIDs = Array(Set(ownerIDs
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
        guard !professionalIDs.isEmpty else { return [] }

        let pageSize = 100
        var listings: [Listing] = []
        let fields = [
            "professionalId", "wixMemberId", "title", "description", "city", "postalCode", "price", "surface", "surfaceHouse",
            "surfaceLand", "landSurface", "rooms", "bedrooms", "bathrooms", "propertyType",
            "transactionType", "mainImageUrl", "galleryImages", "photo1", "photo2", "photo3",
            "photo4", "photo5", "createdAt", "_createdDate", "updatedAt", "previousPrice",
            "lastPriceDropDate", "commercialStatus", "slug", "status"
        ]

        // Older homes can reference the CMS profile while newer ones can
        // reference the Wix member. Query both identifiers and keep published
        // homes only.
        for start in stride(from: 0, to: professionalIDs.count, by: 100) {
            let end = min(start + 100, professionalIDs.count)
            let batch = Array(professionalIDs[start..<end])
            var offset = 0
            while true {
                let response = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: accessToken,
                    body: [
                        "dataCollectionId": "biensprofessionnels",
                        "query": [
                            "filter": [
                                "$or": [
                                    ["wixMemberId": ["$in": batch]],
                                    ["professionalId": ["$in": batch]]
                                ],
                                "status": ["$in": ["active", "published"]]
                            ],
                            "paging": ["limit": pageSize, "offset": offset],
                            "fields": fields
                        ]
                    ],
                    as: WixPublicProfessionalPropertiesResponse.self
                )
                let activeItems = response.dataItems.filter {
                    ["active", "published"].contains($0.data.status?.lowercased() ?? "")
                }
                listings.append(contentsOf: activeItems.map { $0.data.listing(id: $0.id) })
                guard response.dataItems.count == pageSize else { break }
                let nextOffset = offset + response.dataItems.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        }
        return listings
    }

    private func fetchRegisteredServiceProviders(accessToken: String) async throws -> [WixPublicProfessional] {
        let collections = ["serviceproviders", "serviceproviders-1"]
        let fields = [
            "accountId", "businessName", "companyName", "name", "category", "subcategory",
            "description", "services", "city", "postalCode", "phone", "email", "website",
            "photo", "photoUrl", "photoUrls", "logo", "companyLogo", "slug", "status", "featured"
        ]
        var results: [WixPublicProfessional] = []
        var seenAccounts = Set<String>()
        var seenIDs = Set<String>()

        for collection in collections {
            var offset = 0
            let pageSize = 100
            while true {
                let response = try await post(
                    "https://www.wixapis.com/wix-data/v2/items/query",
                    bearer: accessToken,
                    body: [
                        "dataCollectionId": collection,
                        "query": [
                            "paging": ["limit": pageSize, "offset": offset],
                            "fields": fields
                        ]
                    ],
                    as: WixRawDirectoryResponse.self
                )
                results.append(contentsOf: response.dataItems.compactMap { item in
                    let data = item.data.mapValues(\.value)
                    guard importedString(data, ["status"])?.lowercased() == "active" else { return nil }
                    guard !seenIDs.contains(item.id) else { return nil }
                    let accountKey = importedString(data, ["accountId"])?.lowercased()
                    if let accountKey, seenAccounts.contains(accountKey) { return nil }
                    let name = importedString(data, ["businessName", "companyName", "name"]) ?? "Prestataire référencé"
                    seenIDs.insert(item.id)
                    if let accountKey { seenAccounts.insert(accountKey) }
                    let services = directoryText(data, "services")
                    let category = importedString(data, ["category", "subcategory"]) ?? "Service du quotidien"
                    let photo = directoryPhoto(data, ["photoUrls", "photo", "photoUrl", "companyLogo", "logo"])
                    return WixPublicProfessional(
                        id: "serviceprovider-\(collection)-\(item.id)",
                        cmsProfileID: item.id,
                        companyName: name,
                        firstName: importedString(data, ["contactName"]),
                        lastName: nil,
                        network: category,
                        city: importedString(data, ["city"]),
                        postalCode: importedString(data, ["postalCode", "postal_code"]),
                        businessSector: services ?? category,
                        description: importedString(data, ["description"]),
                        logo: photo,
                        website: importedString(data, ["website"]),
                        miniSiteSlug: importedString(data, ["slug", "miniSiteSlug"]),
                        importedCategory: "prestataire",
                        professionalEmail: importedString(data, ["email"]),
                        publicPhone: importedString(data, ["phone", "phoneNumber"]),
                        isServiceProviderProfile: true,
                        isDirectoryFeatured: data["featured"] as? Bool == true
                    )
                })
                guard response.dataItems.count == pageSize else { break }
                let nextOffset = offset + response.dataItems.count
                guard nextOffset > offset else { break }
                offset = nextOffset
            }
        }
        let freeAccessEnds = ISO8601DateFormatter().date(from: "2027-01-01T00:00:00+01:00")!
        guard Date() >= freeAccessEnds else { return results }
        let access = try await fetchAllowedPublicProviderAccess()
        if access.freeAccess { return results }
        return results.filter { professional in
            guard let profileID = professional.cmsProfileID else { return false }
            return access.allowedProfileIDs.contains(profileID)
        }
    }

    private func fetchAllowedPublicProviderAccess() async throws -> (freeAccess: Bool, allowedProfileIDs: Set<String>) {
        var components = URLComponents(string: "https://www.partenairefoyer.com/api/public-professional-access")!
        components.queryItems = [URLQueryItem(name: "type", value: "service_provider")]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(PublicProfessionalAccessResponse.self, from: data)
        let allowedIDs = Set((payload.allowedProfileIds ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return (payload.freeAccess == true, allowedIDs)
    }

    private func directoryPhoto(_ data: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = data[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let values = data[key] as? [String], let first = values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func directoryText(_ data: [String: Any], _ key: String) -> String? {
        if let value = data[key] as? String {
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        if let values = data[key] as? [String] {
            let parts = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        return nil
    }

    private func localProfessionalCategory(_ data: [String: Any]) -> (directoryCategory: String, label: String)? {
        var categoryRecords: [[String: Any]] = []
        if let records = data["categories"] as? [[String: Any]] {
            categoryRecords = records
        } else if let encoded = data["categories"] as? String,
                  let encodedData = encoded.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: encodedData) as? [[String: Any]] {
            categoryRecords = decoded
        }
        let mainCategory = categoryRecords.lazy.compactMap { self.importedString($0, ["mainCategory", "category"]) }.first
        let rawCategory = mainCategory ?? importedString(data, ["professionalType", "category"]) ?? "Professionnel"
        let normalized = rawCategory.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let directoryCategory = normalized.contains("diagnost") ? "diagnostiqueur" : "artisan"
        return (directoryCategory, rawCategory)
    }

    private func fetchImportedLocalProfessionals(
        categories: [String] = ["artisan", "diagnostiqueur"],
        onPage: @escaping @MainActor ([WixPublicProfessional]) -> Void = { _ in }
    ) async throws -> [WixPublicProfessional] {
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-local-pros-public")!
        var results: [WixPublicProfessional] = []
        let pageSize = 50

        for category in categories {
            var offset = 0
            while true {
                var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "category", value: category),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset))
                ]
                var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = payload["items"] as? [[String: Any]] else {
                    throw URLError(.badServerResponse)
                }

                let page: [WixPublicProfessional] = items.compactMap { (item: [String: Any]) -> WixPublicProfessional? in
                    guard (item["claimed"] as? Bool) != true,
                          let rawID = importedString(item, ["id", "_id"]), !rawID.isEmpty else { return nil }
                    let firstName = importedString(item, ["first_name", "firstName"])
                    let lastName = importedString(item, ["last_name", "lastName"])
                    let company = importedString(item, ["company_name", "companyName", "display_name", "displayName"])
                    let name = company ?? [firstName, lastName].compactMap { $0 }.joined(separator: " ")
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let activity = importedString(item, ["activity_label", "activityLabel", "subcategory", "category"])
                    return WixPublicProfessional(
                        id: "imported-local-\(rawID)",
                        companyName: name,
                        firstName: firstName,
                        lastName: lastName,
                        network: "Professionnel importé",
                        city: importedString(item, ["city"]),
                        postalCode: importedString(item, ["postal_code", "postalCode"]),
                        businessSector: activity,
                        description: activity,
                        logo: importedString(item, ["photo_url", "photoUrl"]),
                        website: importedString(item, ["website"]),
                        importedID: rawID,
                        importedCategory: category,
                        dedupeEmail: importedString(item, ["email"]),
                        dedupePhone: importedString(item, ["phone"])
                    )
                }
                results.append(contentsOf: page)
                if !page.isEmpty { await onPage(page) }

                guard items.count == pageSize else { break }
                let nextOffset = offset + items.count
                guard nextOffset > offset else { break }
                offset = nextOffset
                if let total = payload["total"] as? Int, offset >= total { break }
                await Task.yield()
            }
        }
        return results
    }

    private func fetchImportedRealEstateProfessionals(
        onPage: @escaping @MainActor ([WixPublicProfessional]) -> Void = { _ in }
    ) async throws -> [WixPublicProfessional] {
        let endpoint = URL(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-real-estate-pros-public")!
        var offset = 0
        let pageSize = 50
        var results: [WixPublicProfessional] = []
        while true {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  payload["success"] as? Bool != false,
                  let items = payload["items"] as? [[String: Any]],
                  let total = payload["total"] as? Int else { throw URLError(.badServerResponse) }
            let page: [WixPublicProfessional] = items.compactMap { (item: [String: Any]) -> WixPublicProfessional? in
                guard (item["claimed"] as? Bool) != true,
                      let id = importedString(item, ["id"]), !id.isEmpty else { return nil }
                let first = importedString(item, ["firstName", "first_name"])
                let last = importedString(item, ["lastName", "last_name"])
                let name = importedString(item, ["displayName", "display_name", "companyName", "company_name"])
                    ?? [first, last].compactMap { $0 }.joined(separator: " ")
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let network = importedString(item, ["networkName", "network_name", "professionalType", "professional_type"])
                return WixPublicProfessional(
                    id: "imported-\(id)", companyName: importedString(item, ["companyName", "company_name"]) ?? name,
                    firstName: first, lastName: last, network: network ?? "Professionnel immobilier importé",
                    city: importedString(item, ["city"]),
                    postalCode: importedString(item, ["postalCode", "postal_code"]),
                    businessSector: network ?? "Immobilier", description: nil,
                    logo: importedString(item, ["photoUrl", "photo_url"]),
                    website: importedString(item, ["website"]), importedID: id, importedCategory: "immobilier",
                    dedupeEmail: importedString(item, ["email"]), dedupePhone: importedString(item, ["phone"])
                )
            }
            results.append(contentsOf: page)
            if !page.isEmpty { await onPage(page) }
            guard !items.isEmpty else { break }
            let nextOffset = offset + items.count
            guard nextOffset > offset else { break }
            offset = nextOffset
            if offset >= total || items.count < pageSize { break }
            await Task.yield()
        }
        return results
    }

    private func importedString(_ item: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func normalizedProfessionalKey(_ name: String, _ postalCode: String?) -> String {
        let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
        let normalizedPostalCode = (postalCode ?? "").filter { $0.isNumber }
        return "\(normalizedName)|\(normalizedPostalCode)"
    }

    private func normalizedContactKey(_ value: String) -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if email.contains("@") { return "email:\(email)" }
        let phone = value.filter(\.isNumber)
        return phone.count >= 10 ? "phone:\(phone.hasPrefix("33") ? "0" + String(phone.dropFirst(2)) : phone)" : ""
    }

    private func fetchRegisteredLocalProsProfiles(accessToken: String) async throws -> [WixPublicProfessional] {
        let endpoint = "https://www.wixapis.com/wix-data/v2/items/query"
        let fields = ["companyName", "contactName", "email", "phoneNumber", "city", "postalCode", "category", "categories", "description", "photo", "logo", "website", "slug", "professionalType", "isRGE", "isActive", "isVisiblePublicly", "hasActiveSubscription", "subscriptionStatus"]
        var offset = 0
        var results: [WixPublicProfessional] = []
        let pageSize = 100
        while true {
            let response = try await post(
                endpoint,
                bearer: accessToken,
                body: ["dataCollectionId": "prosprofiles", "query": [
                    "filter": ["isActive": ["$eq": true], "isVisiblePublicly": ["$eq": true]],
                    "paging": ["limit": pageSize, "offset": offset], "fields": fields
                ]],
                as: WixRawDirectoryResponse.self
            )
            results.append(contentsOf: response.dataItems.compactMap { item in
                let data = item.data.mapValues(\.value)
                guard data["isActive"] as? Bool == true,
                      data["isVisiblePublicly"] as? Bool == true,
                      let company = importedString(data, ["companyName"]), !company.isEmpty,
                      let contactName = importedString(data, ["contactName"]), !contactName.isEmpty,
                      let email = importedString(data, ["email"]), !email.isEmpty,
                      let phone = importedString(data, ["phoneNumber"]), !phone.isEmpty,
                      hasPublicLocalProfessionalAccess(data) else { return nil }
                let category = localProfessionalCategory(data) ?? (directoryCategory: "artisan", label: "Artisan")
                return WixPublicProfessional(
                    id: "prosprofile-\(item.id)", cmsProfileID: item.id, companyName: company, firstName: contactName,
                    lastName: nil, network: category.label, city: importedString(data, ["city"]),
                    postalCode: importedString(data, ["postalCode"]), businessSector: category.label,
                    description: importedString(data, ["description"]),
                    logo: importedString(data, ["logo", "photo"]), website: importedString(data, ["website"]),
                    miniSiteSlug: importedString(data, ["slug", "miniSiteSlug"]),
                    importedCategory: category.directoryCategory,
                    professionalEmail: email, publicPhone: phone, isLocalProsProfile: true
                )
            })
            guard response.dataItems.count == pageSize else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }
        return results
    }

    private func hasPublicLocalProfessionalAccess(_ data: [String: Any], now: Date = Date()) -> Bool {
        let freeAccessEnds = ISO8601DateFormatter().date(from: "2026-12-31T23:59:59+01:00")!
        if now < freeAccessEnds { return true }
        let status = importedString(data, ["subscriptionStatus"])?.lowercased()
        return data["hasActiveSubscription"] as? Bool == true || status == "active" || status == "trialing"
    }

    private func fetchVisibleProfessionalRecords(accessToken: String) async throws -> [WixPublicProfessionalItem] {
        let pageSize = 100
        var offset = 0
        var records: [WixPublicProfessionalItem] = []
        let fields = [
            "companyName", "firstName", "lastName", "network", "city", "postalCode",
            "businessSector", "description", "photo", "website", "slug", "email", "phone", "memberId",
            "isActive", "isVisibleInDirectory", "activityScore", "profileCompleted"
        ]

        while true {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: accessToken,
                body: [
                    "dataCollectionId": "professionnels",
                    "query": [
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicProfessionalsResponse.self
            )
            records.append(contentsOf: response.dataItems.filter {
                // Match ProfessionnelsPage.tsx: only an explicit false hides a
                // profile; old published records may not have either flag.
                $0.data.isVisibleInDirectory?.value != false &&
                    !($0.data.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
                    !($0.data.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
                    (!($0.data.network?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
                     !($0.data.companyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)) &&
                    !($0.data.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            })
            guard response.dataItems.count == pageSize else { break }
            let nextOffset = offset + response.dataItems.count
            guard nextOffset > offset else { break }
            offset = nextOffset
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

    private func userFacingAuthError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("associated domains") || lowercased.contains("webcredentials") {
            return "Wix a accepté la connexion, mais le rappel sécurisé vers l’app n’est pas encore associé au domaine. Ouvrez la connexion complète du site depuis cet écran pour accéder à votre compte sans changer de mot de passe."
        }
        return message
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

    private func deleteProfessionalPortalSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: professionalPortalKeychainService,
                                    kSecAttrAccount as String: "professional-portal-session"]
        SecItemDelete(query as CFDictionary)
    }
}

private struct WixInsertDataItemResponse: Decodable {
    let dataItem: WixInsertedDataItem?
}

private struct WixInsertedDataItem: Decodable {
    let id: String?
}
