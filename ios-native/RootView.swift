import SwiftUI
import WebKit
import UIKit

struct RootView: View {
    var body: some View {
        PartenaireFoyerWebsiteView()
    }
}

/// Keeps the complete PartenaireFoyer experience inside the iOS app.
/// The site owns navigation, accounts, listings, dashboards, and seasonal themes,
/// so the app stays in sync with the full responsive website.
private struct PartenaireFoyerWebsiteView: UIViewRepresentable {
    private let homeURL = URL(string: "https://www.partenairefoyer.com/")!

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.load(URLRequest(url: homeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Keep links that request a new window inside the app.
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            switch url.scheme?.lowercased() {
            case "mailto", "tel", "sms":
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }
    }
}
