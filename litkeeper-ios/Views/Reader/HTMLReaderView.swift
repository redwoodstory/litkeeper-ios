import SwiftUI
import SwiftData

// MARK: - Story content model

struct StoryContent: Codable {
    let title: String?
    let author: String?
    let category: String?
    let description: String?
    let tags: [String]?
    let chapters: [Chapter]

    struct Chapter: Codable {
        let number: Int
        let title: String?
        let paragraphs: [String]
    }

    var totalParagraphs: Int { chapters.reduce(0) { $0 + $1.paragraphs.count } }

    func flatIndex(chapterIndex: Int, paragraphIndex: Int) -> Int {
        chapters[0..<chapterIndex].reduce(0) { $0 + $1.paragraphs.count } + paragraphIndex
    }

    func chapterAndParagraph(for flatIndex: Int) -> (Int, Int)? {
        var remaining = flatIndex
        for (ci, ch) in chapters.enumerated() {
            if remaining < ch.paragraphs.count { return (ci, remaining) }
            remaining -= ch.paragraphs.count
        }
        return nil
    }
}

// MARK: - Color theme

enum ReaderTheme: String, CaseIterable {
    case white, beige, pureBlack, grey, darkNavy

    var label: String {
        switch self {
        case .white:     return "White"
        case .beige:     return "Beige"
        case .pureBlack: return "Black"
        case .grey:      return "Grey"
        case .darkNavy:  return "Navy"
        }
    }

    var isDark: Bool {
        switch self {
        case .white, .beige: return false
        default: return true
        }
    }

    var background: Color {
        switch self {
        case .white:     return Color(readerHex: "#ffffff")
        case .beige:     return Color(readerHex: "#f5f0e8")
        case .pureBlack: return Color(readerHex: "#000000")
        case .grey:      return Color(readerHex: "#1c1c1e")
        case .darkNavy:  return Color(readerHex: "#0f1419")
        }
    }

    var text: Color {
        switch self {
        case .white:     return Color(readerHex: "#1a1a1a")
        case .beige:     return Color(readerHex: "#2c2420")
        case .pureBlack: return Color(readerHex: "#f0f0f0")
        case .grey:      return Color(readerHex: "#e0e0e0")
        case .darkNavy:  return Color(readerHex: "#cccccc")
        }
    }

    var secondary: Color {
        switch self {
        case .white:     return Color(readerHex: "#666666")
        case .beige:     return Color(readerHex: "#7a6a60")
        case .pureBlack: return Color(readerHex: "#999999")
        case .grey:      return Color(readerHex: "#9ca3af")
        case .darkNavy:  return Color(readerHex: "#9ca3af")
        }
    }

    // Card backgrounds: slightly offset from the page background
    var card: Color {
        switch self {
        case .white:     return Color(readerHex: "#f9fafb")
        case .beige:     return Color(readerHex: "#ede8dc")
        case .pureBlack: return Color(readerHex: "#111111")
        case .grey:      return Color(readerHex: "#2a2a2a")
        case .darkNavy:  return Color(readerHex: "#1f2937")  // matches Flask --header-bg
        }
    }

    var border: Color {
        switch self {
        case .white:     return Color(readerHex: "#e5e7eb")
        case .beige:     return Color(readerHex: "#d4c9b8")
        case .pureBlack: return Color(readerHex: "#2a2a2a")
        case .grey:      return Color(readerHex: "#374151")
        case .darkNavy:  return Color(readerHex: "#374151")  // matches Flask --separator-color
        }
    }
}

// MARK: - Reader

struct HTMLReaderView: View {
    let story: Story
    let localStory: LocalStory?
    let appState: AppState
    var targetChapterIndex: Int? = nil
    var targetParagraphIndex: Int? = nil
    var targetQuoteText: String? = nil

    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss
    @Environment(\.colorScheme)   private var systemColorScheme
    @Environment(SyncService.self) private var syncService

    @AppStorage("reader.fontSize")    private var fontSize:      Double = 17
    @AppStorage("reader.lineSpacing") private var lineSpacing:   Double = 1.58
    @AppStorage("reader.hPadding")    private var hPadding:      Double = 20
    @AppStorage("reader.fontKey")     private var fontKey:       String = "system"
    @AppStorage("reader.colorTheme")  private var colorThemeRaw: String = ""

