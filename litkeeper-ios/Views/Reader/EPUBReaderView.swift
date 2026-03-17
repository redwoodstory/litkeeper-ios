import SwiftUI
import SwiftData
import WebKit
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

struct EPUBReaderView: View {
    let story: Story
    let localStory: LocalStory?
    let appState: AppState

    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss
    @Environment(\.colorScheme)   private var systemColorScheme

    @State private var showControls = true
    @State private var showSettings = false
    @State private var readingFraction: Double = 0
    @State private var publication: Publication?
    @State private var loadError: String?
    @State private var isContentReady = false

    @AppStorage("reader.fontSize")    private var fontSize:      Double = 17
    @AppStorage("reader.lineSpacing") private var lineSpacing:   Double = 1.58
    @AppStorage("reader.hPadding")    private var hPadding:      Double = 20
    @AppStorage("reader.fontKey")     private var fontKey:       String = "system"
    @AppStorage("reader.colorTheme")  private var colorThemeRaw: String = ""

    private var theme: ReaderTheme {
        if colorThemeRaw.isEmpty {
            return systemColorScheme == .dark ? .darkNavy : .beige
        }
        return ReaderTheme(rawValue: colorThemeRaw) ?? .beige
    }

    private var epubPreferences: EPUBPreferences {
        let readiumTheme: ReadiumNavigator.Theme
        let bgColor: ReadiumNavigator.Color?
        let fgColor: ReadiumNavigator.Color?

        switch theme {
        case .white:
            readiumTheme = .light;  bgColor = nil; fgColor = nil
        case .beige:
            readiumTheme = .sepia;  bgColor = nil; fgColor = nil
        case .grey:
            readiumTheme = .dark;   bgColor = nil; fgColor = nil
        case .pureBlack:
            readiumTheme = .dark
            bgColor = ReadiumNavigator.Color(hex: "000000")
            fgColor = ReadiumNavigator.Color(hex: "f0f0f0")
        case .darkNavy:
            readiumTheme = .dark
            bgColor = ReadiumNavigator.Color(hex: "0f1419")
            fgColor = ReadiumNavigator.Color(hex: "cccccc")
        }

        let fontFamily: FontFamily
        switch fontKey {
        case "newYork":     fontFamily = FontFamily(rawValue: "New York")
        case "georgia":     fontFamily = .georgia
        case "baskerville": fontFamily = FontFamily(rawValue: "Baskerville")
        case "didot":       fontFamily = FontFamily(rawValue: "Didot")
        default:            fontFamily = FontFamily(rawValue: "-apple-system")
        }

        return EPUBPreferences(
            backgroundColor: bgColor,
            fontFamily: fontFamily,
            fontSize: fontSize / 17.0,
            lineHeight: lineSpacing,
            pageMargins: hPadding / 20.0,
            publisherStyles: false,
            textColor: fgColor,
            theme: readiumTheme
        )
    }

    var body: some View {
        ZStack {
            if let publication {
                ReadiumEPUBView(
                    publication: publication,
                    initialLocatorJSON: localStory?.readingProgressLocator,
                    preferences: epubPreferences,
                    onLocatorChange: { locator in
                        if !isContentReady {
                            withAnimation(.easeOut(duration: 0.4)) { isContentReady = true }
                        }
                        readingFraction = locator.locations.totalProgression ?? readingFraction
                        if let localStory {
                            localStory.readingProgressLocator = locator.jsonString
                            localStory.readingProgressPercentage = readingFraction * 100
                            try? modelContext.save()
                        }
                    },
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.25)) { showControls.toggle() }
                    }
                )
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    if isContentReady && showControls {
                        headerBar.transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) {
                    if isContentReady && showControls {
                        footerBar.transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showControls)
            }

