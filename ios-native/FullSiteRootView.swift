import SwiftUI
import WebKit
import Combine
import UIKit

/// Les parcours fonctionnels chargent les pages publiées du site Wix PartenaireFoyer.
/// Les comptes, annonces, favoris et tableaux de bord utilisent le CMS et les sessions Wix.
enum PortalSection: String, CaseIterable, Identifiable {
    case home, listings, deposit, favorites, account
    case classifieds, professionals, proLogin, matching, estimate, becomeAgent
    case privateDashboard, privateSignup, privateLegal, privateSalesTerms
    case proDashboard, proProperties, proBuyers, proRequests, proMatchings, proMessages, proProfile, proSignup, proLegal, proSalesTerms
    case brokerLogin, brokerSignup, brokerDashboard, brokerMessages, brokerLegal
    case artisanLogin, artisanSignup, artisanDashboard, artisanMessages, artisanLegal
    case providerLogin, providerSignup, providerDashboard, providerProfile, providerPhotos, providerLegal
    case seasonalListings, hostLogin, hostSignup, hostDashboard, hostCalendar, hostBookings
    case terms, salesTerms, privacy, legalNotices
    case brokerSalesTerms, artisanSalesTerms, providerSalesTerms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .listings: return "Annonces"
        case .deposit: return "Déposer"
        case .favorites: return "Favoris"
        case .account: return "Compte"
        case .classifieds: return "Petites annonces"
        case .professionals: return "Professionnels"
        case .proLogin: return "Espace professionnel"
        case .matching: return "Matching"
        case .estimate: return "Estimation"
        case .becomeAgent: return "Devenir mandataire"
        case .privateDashboard: return "Espace particulier"
        case .privateSignup: return "Créer un compte particulier"
        case .privateLegal: return "Conditions particuliers"
        case .privateSalesTerms: return "CGV particuliers"
        case .proDashboard: return "Tableau de bord professionnel"
        case .proProperties: return "Mes biens professionnels"
        case .proBuyers: return "Acquéreurs professionnels"
        case .proRequests: return "Demandes professionnelles"
        case .proMatchings: return "Matchings professionnels"
        case .proMessages: return "Messages professionnels"
        case .proProfile: return "Profil professionnel"
        case .proSignup: return "Inscription professionnelle"
        case .proLegal: return "Conditions professionnels"
        case .proSalesTerms: return "CGV professionnels"
        case .brokerLogin: return "Connexion courtier"
        case .brokerSignup: return "Inscription courtier"
        case .brokerDashboard: return "Espace courtier"
        case .brokerMessages: return "Messages courtier"
        case .brokerLegal: return "Conditions courtier"
        case .artisanLogin: return "Connexion artisan / diagnostiqueur"
        case .artisanSignup: return "Inscription artisan / diagnostiqueur"
        case .artisanDashboard: return "Espace artisan / diagnostiqueur"
        case .artisanMessages: return "Messages artisan"
        case .artisanLegal: return "Conditions artisan"
        case .providerLogin: return "Connexion prestataire"
        case .providerSignup: return "Inscription prestataire"
        case .providerDashboard: return "Espace prestataire"
        case .providerProfile: return "Fiche prestataire"
        case .providerPhotos: return "Photos prestataire"
        case .providerLegal: return "Conditions prestataire"
        case .seasonalListings: return "Locations saisonnières"
        case .hostLogin: return "Connexion hébergeur"
        case .hostSignup: return "Inscription hébergeur"
        case .hostDashboard: return "Espace hébergeur"
        case .hostCalendar: return "Calendrier hébergeur"
        case .hostBookings: return "Demandes de réservation"
        case .terms: return "Conditions générales d’utilisation"
        case .salesTerms: return "Conditions générales de vente"
        case .privacy: return "Confidentialité"
        case .legalNotices: return "Mentions légales"
        case .brokerSalesTerms: return "CGV courtier"
        case .artisanSalesTerms: return "CGV artisan"
        case .providerSalesTerms: return "CGV prestataire"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .listings: return "magnifyingglass"
        case .deposit: return "plus.circle.fill"
        case .favorites: return "heart"
        case .account: return "person.crop.circle"
        case .classifieds: return "shippingbox"
        case .professionals: return "person.2"
        case .proLogin: return "building.2"
        case .matching: return "arrow.left.arrow.right"
        case .estimate: return "chart.bar.xaxis"
        case .becomeAgent: return "person.badge.plus"
        case .privateDashboard, .privateSignup: return "person.crop.circle"
        case .privateLegal, .privateSalesTerms, .proLegal, .proSalesTerms, .brokerLegal, .artisanLegal, .providerLegal, .terms, .salesTerms, .privacy, .legalNotices, .brokerSalesTerms, .artisanSalesTerms, .providerSalesTerms: return "doc.text"
        case .proDashboard, .proProperties, .proBuyers, .proRequests, .proMatchings, .proMessages, .proProfile, .proSignup: return "building.2"
        case .brokerLogin, .brokerSignup, .brokerDashboard, .brokerMessages: return "briefcase"
        case .artisanLogin, .artisanSignup, .artisanDashboard, .artisanMessages: return "wrench.and.screwdriver"
        case .providerLogin, .providerSignup, .providerDashboard, .providerProfile, .providerPhotos: return "person.2"
        case .seasonalListings, .hostLogin, .hostSignup, .hostDashboard, .hostCalendar, .hostBookings: return "sun.horizon"
        }
    }

    /// Routes publiques vérifiées directement sur PartenaireFoyer.
    /// Les parcours de compte restent opérés par le service Wix existant.
    var landingURL: URL {
        let path: String
        switch self {
        case .home: path = "/"
        case .listings: path = "/annonces"
        case .deposit: path = "/deposer-mon-bien"
        case .favorites: path = "/vendeur-favoris"
        case .account: path = "/vendeur-login"
        case .classifieds: path = "/petites-annonces"
        case .professionals: path = "/professionnels"
        case .proLogin: path = "/pro-app-login"
        case .matching: path = "/matching-immobilier"
        case .estimate: path = "/estimation-bien"
        case .becomeAgent: path = "/devenir-mandataire-immobilier"
        case .privateDashboard: path = "/vendeur-dashboard"
        case .privateSignup: path = "/vendeur-signup"
        case .privateLegal: path = "/cgu-particuliers"
        case .privateSalesTerms: path = "/cgv-particuliers"
        case .proDashboard: path = "/pro/dashboard"
        case .proProperties: path = "/pro/biens"
        case .proBuyers: path = "/pro/acquereurs"
        case .proRequests: path = "/pro/demandes"
        case .proMatchings: path = "/pro/mes-matchings"
        case .proMessages: path = "/pro/messages"
        case .proProfile: path = "/pro/profil"
        case .proSignup: path = "/inscription-pro"
        case .proLegal: path = "/pro-cgu"
        case .proSalesTerms: path = "/pro-cgv"
        case .brokerLogin: path = "/broker-login"
        case .brokerSignup: path = "/broker-signup"
        case .brokerDashboard: path = "/broker-dashboard"
        case .brokerMessages: path = "/broker-messages"
        case .brokerLegal: path = "/broker-cgu"
        case .artisanLogin: path = "/artisan-login"
        case .artisanSignup: path = "/artisan-signup"
        case .artisanDashboard: path = "/artisan-dashboard"
        case .artisanMessages: path = "/artisan-messages"
        case .artisanLegal: path = "/artisan-cgu"
        case .providerLogin: path = "/connexion-prestataire"
        case .providerSignup: path = "/inscription-prestataire"
        case .providerDashboard: path = "/espace-prestataire"
        case .providerProfile: path = "/espace-prestataire/creer-fiche"
        case .providerPhotos: path = "/espace-prestataire/photos"
        case .providerLegal: path = "/prestataire-cgu"
        case .seasonalListings: path = "/locations-saisonnieres"
        case .hostLogin: path = "/hebergeur-connexion"
        case .hostSignup: path = "/hebergeur-inscription"
        case .hostDashboard: path = "/hebergeur-dashboard"
        case .hostCalendar: path = "/hebergeur-calendrier"
        case .hostBookings: path = "/hebergeur-demandes"
        case .terms: path = "/cgu"
        case .salesTerms: path = "/cgv"
        case .privacy: path = "/confidentialite"
        case .legalNotices: path = "/mentions-legales"
        case .brokerSalesTerms: path = "/broker-cgv"
        case .artisanSalesTerms: path = "/artisan-cgv"
        case .providerSalesTerms: path = "/prestataire-cgv"
        }
        return URL(string: "https://www.partenairefoyer.com\(path)")!
    }
}

