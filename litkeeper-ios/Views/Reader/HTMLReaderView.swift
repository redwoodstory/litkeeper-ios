import SwiftUI
import WebKit
import SwiftData

struct HTMLReaderView: View {
    let localStory: LocalStory
    let appState: AppState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var scrollProgress: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            HTMLWebView(
                localStory: localStory,
                onScroll: { fraction in
                    scrollProgress = fraction
                    localStory.readingProgressScrollY = fraction
                    localStory.readingProgressPercentage = fraction * 100
                    try? modelContext.save()
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
                        Text(localStory.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(scrollProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)

                    Spacer()

                    ProgressView(value: scrollProgress)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .background(.regularMaterial)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showControls)
        .onAppear { scrollProgress = (localStory.readingProgressScrollY ?? 0) }
    }
}

// MARK: - UIViewRepresentable

struct HTMLWebView: UIViewRepresentable {
    let localStory: LocalStory
    var onScroll: (Double) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialScrollFraction: (localStory.readingProgressScrollY ?? 0),
            onScroll: onScroll,
            onTap: onTap
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scroll")
        config.userContentController.add(context.coordinator, name: "tap")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let htmlPath = localStory.htmlLocalPath {
            let htmlURL = DownloadManager.shared.htmlDirectory.appendingPathComponent(htmlPath)
            let dir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: dir)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIScrollViewDelegate {
        let initialScrollFraction: Double
        var onScroll: (Double) -> Void
        var onTap: () -> Void
        weak var webView: WKWebView?
        private var didRestorePosition = false

        init(initialScrollFraction: Double,
             onScroll: @escaping (Double) -> Void,
             onTap: @escaping () -> Void) {
            self.initialScrollFraction = initialScrollFraction
            self.onScroll = onScroll
            self.onTap = onTap
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "scroll":
                let fraction = message.body as? Double ?? 0
                DispatchQueue.main.async { self.onScroll(fraction) }
            case "tap":
                DispatchQueue.main.async { self.onTap() }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject reader styles and restore scroll position
            let readerCSS = """
            body {
              font-family: -apple-system, 'Helvetica Neue', sans-serif;
              font-size: 17px;
              line-height: 1.7;
              max-width: 680px;
              margin: 0 auto;
              padding: 24px 20px 60px;
              color: var(--reader-text, #1a1a1a);
              background: var(--reader-bg, #ffffff);
            }
            @media (prefers-color-scheme: dark) {
              body { --reader-text: #e8e8e8; --reader-bg: #1a1a1a; }
            }
            img { max-width: 100%; height: auto; }
            """

            let setupJS = """
            (function() {
              // Inject styles
              var style = document.createElement('style');
              style.textContent = `\(readerCSS)`;
              document.head.appendChild(style);

              // Restore scroll position
              var fraction = \(initialScrollFraction);
              if (fraction > 0) {
                var h = document.body.scrollHeight - window.innerHeight;
                window.scrollTo(0, h * fraction);
              }

              // Report scroll progress
              var ticking = false;
              window.addEventListener('scroll', function() {
                if (!ticking) {
                  window.requestAnimationFrame(function() {
                    var h = document.body.scrollHeight - window.innerHeight;
                    var pct = h > 0 ? window.scrollY / h : 0;
                    window.webkit.messageHandlers.scroll.postMessage(pct);
                    ticking = false;
                  });
                  ticking = true;
                }
              }, { passive: true });

              // Tap to toggle controls
              document.addEventListener('click', function(e) {
                var cx = e.clientX, cy = e.clientY;
                var iw = window.innerWidth, ih = window.innerHeight;
                if (cx > iw * 0.2 && cx < iw * 0.8 && cy > ih * 0.2 && cy < ih * 0.8) {
                  window.webkit.messageHandlers.tap.postMessage({});
                }
              });
            })();
            """
            webView.evaluateJavaScript(setupJS)
        }
    }
}