    @State private var content: StoryContent?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showControls = true
    @State private var showSettings = false
    @State private var scrollProgress: Double = 0
    @State private var scrollPos = ScrollPosition(edge: .top)
    @State private var contentHeight: CGFloat = 0
    @State private var hasRestoredPosition = false
    @State private var lastPushedFraction: Double = -1
    @State private var serverScrollFraction: Double? = nil
    @State private var didFireCompletionHaptic = false
    @State private var readerItems: [ReaderItem] = []
    @State private var quoteAlertVisible = false
    @State private var quoteErrorAlertVisible = false
    @State private var showSaveQuoteDialog = false
    @State private var pendingQuoteChapter: Int? = nil
    @State private var pendingQuoteParagraph: Int? = nil
    @State private var pendingQuoteText: String = ""
    @State private var targetScrollID: String? = nil
    @State private var highlightFlatIndex: Int? = nil
    @State private var pendingScrollToID: String? = nil
    @State private var pendingResumeScrollID: String? = nil
    @State private var attrCache: [Int: AttributedString] = [:]
    @State private var visibleParagraphIndices: Set<Int> = []
    @State private var totalParagraphs: Int = 0

    private var theme: ReaderTheme {
        if colorThemeRaw.isEmpty {
            return systemColorScheme == .dark ? .darkNavy : .beige
        }
        return ReaderTheme(rawValue: colorThemeRaw) ?? .beige
    }

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let content {
                readerBody(content: content)
            }
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .statusBarHidden(!showControls)
        .onAppear {
            // Persist the smart default so the settings sheet shows the right selection
            if colorThemeRaw.isEmpty {
                colorThemeRaw = (systemColorScheme == .dark ? ReaderTheme.darkNavy : .beige).rawValue
            }
        }
        .task { await loadContent() }
        .onChange(of: readerItems.count) { old, new in
            if old == 0 && new > 0 { buildAttrCache() }
        }
        .onChange(of: fontSize)       { _, _ in buildAttrCache() }
        .onChange(of: fontKey)        { _, _ in buildAttrCache() }
        .onChange(of: colorThemeRaw)  { _, _ in buildAttrCache() }
        .onDisappear {
            guard scrollProgress > 0 else {
                print("[HTML] onDisappear: scrollProgress=0, skipping server save")
                return
            }
            let fraction = scrollProgress
            let storyID = story.id
            let paragraphID = localStory?.readingProgressParagraphID
            print("[HTML] onDisappear: saving fraction=\(String(format: "%.4f", fraction)) (\(Int(fraction * 100))%) for story \(storyID)")

            // Upsert a pending operation so progress survives if we're offline
            let existing = (try? modelContext.fetch(
                FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.storyID == storyID && $0.operationType == "progress" })
            ))?.first
            let op: PendingOperation
            if let existing {
                op = existing
            } else {
                op = PendingOperation(storyID: storyID, operationType: "progress")
                modelContext.insert(op)
            }
            op.progressFraction = fraction
            op.progressParagraphID = paragraphID
            try? modelContext.save()

            Task { await syncService.flushPendingOperations(appState: appState, modelContext: modelContext) }
        }
    }

    // MARK: - Loading / error states

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading story…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    // MARK: - Reader items (one item per paragraph for precise scroll targeting)

    private enum ReaderItem: Identifiable {
        case header
        case chapterDivider(chapterIndex: Int)
        case chapterTitle(chapterIndex: Int, title: String)
        case paragraph(flatIndex: Int, text: String)

        var id: String {
            switch self {
            case .header:                        return "header"
            case .chapterDivider(let ci):        return "div-\(ci)"
            case .chapterTitle(let ci, _):       return "title-\(ci)"
            case .paragraph(let fi, _):          return "para-\(fi)"
            }
        }
    }

    private func buildItems(content: StoryContent) -> [ReaderItem] {
        var items: [ReaderItem] = [.header]
        for (ci, chapter) in content.chapters.enumerated() {
            if ci > 0 { items.append(.chapterDivider(chapterIndex: ci)) }
            if let title = chapter.title, !title.isEmpty {
                items.append(.chapterTitle(chapterIndex: ci, title: title))
            }
            let chapterStart = content.flatIndex(chapterIndex: ci, paragraphIndex: 0)
            for (pi, text) in chapter.paragraphs.enumerated() {
                items.append(.paragraph(flatIndex: chapterStart + pi, text: text))
            }
        }
        return items
    }

    // MARK: - Reader body

    @ViewBuilder
    private func readerBody(content: StoryContent) -> some View {
        ScrollView(.vertical) {
            ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(readerItems) { item in
                    switch item {
                    case .header:
                        storyHeader(content: content)
                    case .chapterDivider:
                        HStack {
                            Spacer()
                            Text("◆  ◆  ◆")
                                .font(.caption)
                                .foregroundStyle(theme.secondary.opacity(0.5))
                            Spacer()
                        }
                        .padding(.vertical, 36)
                    case .chapterTitle(_, let title):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(theme.text)
                            Rectangle()
                                .fill(theme.border)
                                .frame(height: 1.5)
                        }
                        .padding(.bottom, 24)
                    case .paragraph(let flatIndex, let text):
                        ParagraphView(
                            text: text,
                            isHighlighted: highlightFlatIndex == flatIndex,
                            cachedAttr: attrCache[flatIndex],
                            baseFont: resolvedFont,
                            textColor: theme.text,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing
                        )
                        .onAppear    { visibleParagraphIndices.insert(flatIndex) }
                        .onDisappear { visibleParagraphIndices.remove(flatIndex) }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            if let (ci, pi) = content.chapterAndParagraph(for: flatIndex) {
                                pendingQuoteChapter = ci
                                pendingQuoteParagraph = pi
                                pendingQuoteText = text
                                showSaveQuoteDialog = true
                                HapticManager.shared.selectionChanged()
                            }
                        }
                    }
                }
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, CGFloat(hPadding))
            .padding(.top, 80)
            .padding(.bottom, 20)
            .onChange(of: pendingScrollToID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
                pendingScrollToID = nil
            }
            .onChange(of: pendingResumeScrollID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .top)
                pendingResumeScrollID = nil
            }
            } // ScrollViewReader
        }
        .scrollPosition($scrollPos)
        .background(theme.background)
        .overlay {
            if !hasRestoredPosition {
                theme.background.ignoresSafeArea()
            }
        }
        // Capture content height for pixel-precise restoration
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, h in
            contentHeight = h
        }
        // Track scroll progress from visible paragraph index — stable under lazy layout.
        .onChange(of: visibleParagraphIndices) { _, indices in
            guard let minIndex = indices.min(), totalParagraphs > 0 else { return }
            let fraction = min(Double(minIndex) / Double(max(totalParagraphs - 1, 1)), 1.0)
            scrollProgress = fraction
            if fraction >= 0.99 && !didFireCompletionHaptic {
                didFireCompletionHaptic = true
                HapticManager.shared.notify(.success)
            }
        }
        .onScrollPhaseChange { _, newPhase in
            guard newPhase == .idle, hasRestoredPosition else { return }
            let fraction = scrollProgress
            print("[HTML] scroll idle — saving \(Int(fraction * 100))%")
            if let localStory {
                localStory.readingProgressScrollY = fraction
                localStory.readingProgressPercentage = fraction * 100
                if let minIndex = visibleParagraphIndices.min() {
                    let id = "para-\(minIndex)"
                    localStory.readingProgressParagraphID = id
                    print("[HTML] saving paragraphID=\(id)")
                }
            }
            if fraction > lastPushedFraction + 0.05 {
                lastPushedFraction = fraction
                print("[HTML] server sync (idle): \(Int(fraction * 100))%")
                let storyID = story.id
                let paragraphID = visibleParagraphIndices.min().map { "para-\($0)" }
                let progress = ReadingProgress(
                    currentChapter: nil, cfi: nil,
                    percentage: fraction,
                    isCompleted: fraction >= 0.99,
                    lastReadAt: nil,
                    paragraphID: paragraphID
                )
                Task { try? await appState.makeAPIClient().saveProgress(storyID: storyID, progress: progress) }
            }
        }
        .task(id: readerItems.isEmpty) {
            guard !readerItems.isEmpty else { return }

            // Priority 1: opened from a highlight — jump to that exact paragraph.
            if let targetID = targetScrollID {
                var attempts = 0
                while contentHeight == 0 && attempts < 20 {
                    try? await Task.sleep(for: .milliseconds(50))
                    attempts += 1
                }
                pendingScrollToID = targetID
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeIn(duration: 0.15)) { hasRestoredPosition = true }
                return
            }

            // Priority 2: saved paragraph ID — precise, layout-independent.
            if let paragraphID = localStory?.readingProgressParagraphID {
                print("[HTML] restore: paragraph-based → \(paragraphID)")
                pendingResumeScrollID = paragraphID
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeIn(duration: 0.15)) { hasRestoredPosition = true }
                return
            }

            // Priority 3: fraction-based fallback (for saves predating paragraph tracking).
            let localFraction = localStory?.readingProgressScrollY ?? 0
            let serverFraction = serverScrollFraction ?? 0
            let saved = max(localFraction, serverFraction)
            guard saved > 0 else {
                print("[HTML] restore: no saved progress, starting at beginning")
                withAnimation(.easeIn(duration: 0.15)) { hasRestoredPosition = true }
                return
            }
            print("[HTML] restore: fraction-based \(Int(localFraction * 100))%/\(Int(serverFraction * 100))% → using \(Int(saved * 100))%")
            scrollProgress = saved
            try? await Task.sleep(for: .milliseconds(100))
            guard contentHeight > 0 else {
                hasRestoredPosition = true
                return
            }
            let targetY = saved * contentHeight
            print("[HTML] restore: fraction=\(String(format: "%.4f", saved)), targetY=\(String(format: "%.1f", targetY))/\(String(format: "%.1f", contentHeight))")
            withAnimation(.none) {
                scrollPos = ScrollPosition(point: CGPoint(x: 0, y: targetY))
            }
            withAnimation(.easeIn(duration: 0.15)) { hasRestoredPosition = true }
        }
        .onTapGesture {
            HapticManager.shared.selectionChanged()
            withAnimation(.easeInOut(duration: 0.25)) { showControls.toggle() }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if showControls {
                headerBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showControls {
                footerBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
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
        .sheet(isPresented: $showSaveQuoteDialog) {
            SaveQuoteSheet(
                text: pendingQuoteText,
                onSave: {
                    if let ci = pendingQuoteChapter, let pi = pendingQuoteParagraph {
                        let text = pendingQuoteText
                        Task { await saveQuote(chapterIndex: ci, paragraphIndex: pi, rawHTML: text) }
                    }
                }
            )
            .presentationDetents([.height(360)])
            .presentationCornerRadius(20)
            .presentationDragIndicator(.visible)
        }
        .alert("Quote Saved", isPresented: $quoteAlertVisible) {
            Button("OK", role: .cancel) {}
        }
        .alert("Could Not Save Quote", isPresented: $quoteErrorAlertVisible) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Story header card (mirrors Flask .story-header)

    @ViewBuilder
    private func storyHeader(content: StoryContent) -> some View {
        VStack(spacing: 14) {
            Text(content.title ?? story.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)

            Text("by \(content.author ?? story.author)")
                .font(.body.italic())
                .foregroundStyle(theme.secondary)

            if (content.category != nil && !(content.category!.isEmpty)) ||
               (content.tags != nil && !(content.tags!.isEmpty)) {
                HStack(spacing: 8) {
                    if let cat = content.category, !cat.isEmpty {
                        Text(cat)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                            .overlay(Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 1))
                            .foregroundStyle(Color.blue)
                    }
                    if let tags = content.tags, !tags.isEmpty {
                        Text(tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(theme.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let desc = content.description, !desc.isEmpty {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
                    .padding(.top, 4)
                Text(desc)
                    .font(.callout.italic())
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(8)
                    .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
        .padding(.bottom, 28)
    }

    // MARK: - Controls overlay (header + footer rendered separately for directional transitions)

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

    private var footerBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: scrollProgress)
                .animation(.linear(duration: 0.3), value: scrollProgress)
            Text("\(Int(scrollProgress * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(theme.card.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 0.5)
        }
    }

    // MARK: - Font resolution

    private var resolvedFont: Font {
        let size = CGFloat(fontSize)
        switch fontKey {
        case "newYork":     return .system(size: size, design: .serif)
        case "georgia":     return .custom("Georgia",    size: size)
        case "baskerville": return .custom("Baskerville", size: size)
        case "didot":       return .custom("Didot",      size: size)
        default:            return .system(size: size)
        }
    }

    // MARK: - AttributedString cache

    private func buildAttrCache() {
        let font = resolvedFont
        let color = theme.text
        let items = readerItems
        Task {
            var built: [Int: AttributedString] = [:]
            for item in items {
                if case .paragraph(let fi, let text) = item {
                    built[fi] = styledAttributedString(html: text, baseFont: font, color: color)
                }
            }
            attrCache = built
        }
    }

    // MARK: - Content loading

    private func saveQuote(chapterIndex: Int, paragraphIndex: Int, rawHTML: String) async {
        let text = rawHTML
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard appState.isConfigured, !text.isEmpty else { return }
        do {
            try await appState.makeAPIClient().saveHighlight(
                storyID: story.id,
                chapterIndex: chapterIndex,
                paragraphIndex: paragraphIndex,
                quoteText: text
            )
            HapticManager.shared.notify(.success)
            await MainActor.run { quoteAlertVisible = true }
        } catch {
            await MainActor.run { quoteErrorAlertVisible = true }
        }
    }

    private func loadContent() async {
        // Capture everything from appState/story/localStory BEFORE any await.
        // loadContent() is nonisolated async — after any suspension it resumes on a
        // background thread, so reading @Observable / @Environment values after an
        // await is unsafe and can silently produce stale or nil results.
        let storyID       = story.id
        let filenameBase  = story.filenameBase
        let localHTMLPath    = localStory?.htmlLocalPath
        let localScrollY     = localStory?.readingProgressScrollY
        let localParagraphID = localStory?.readingProgressParagraphID
        let client: APIClient? = appState.isConfigured ? appState.makeAPIClient() : nil
        let serverBase    = appState.serverURL.hasSuffix("/")
            ? String(appState.serverURL.dropLast())
            : appState.serverURL
        let apiToken      = appState.apiToken

        // ── 1. Load story JSON ────────────────────────────────────────────
        let decoded: StoryContent

        if let path = localHTMLPath {
            let fileURL = DownloadManager.shared.htmlDirectory.appendingPathComponent(path)
            do {
                let data = try Data(contentsOf: fileURL)
                decoded = try JSONDecoder().decode(StoryContent.self, from: data)
                print("[HTML] loadContent: loaded from local file (\(data.count)B)")
            } catch {
                await MainActor.run { loadError = "Could not load local file."; isLoading = false }
                return
            }
        } else {
            guard let url = URL(string: "\(serverBase)/download/\(filenameBase).json") else {
                await MainActor.run { loadError = "Invalid server URL."; isLoading = false }
                return
            }
            var request = URLRequest(url: url)
            if !apiToken.isEmpty {
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    await MainActor.run { loadError = "Server returned an error."; isLoading = false }
                    return
                }
                decoded = try JSONDecoder().decode(StoryContent.self, from: data)
                print("[HTML] loadContent: loaded from server (\(data.count)B)")
            } catch {
                await MainActor.run {
                    loadError = "Could not load story: \(error.localizedDescription)"
                    isLoading = false
                }
                return
            }
        }

        // ── 2. Fetch server reading progress ─────────────────────────────
        var progressFraction: Double? = nil
        if let c = client {
            print("[HTML] loadContent: fetching server progress for story \(storyID)…")
            let serverProgress = try? await c.fetchProgress(storyID: storyID)
            progressFraction = serverProgress?.percentage
            print("[HTML] loadContent: serverProgress.percentage=\(progressFraction?.description ?? "nil"), localScrollY=\(localScrollY?.description ?? "nil")")
        } else {
            print("[HTML] loadContent: server not configured, skipping progress fetch")
        }

        // ── 3. Commit to main thread ──────────────────────────────────────
        let items = buildItems(content: decoded)

        // If opened from a highlight, find the target paragraph.
        // Primary: search by quote text — resilient to story updates shifting paragraph indices.
        // Fallback: use stored chapter/paragraph indices.
        var resolvedTargetScrollID: String? = nil
        var resolvedHighlightFlatIndex: Int? = nil
        if targetChapterIndex != nil || targetQuoteText != nil {
            var found = false
            if let quote = targetQuoteText {
                let needle = quote.trimmingCharacters(in: .whitespacesAndNewlines)
                outer: for (ci, chapter) in decoded.chapters.enumerated() {
                    for (pi, paraHTML) in chapter.paragraphs.enumerated() {
                        let stripped = paraHTML
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if stripped.contains(needle) || needle.contains(stripped) {
                            let flatIndex = decoded.flatIndex(chapterIndex: ci, paragraphIndex: pi)
                            resolvedTargetScrollID = "para-\(flatIndex)"
                            resolvedHighlightFlatIndex = flatIndex
                            found = true
                            break outer
                        }
                    }
                }
            }
            // Fallback: stored indices
            if !found, let ci = targetChapterIndex, let pi = targetParagraphIndex {
                let flatIndex = decoded.flatIndex(chapterIndex: ci, paragraphIndex: pi)
                resolvedTargetScrollID = "para-\(flatIndex)"
                resolvedHighlightFlatIndex = flatIndex
            }
        }

        await MainActor.run {
            content = decoded
            readerItems = items
            totalParagraphs = decoded.totalParagraphs
            serverScrollFraction = progressFraction
            targetScrollID = resolvedTargetScrollID
            highlightFlatIndex = resolvedHighlightFlatIndex
            isLoading = false
        }
    }
}

// MARK: - Paragraph view

private struct ParagraphView: View {
    let text: String
    let isHighlighted: Bool
    let cachedAttr: AttributedString?
    let baseFont: Font
    let textColor: Color
    let fontSize: Double
    let lineSpacing: Double

    var body: some View {
        Text(cachedAttr ?? styledAttributedString(html: text, baseFont: baseFont, color: textColor))
            .lineSpacing(CGFloat(fontSize * max(0, lineSpacing - 1.2) * 0.7))
            .background(
                isHighlighted ? Color.yellow.opacity(0.35) : Color.clear,
                in: RoundedRectangle(cornerRadius: 3)
            )
            .padding(.bottom, CGFloat(fontSize * lineSpacing * 0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Inline HTML rendering (file-scope so ParagraphView and HTMLReaderView can both use it)

private func styledAttributedString(html: String, baseFont: Font, color: Color) -> AttributedString {
    guard html.contains("<") else {
        var str = AttributedString(decodeHTMLEntities(html))
        str.font = baseFont
        str.foregroundColor = color
        return str
    }

    var result = AttributedString()
    var boldDepth = 0
    var italicDepth = 0
    var underlineDepth = 0
    var cursor = html.startIndex

    while cursor < html.endIndex {
        if html[cursor] == "<" {
            guard let tagEnd = html[cursor...].firstIndex(of: ">") else {
                appendRun(decodeHTMLEntities(String(html[cursor...])), bold: boldDepth > 0, italic: italicDepth > 0, underline: underlineDepth > 0, baseFont: baseFont, color: color, into: &result)
                break
            }
            let inner = String(html[html.index(after: cursor)..<tagEnd]).trimmingCharacters(in: .whitespaces)
            cursor = html.index(after: tagEnd)

            let closing = inner.hasPrefix("/")
            var raw = closing ? String(inner.dropFirst()) : inner
            raw = (raw.components(separatedBy: .whitespaces).first ?? raw)
            raw = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            let tag = raw.lowercased()

            switch tag {
            case "b", "strong": boldDepth      += closing ? -1 : 1
            case "em", "i":     italicDepth    += closing ? -1 : 1
            case "u":           underlineDepth += closing ? -1 : 1
            case "br":          appendRun("\n", bold: false, italic: false, underline: false, baseFont: baseFont, color: color, into: &result)
            default:            break
            }
        } else {
            let textEnd = html[cursor...].firstIndex(of: "<") ?? html.endIndex
            let text = decodeHTMLEntities(String(html[cursor..<textEnd]))
            cursor = textEnd
            if !text.isEmpty {
                appendRun(text, bold: boldDepth > 0, italic: italicDepth > 0, underline: underlineDepth > 0, baseFont: baseFont, color: color, into: &result)
            }
        }
    }

    return result
}

private func appendRun(_ text: String, bold: Bool, italic: Bool, underline: Bool, baseFont: Font, color: Color, into result: inout AttributedString) {
    var str = AttributedString(text)
    switch (bold, italic) {
    case (true, true):  str.font = baseFont.bold().italic()
    case (true, false): str.font = baseFont.bold()
    case (false, true): str.font = baseFont.italic()
    default:            str.font = baseFont
    }
    str.foregroundColor = color
    if underline { str.underlineStyle = Text.LineStyle(pattern: .solid) }
    result += str
}

private func decodeHTMLEntities(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&amp;",  with: "&")
        .replacingOccurrences(of: "&lt;",   with: "<")
        .replacingOccurrences(of: "&gt;",   with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;",  with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
}

// MARK: - Settings sheet

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var hPadding: Double
    @Binding var fontKey: String
    @Binding var colorThemeRaw: String

    private let fonts: [(key: String, label: String, sample: String)] = [
        ("system",      "System",      "System"),
        ("newYork",     "New York",    "New York"),
        ("georgia",     "Georgia",     "Georgia"),
        ("baskerville", "Baskerville", "Baskerville"),
        ("didot",       "Didot",       "Didot"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    themePicker
                }

                Section("Font") {
                    fontPicker

                    LabeledSlider(
                        label: "Size",
                        value: $fontSize,
                        range: 12...26,
                        step: 1,
                        display: "\(Int(fontSize))pt"
                    )
                }

                Section("Layout") {
                    LabeledSlider(
                        label: "Line Spacing",
                        value: $lineSpacing,
                        range: 1.2...2.5,
                        step: 0.1,
                        display: String(format: "%.1f×", lineSpacing)
                    )
                    LabeledSlider(
                        label: "Margins",
                        value: $hPadding,
                        range: 8...60,
                        step: 4,
                        display: marginLabel
                    )
                }

                Section("Preview") {
                    Text("The story unfolded slowly, each sentence a quiet revelation. She had not expected to find beauty in these pages, yet here it was — patient and unhurried.")
                        .font(previewFont)
                        .lineSpacing(CGFloat(fontSize * max(0, lineSpacing - 1.2) * 0.7))
                        .padding(.vertical, 6)
                }
            }
            .navigationTitle("Reading Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Theme picker (color swatches)

    private var themePicker: some View {
        HStack(spacing: 0) {
            ForEach(ReaderTheme.allCases, id: \.self) { t in
                let isSelected = colorThemeRaw == t.rawValue

                Button {
                    colorThemeRaw = t.rawValue
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(t.background)
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(t.isDark ? .white : .black)
                            }
                        }
                        Text(t.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Font picker (menu with live samples)

    private var fontPicker: some View {
        Picker("Font", selection: $fontKey) {
            ForEach(fonts, id: \.key) { f in
                Text(f.label).tag(f.key)
            }
        }
        .pickerStyle(.menu)
    }

    private var marginLabel: String {
        switch Int(hPadding) {
        case ..<16: return "Narrow"
        case ..<32: return "Normal"
        case ..<48: return "Wide"
        default:    return "Very Wide"
        }
    }

    private var previewFont: Font {
        let size = CGFloat(fontSize)
        switch fontKey {
        case "newYork":     return .system(size: size, design: .serif)
        case "georgia":     return .custom("Georgia",     size: size)
        case "baskerville": return .custom("Baskerville", size: size)
        case "didot":       return .custom("Didot",       size: size)
        default:            return .system(size: size)
        }
    }
}

// MARK: - Shared slider component

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(display)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - Save quote sheet

struct SaveQuoteSheet: View {
    let text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var cleanText: String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\u{201C}")
                    .font(.system(size: 72, weight: .bold, design: .serif))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, -28)

                ScrollView {
                    Text(cleanText)
                        .font(.body)
                        .italic()
                        .lineSpacing(5)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)

}
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            VStack(spacing: 8) {
                Button {
                    onSave()
                    dismiss()
                } label: {
                    Text("Save Quote")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Hex color convenience

private extension Color {
    init(readerHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