@MainActor
final class PortalBrowser: ObservableObject {
    @Published var section: PortalSection
    private let initialSection: PortalSection
    @Published var isLoading = true
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL = AppConfig.websiteURL
    @Published var errorMessage: String?
    @Published var navigationHint: String?

    let webView: WKWebView
    private var started = false

    init(initialSection: PortalSection = .home) {
        self.initialSection = initialSection
        _section = Published(initialValue: initialSection)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // Cookies et connexion persistants.
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        if initialSection == .home {
            load(AppConfig.websiteURL)
        } else {
            navigate(to: initialSection)
        }
    }

    private func load(_ url: URL) {
        errorMessage = nil
        navigationHint = nil
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 35)
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    func navigate(to destination: PortalSection) {
        section = destination
        navigationHint = nil
        errorMessage = nil
        load(destination.landingURL)
    }

    func goBack() {
        navigationHint = nil
        if webView.canGoBack { webView.goBack() }
        else { navigate(to: .home) }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        errorMessage = nil
        navigationHint = nil
        if webView.url == nil { load(AppConfig.websiteURL) }
        else { webView.reload() }
    }

    func didNavigate() {
        currentURL = webView.url ?? AppConfig.websiteURL
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    func finishedNavigation() {
        didNavigate()
        errorMessage = nil
    }

    func isPartenaireFoyer(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme == "https" else { return false }
        return host == "partenairefoyer.com" || host.hasSuffix(".partenairefoyer.com")
    }
}

struct PortalWebView: UIViewRepresentable {
    @ObservedObject var browser: PortalBrowser

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeUIView(context: Context) -> WKWebView {
        let view = browser.webView
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator

        let refresher = UIRefreshControl()
        refresher.addTarget(context.coordinator, action: #selector(Coordinator.pullToRefresh(_:)), for: .valueChanged)
        view.scrollView.refreshControl = refresher

        context.coordinator.progressObservation = view.observe(
            \.estimatedProgress, options: [.new]
        ) { [weak browser] view, _ in
            DispatchQueue.main.async {
                browser?.progress = view.estimatedProgress
            }
        }
        browser.startIfNeeded()
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let browser: PortalBrowser
        var progressObservation: NSKeyValueObservation?

        init(browser: PortalBrowser) { self.browser = browser }

        @objc func pullToRefresh(_ sender: UIRefreshControl) {
            browser.reload()
            // Fin explicite au prochain didFinish / didFail.
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser.isLoading = true
            browser.didNavigate()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            browser.isLoading = false
            browser.finishedNavigation()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error, in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error, in: webView)
        }

        private func report(_ error: Error, in webView: WKWebView) {
            webView.scrollView.refreshControl?.endRefreshing()
            browser.isLoading = false
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                browser.errorMessage = "Impossible de charger cette page. Vérifiez votre connexion puis réessayez."
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if browser.isPartenaireFoyer(url) {
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            // Les sous-ressources du site restent chargées normalement.
            // Les navigations externes (tél, mail, paiement, OAuth, etc.)
            // s'ouvrent dans le navigateur iOS, pas dans une copie de compte.
            if let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel", "sms", "maps"].contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Liens target="_blank" du site : navigation dans l'app.
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                if browser.isPartenaireFoyer(url) {
                    webView.load(navigationAction.request)
                } else {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
            return nil
        }
    }
}

struct FullSiteRootView: View {
    let initialSection: PortalSection
    @StateObject private var browser: PortalBrowser

    init(initialSection: PortalSection = .home) {
        self.initialSection = initialSection
        _browser = StateObject(wrappedValue: PortalBrowser(initialSection: initialSection))
    }

    private let tabs: [PortalSection] = [.listings, .deposit, .favorites, .account]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 36)
                }
                .disabled(!browser.canGoBack)
                .accessibilityLabel("Retour")

