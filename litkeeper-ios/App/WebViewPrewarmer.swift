import WebKit

/// Holds a persistent WKWebView that forces iOS to spin up the WebContent,
/// GPU, and Networking sub-processes during app launch so they're already
/// running when the EPUB reader opens.
@MainActor
final class WebViewPrewarmer {
    static let shared = WebViewPrewarmer()

    private var webView: WKWebView?

    private init() {}

    func prewarm() {
        guard webView == nil else { return }
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.loadHTMLString("<html></html>", baseURL: nil)
        webView = wv
    }
}
