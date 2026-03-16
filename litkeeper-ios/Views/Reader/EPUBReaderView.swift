import SwiftUI
import WebKit
import SwiftData

struct EPUBReaderView: View {
    let story: Story
    let localStory: LocalStory?
    let appState: AppState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var chapterTitle = ""
    @State private var readingFraction: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            EPUBWebView(
                storyID: story.id,
                filenameBase: story.filenameBase,
                initialCFI: localStory?.readingProgressCFI,
                serverURL: appState.serverURL,
                token: appState.apiToken,
                onRelocate: { fraction, title in
                    readingFraction = fraction
                    chapterTitle = title ?? ""
                    if let localStory {
                        localStory.readingProgressPercentage = fraction * 100
                        try? modelContext.save()
                    }
                },
                onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }
            )
            .ignoresSafeArea()

            if showControls {
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .padding(10)
                                .background(Circle().fill(.regularMaterial))
                        }
                        Spacer()
                        if !chapterTitle.isEmpty {
                            Text(chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(readingFraction * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)

                    Spacer()

                    ProgressView(value: readingFraction)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .background(.regularMaterial)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showControls)
        .onAppear { readingFraction = (localStory?.readingProgressPercentage ?? 0) / 100 }
    }
}

// MARK: - UIViewRepresentable

struct EPUBWebView: UIViewRepresentable {
    let storyID: Int
    let filenameBase: String
    let initialCFI: String?
    let serverURL: String
    let token: String
    var onRelocate: (Double, String?) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(storyID: storyID, filenameBase: filenameBase, initialCFI: initialCFI,
                    onRelocate: onRelocate, onTap: onTap)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "progress")
        config.userContentController.add(context.coordinator, name: "tap")

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        let handler = EPUBSchemeHandler(
            serverBase: URL(string: base),
            token: token.isEmpty ? nil : token
        )
        config.setURLSchemeHandler(handler, forURLScheme: "epub-local")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        webView.load(URLRequest(url: URL(string: "epub-local://app/epub-reader.html")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let storyID: Int
        let filenameBase: String
        let initialCFI: String?
        var onRelocate: (Double, String?) -> Void
        var onTap: () -> Void
        weak var webView: WKWebView?

        init(storyID: Int, filenameBase: String, initialCFI: String?,
             onRelocate: @escaping (Double, String?) -> Void,
             onTap: @escaping () -> Void) {
            self.storyID = storyID
            self.filenameBase = filenameBase
            self.initialCFI = initialCFI
            self.onRelocate = onRelocate
            self.onTap = onTap
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "progress":
                guard let body = message.body as? [String: Any] else { return }
                let fraction = body["fraction"] as? Double ?? 0
                let title = body["chapterTitle"] as? String
                DispatchQueue.main.async { self.onRelocate(fraction, title) }
            case "tap":
                DispatchQueue.main.async { self.onTap() }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let cfi = initialCFI ?? ""
            let escapedCFI = cfi.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            window.postMessage({
              type: 'open',
              payload: { url: 'epub-local://epub/\(storyID)/\(filenameBase)', cfi: '\(escapedCFI)' }
            }, '*');
            """
            webView.evaluateJavaScript(js)
        }
    }
}
