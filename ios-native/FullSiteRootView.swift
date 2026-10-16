import SwiftUI
import WebKit
import Combine
import UIKit

/// L'application utilise la plateforme publique PartenaireFoyer comme source
/// unique pour les comptes, annonces (Wix + Supabase), favoris et dashboards.
/// Pas de second compte, pas de copie partielle de la base des annonces.
enum PortalSection: String, CaseIterable, Identifiable {
    case home, listings, deposit, favorites, account
    case classifieds, professionals, proLogin, matching, estimate, becomeAgent

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
        }
    }

    /// Textes réels de la page d'accueil / des pages publiques Wix.
    /// Ne pas inventer des URLs de dashboards : la session et les permissions
    /// sont gérées par les liens de navigation du site.
    var linksToFind: [String] {
        switch self {
        case .home, .professionals: return []
        case .listings: return ["Voir toutes les annonces"]
        case .deposit: return ["Connexion / Inscription", "Déposez votre annonce gratuitement"]
        case .favorites: return ["Mes favoris", "Favoris"]
        case .account: return ["Connexion / Inscription"]
        case .classifieds: return ["Voir toutes les petites annonces", "Voir les petites annonces"]
        case .proLogin: return ["Connexion professionnel"]
        case .matching: return ["Découvrir le matching immobilier"]
        case .estimate: return ["Estimer"]
        case .becomeAgent: return ["Devenir mandataire immobilier"]
        }
    }

    var landingURL: URL {
        if self == .professionals || self == .proLogin {
            return URL(string: "https://www.partenairefoyer.com/pros")!
        }
        return AppConfig.websiteURL
    }
}

@MainActor
final class PortalBrowser: ObservableObject {
    @Published var section: PortalSection = .home
    @Published var isLoading = true
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL = AppConfig.websiteURL
    @Published var errorMessage: String?
    @Published var navigationHint: String?

    let webView: WKWebView
    private var started = false
    private var pendingLabels: [String]?
    private var cachedURLs: [PortalSection: URL] = [:]

    init() {
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
        load(AppConfig.websiteURL)
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
        pendingLabels = nil

        if destination == .home || destination == .professionals {
            load(destination.landingURL)
            return
        }

        if let cached = cachedURLs[destination] {
            load(cached)
            return
        }

        pendingLabels = destination.linksToFind
        // On repart d'une page connue et publique ; les liens de connexion
        // restent gérés par le site, avec l'authentification Wix existante.
        if webView.url == destination.landingURL && !isLoading {
            tryPendingAction(attempt: 0)
        } else {
            load(destination.landingURL)
        }
    }

    func goBack() {
        pendingLabels = nil
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
        rememberRoute(currentURL)
    }

    private func rememberRoute(_ url: URL) {
        guard isPartenaireFoyer(url) else { return }
        let path = url.path.lowercased()
        if path.contains("favori") { cachedURLs[.favorites] = url }
        if path.contains("petite") && path.contains("annonce") {
            cachedURLs[.classifieds] = url
        }
        if path.contains("annonce") && !path.contains("petite")
            && !path.contains("annonce-immobiliere/") {
            cachedURLs[.listings] = url
        }
    }

    func finishedNavigation() {
        didNavigate()
        errorMessage = nil
        if pendingLabels != nil {
            // Wix peut rendre ses liens après DOMContentLoaded.
            tryPendingAction(attempt: 0)
        }
    }

    private func tryPendingAction(attempt: Int) {
        guard let labels = pendingLabels, !labels.isEmpty else { return }
        guard !webView.isLoading else { return }

        // Utilise seulement les liens/boutons réellement présents sur Wix.
        // L'ordre des préférences évite de lancer un flux non demandé.
        let encoded = (try? JSONSerialization.data(withJSONObject: labels))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let script = """
        (function () {
          const labels = \(encoded);
          const norm = value => String(value || '').normalize('NFD')
             .replace(/[\\u0300-\\u036f]/g, '')
             .replace(/\\s+/g, ' ').trim().toLowerCase();
          const targets = Array.from(document.querySelectorAll(
             'a, button, [role="button"]'
          )).filter(el => el.getClientRects().length > 0);
          for (const wanted of labels) {
            const goal = norm(wanted);
            const exact = targets.find(el => norm(el.innerText || el.textContent) === goal);
            const match = exact || targets.find(el => {
              const label = norm(el.innerText || el.textContent);
              return label.length < 95 && label.includes(goal);
            });
            if (match) {
              const href = match.closest('a')?.href || match.getAttribute('href');
              match.click();
              return href || 'clicked';
            }
          }
          return '';
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, self.pendingLabels == labels else { return }
                if let value = result as? String, !value.isEmpty {
                    self.pendingLabels = nil
                    self.navigationHint = nil
                    if let url = URL(string: value), self.isPartenaireFoyer(url) {
                        self.cachedURLs[self.section] = url
                    }
                } else if attempt < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self.tryPendingAction(attempt: attempt + 1)
                    }
                } else {
                    self.pendingLabels = nil
                    self.navigationHint = "Utilisez le menu du site pour accéder à « \(self.section.title) »."
                }
            }
        }
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
    @StateObject private var browser = PortalBrowser()

    private let tabs: [PortalSection] = [.home, .listings, .deposit, .favorites, .account]

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
