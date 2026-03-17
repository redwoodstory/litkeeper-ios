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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var chapterTitle = ""
    @State private var readingFraction: Double = 0
    @State private var publication: Publication?
    @State private var loadError: String?
    @State private var isContentReady = false

    var body: some View {
        ZStack(alignment: .top) {
            if let publication {
                ReadiumEPUBView(
                    publication: publication,
                    initialLocatorJSON: localStory?.readingProgressLocator,
                    onLocatorChange: { locator in
                        if !isContentReady {
                            withAnimation(.easeOut(duration: 0.4)) { isContentReady = true }
                        }
                        readingFraction = locator.locations.totalProgression ?? readingFraction
                        chapterTitle = locator.title ?? ""
                        if let localStory {
                            localStory.readingProgressLocator = locator.jsonString
                            localStory.readingProgressPercentage = readingFraction * 100
                            try? modelContext.save()
                        }
                    },
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                    }
                )
                .ignoresSafeArea()
            }

            if isContentReady && showControls {
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
        .onAppear {
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
        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            config: config
        )
        navigator.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        navigator.view.addGestureRecognizer(tap)

        return navigator
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        context.coordinator.onLocatorChange = onLocatorChange
        context.coordinator.onTap = onTap
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

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let loc = gesture.location(in: view)
            let inCenter = loc.x > view.bounds.width * 0.2 && loc.x < view.bounds.width * 0.8
                        && loc.y > view.bounds.height * 0.2 && loc.y < view.bounds.height * 0.8
            if inCenter { onTap() }
        }
    }
}