            if let loadError {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Dismiss") { dismiss() }
                            .padding(.top, 4)
                    }
                }
            } else if !isContentReady {
                EPUBLoadingOverlay(story: story, localStory: localStory, onDismiss: { dismiss() })
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(isContentReady && !showControls)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                hPadding: $hPadding,
                fontKey: $fontKey,
                colorThemeRaw: $colorThemeRaw
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if colorThemeRaw.isEmpty {
                colorThemeRaw = (systemColorScheme == .dark ? ReaderTheme.darkNavy : .beige).rawValue
            }
            readingFraction = (localStory?.readingProgressPercentage ?? 0) / 100
            Task { await openPublication() }
        }
        .onDisappear {
            guard readingFraction > 0 else { return }
            let progress = ReadingProgress(
                currentChapter: nil,
                cfi: nil,
                percentage: readingFraction,
                isCompleted: readingFraction >= 0.99,
                lastReadAt: nil
            )
            let storyID = story.id
            Task { try? await appState.makeAPIClient().saveProgress(storyID: storyID, progress: progress) }
        }
    }

    // MARK: - Header bar (mirrors HTMLReaderView.headerBar)

    private var headerBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .padding(10)
                    .background(Circle().fill(.regularMaterial))
            }
            Spacer()
            Text(story.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.horizontal, 8)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "textformat.size")
                    .font(.title3)
                    .padding(10)
                    .background(Circle().fill(.regularMaterial))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.card.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 0.5)
        }
    }

    // MARK: - Footer bar (mirrors HTMLReaderView.footerBar)

    private var footerBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: readingFraction)
            Text("\(Int(readingFraction * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(theme.card.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 0.5)
        }
    }

    // MARK: - Publication opener

    private func openPublication() async {
        guard let localStory, localStory.hasEPUB else {
            loadError = "EPUB not downloaded. Please download the story first."
            return
        }
        let epubURL = DownloadManager.shared.localEPUBURL(filenameBase: localStory.filenameBase)
        guard let fileURL = FileURL(url: epubURL) else {
            loadError = "Invalid EPUB file path."
            return
        }

        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: EPUBParser())

        do {
            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        } catch {
            loadError = "Could not open EPUB: \(error.localizedDescription)"
        }
    }
}

// MARK: - Loading Overlay

private struct EPUBLoadingOverlay: View {
    let story: Story
    let localStory: LocalStory?
    let onDismiss: () -> Void

    private var coverURL: URL? {
        guard let filename = localStory?.coverFilename else { return nil }
        let url = DownloadManager.shared.localCoverURL(filename: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var resumeText: String? {
        guard let pct = localStory?.readingProgressPercentage, pct > 1 else { return nil }
        return "Resuming at \(Int(pct))%"
    }

    var body: some View {
        ZStack {
            CoverImageView(url: coverURL, title: story.title, author: story.author)
                .blur(radius: 60)
                .overlay(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 28) {
                CoverImageView(url: coverURL, title: story.title, author: story.author)
                    .frame(width: 140, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                VStack(spacing: 6) {
                    Text(story.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let resumeText {
                        Text(resumeText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 40)

                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable

struct ReadiumEPUBView: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocatorJSON: String?
    var preferences: EPUBPreferences
    var onLocatorChange: (Locator) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLocatorChange: onLocatorChange, onTap: onTap)
    }

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let initialLocator = initialLocatorJSON.flatMap { try? Locator(jsonString: $0) }
        var config = EPUBNavigatorViewController.Configuration()
        config.preloadPreviousPositionCount = 0
        config.preloadNextPositionCount = 1
        config.preferences = preferences
        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            config: config
        )
        navigator.delegate = context.coordinator
        return navigator
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        context.coordinator.onLocatorChange = onLocatorChange
        context.coordinator.onTap = onTap
        uiViewController.submitPreferences(preferences)
    }

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        var onLocatorChange: (Locator) -> Void
        var onTap: () -> Void

        init(onLocatorChange: @escaping (Locator) -> Void, onTap: @escaping () -> Void) {
            self.onLocatorChange = onLocatorChange
            self.onTap = onTap
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            onLocatorChange(locator)
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            onTap()
        }
    }
}
