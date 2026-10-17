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

    func signOut() {
        resetDashboard()
        deleteStoredSession()
        member = nil
        errorMessage = nil
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
            var components = URLComponents(string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/ios-native-dashboard")!
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
            "surface", "rooms", "bedrooms", "propertyType", "transactionType", "mainImage",
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

        return properties.map(\.listing)
    }

    func fetchPublicProfessionals() async throws -> [WixPublicProfessional] {
        let visitor = try await requestToken([
            "clientId": clientID,
            "grantType": "anonymous"
        ])
        let pageSize = 100
        var offset = 0
        var profiles: [WixPublicProfessional] = []
        let fields = [
            "companyName", "city", "postalCode", "professionalType",
            "category", "description", "logo", "photo", "isVisiblePublicly", "isActive"
        ]

        // Only profiles that Wix explicitly marks public and active are eligible.
        for _ in 0..<10 {
            let response = try await post(
                "https://www.wixapis.com/wix-data/v2/items/query",
                bearer: visitor.accessToken,
                body: [
                    "dataCollectionId": "prosprofiles",
                    "query": [
                        "filter": [
                            "isVisiblePublicly": ["$eq": true],
                            "isActive": ["$eq": true]
                        ],
                        "paging": ["limit": pageSize, "offset": offset],
                        "fields": fields
                    ]
                ],
                as: WixPublicProfessionalsResponse.self
            )
            let visible = response.dataItems.filter {
                $0.data.isVisiblePublicly == true && $0.data.isActive == true
            }
            profiles.append(contentsOf: visible.map { $0.data.professional(id: $0.id) })
            guard response.dataItems.count == pageSize else { break }
            offset += pageSize
        }
        return profiles
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