                VStack(alignment: .leading, spacing: 2) {
                    Text("PartenaireFoyer")
                        .font(.headline)
                    Text(browser.section.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Actualiser")
                .padding(.horizontal, 4)

                ShareLink(item: browser.currentURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Partager la page")
                .padding(.horizontal, 4)

                Menu {
                    Button { browser.navigate(to: .classifieds) } label: {
                        Label("Petites annonces", systemImage: "shippingbox")
                    }
                    Button { browser.navigate(to: .professionals) } label: {
                        Label("Annuaire des professionnels", systemImage: "person.2")
                    }
                    Button { browser.navigate(to: .proLogin) } label: {
                        Label("Connexion professionnel", systemImage: "building.2")
                    }
                    Button { browser.navigate(to: .matching) } label: {
                        Label("Matching immobilier", systemImage: "arrow.left.arrow.right")
                    }
                    Button { browser.navigate(to: .estimate) } label: {
                        Label("Estimer un bien", systemImage: "chart.bar.xaxis")
                    }
                    Button { browser.navigate(to: .becomeAgent) } label: {
                        Label("Devenir mandataire", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Link("Assistance", destination: URL(string: "mailto:\(AppConfig.supportEmail)")!)
                    Link("Confidentialité", destination: AppConfig.privacyURL)
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .frame(width: 30, height: 36)
                }
                .accessibilityLabel("Tous les services")
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 52)

            if browser.isLoading {
                ProgressView(value: max(0.05, min(browser.progress, 1)))
                    .tint(.accentColor)
                    .progressViewStyle(.linear)
            }

            if let message = browser.errorMessage {
                HStack {
                    Text(message).font(.footnote)
                    Spacer()
                    Button("Réessayer") { browser.reload() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
            }
            if let hint = browser.navigationHint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(hint)
                        .font(.footnote)
                    Spacer()
                    Button { browser.navigationHint = nil } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
            }

            PortalWebView(browser: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button {
                        browser.navigate(to: tab)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 19, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(browser.section == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal, 4)
            .background(.background)
        }
        .background(Color(uiColor: .systemBackground))
    }
}
