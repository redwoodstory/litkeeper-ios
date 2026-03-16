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

    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss
    @Environment(\.colorScheme)   private var systemColorScheme

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
    @State private var highWaterIndex: Int = 0

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

    // MARK: - Reader body

    @ViewBuilder
    private func readerBody(content: StoryContent) -> some View {
        let totalParas = content.totalParagraphs

        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        storyHeader(content: content)

                        ForEach(Array(content.chapters.enumerated()), id: \.offset) { ci, chapter in
                            chapterSection(
                                chapter: chapter,
                                chapterIndex: ci,
                                chapterStart: content.flatIndex(chapterIndex: ci, paragraphIndex: 0),
                                totalParas: totalParas,
                                isFirst: ci == 0
                            )
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, CGFloat(hPadding))
                    // Top padding keeps the first content clear of the controls bar
                    .padding(.top, 80)
                    .padding(.bottom, 20)
                }
                .background(theme.background)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }
                .onAppear {
                    let saved = localStory?.readingProgressScrollY ?? 0
                    guard saved > 0 else { return }
                    highWaterIndex = Int(saved * Double(max(totalParas - 1, 1)))
                    scrollProgress = saved
                    if let (ci, pi) = content.chapterAndParagraph(for: highWaterIndex) {
                        let id = "p-\(content.flatIndex(chapterIndex: ci, paragraphIndex: pi))"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
            }

            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .ignoresSafeArea(edges: .bottom)
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

    // MARK: - Chapter content

    @ViewBuilder
    private func chapterSection(
        chapter: StoryContent.Chapter,
        chapterIndex: Int,
        chapterStart: Int,
        totalParas: Int,
        isFirst: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                HStack {
                    Spacer()
                    Text("◆  ◆  ◆")
                        .font(.caption)
                        .foregroundStyle(theme.secondary.opacity(0.5))
                    Spacer()
                }
                .padding(.vertical, 36)
            }

            if let title = chapter.title, !title.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.text)
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1.5)
                }
                .padding(.bottom, 24)
            }

            ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { pi, text in
                paragraphView(text: text, flatIndex: chapterStart + pi, totalParas: totalParas)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(text: String, flatIndex: Int, totalParas: Int) -> some View {
        Text(text)
            .font(resolvedFont)
            .foregroundStyle(theme.text)
            // Line spacing: extra space between lines within a paragraph.
            // Scaling factor keeps it from growing too aggressively with larger font sizes.
            .lineSpacing(CGFloat(fontSize * max(0, lineSpacing - 1.2) * 0.7))
            // Paragraph spacing: notably larger than the per-line gap, matching CSS margin-bottom.
            .padding(.bottom, CGFloat(fontSize * lineSpacing * 0.6))
            .fixedSize(horizontal: false, vertical: true)
            .id("p-\(flatIndex)")
            .onAppear {
                guard flatIndex > highWaterIndex else { return }
                highWaterIndex = flatIndex
                let fraction = Double(flatIndex) / Double(max(totalParas - 1, 1))
                scrollProgress = fraction
                if let localStory {
                    localStory.readingProgressScrollY = fraction
                    localStory.readingProgressPercentage = fraction * 100
                    try? modelContext.save()
                }
            }
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Header bar
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

            Spacer()

            // Footer bar
            VStack(spacing: 4) {
                ProgressView(value: scrollProgress)
                Text("\(Int(scrollProgress * 100))%")
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

    // MARK: - Content loading

    private func loadContent() async {
        if let path = localStory?.htmlLocalPath {
            let fileURL = DownloadManager.shared.htmlDirectory.appendingPathComponent(path)
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(StoryContent.self, from: data)
                await MainActor.run { content = decoded; isLoading = false }
            } catch {
                await MainActor.run { loadError = "Could not load local file."; isLoading = false }
            }
            return
        }

        let base = appState.serverURL.hasSuffix("/")
            ? String(appState.serverURL.dropLast())
            : appState.serverURL
        guard let url = URL(string: "\(base)/download/\(story.filenameBase).json") else {
            await MainActor.run { loadError = "Invalid server URL."; isLoading = false }
            return
        }
        var request = URLRequest(url: url)
        if !appState.apiToken.isEmpty {
            request.setValue("Bearer \(appState.apiToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                await MainActor.run { loadError = "Server returned an error."; isLoading = false }
                return
            }
            let decoded = try JSONDecoder().decode(StoryContent.self, from: data)
            await MainActor.run { content = decoded; isLoading = false }
        } catch {
            await MainActor.run {
                loadError = "Could not load story: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
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
