import SwiftUI

private enum ImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return cache
    }()

    static func cachedImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return shared.object(forKey: url.absoluteString as NSString)
    }
}

struct CoverImageView: View {
    let url: URL?
    var fallbackURL: URL? = nil
    let title: String
    let author: String
    var token: String = ""
    var proxyTokenId: String = ""
    var proxyToken: String = ""

    @State private var loadedImage: UIImage?
    @State private var isLoading: Bool

    init(url: URL?, fallbackURL: URL? = nil, title: String, author: String,
         token: String = "", proxyTokenId: String = "", proxyToken: String = "") {
        self.url = url
        self.fallbackURL = fallbackURL
        self.title = title
        self.author = author
        self.token = token
        self.proxyTokenId = proxyTokenId
        self.proxyToken = proxyToken
        // Seed state from cache so re-created cells never flash the skeleton.
        let cached = ImageCache.cachedImage(for: url)
        _loadedImage = State(initialValue: cached)
        _isLoading = State(initialValue: cached == nil && url != nil)
    }

    var body: some View {
        Color.clear
            .overlay {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    SkeletonShape()
                } else {
                    placeholderView
                }
            }
            .clipped()
            .task(id: url) {
                guard loadedImage == nil else { return }
                if url == nil { isLoading = false; return }
                await loadImage()
                isLoading = false
            }
    }

    private func loadImage() async {
        guard let url else { return }
        print("[LK-IMG] → \(url.lastPathComponent)")

        if url.isFileURL {
            let cacheKey = url.absoluteString as NSString
            if let cached = ImageCache.shared.object(forKey: cacheKey) {
                loadedImage = cached
                return
            }
            // Read and decode off the main thread — Data(contentsOf:) is blocking I/O
            let result = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return (nil as UIImage?, 0) }
                return (UIImage(data: data), data.count)
            }.value
            if let img = result.0 {
                print("[LK-IMG] ← \(url.lastPathComponent) (local, \(result.1)B)")
                ImageCache.shared.setObject(img, forKey: cacheKey, cost: result.1)
                loadedImage = img
            } else {
                print("[LK-IMG] ✗ Could not read local file \(url.lastPathComponent) — removing corrupt file")
                try? FileManager.default.removeItem(at: url)
                if let fallback = fallbackURL {
                    await loadRemote(url: fallback)
                }
            }
            return
        }

        await loadRemote(url: url)
    }

    private func loadRemote(url: URL) async {
        let cacheKey = url.absoluteString as NSString
        if let cached = ImageCache.shared.object(forKey: cacheKey) {
            loadedImage = cached
            return
        }

        var request = URLRequest(url: url)
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Api-Key") }
        if !proxyTokenId.isEmpty { request.setValue(proxyTokenId, forHTTPHeaderField: "P-Access-Token-Id") }
        if !proxyToken.isEmpty { request.setValue(proxyToken, forHTTPHeaderField: "P-Access-Token") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            print("[LK-IMG] ✗ No response for \(url.lastPathComponent)")
            return
        }
        guard http.statusCode == 200 else {
            print("[LK-IMG] ✗ HTTP \(http.statusCode) for \(url.lastPathComponent)")
            return
        }
        // Decode off the main thread — UIImage(data:) for large JPEGs can take 50-150ms
        let decoded = await Task.detached(priority: .userInitiated) {
            UIImage(data: data).map { ($0, data.count) }
        }.value
        guard let (img, cost) = decoded else {
            print("[LK-IMG] ✗ Invalid image data for \(url.lastPathComponent) (\(data.count)B)")
            return
        }
        ImageCache.shared.setObject(img, forKey: cacheKey, cost: cost)
        print("[LK-IMG] ← \(url.lastPathComponent) (\(cost)B)")
        loadedImage = img
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [coverColor.opacity(0.8), coverColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 4) {
                Text("📖")
                    .font(.system(size: 32))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var coverColor: Color {
        let hash = abs(title.hashValue)
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .cyan, .mint, .green, .orange]
        return colors[hash % colors.count]
    }
}
