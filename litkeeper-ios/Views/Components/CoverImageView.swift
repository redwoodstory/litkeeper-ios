import SwiftUI

private enum ImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return cache
    }()
}

struct CoverImageView: View {
    let url: URL?
    var fallbackURL: URL? = nil
    let title: String
    let author: String
    var token: String = ""
    var proxyTokenId: String = ""
    var proxyToken: String = ""

    @State private var loadedImage: UIImage? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if isLoading {
                    SkeletonShape()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    placeholderView(size: geo.size)
                }
            }
        }
        .task(id: url) {
            // Don't wipe loadedImage before the new one arrives — keeps the existing
            // cover visible while reloading (avoids flash to skeleton/placeholder).
            if url == nil { loadedImage = nil }
            isLoading = url != nil
            await loadImage()
            isLoading = false
        }
    }

    private func loadImage() async {
        guard let url else { return }
        print("[LK-IMG] → \(url.lastPathComponent)")

        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                print("[LK-IMG] ← \(url.lastPathComponent) (local, \(data.count)B)")
                loadedImage = img
                return
            }
            // Local file unreadable or not a valid image — delete it so it gets re-downloaded
            print("[LK-IMG] ✗ Could not read local file \(url.lastPathComponent) — removing corrupt file")
            try? FileManager.default.removeItem(at: url)
            if let fallback = fallbackURL {
                await loadRemote(url: fallback)
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
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        }
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
        guard let img = UIImage(data: data) else {
            print("[LK-IMG] ✗ Invalid image data for \(url.lastPathComponent) (\(data.count)B)")
            return
        }
        ImageCache.shared.setObject(img, forKey: cacheKey, cost: data.count)
        print("[LK-IMG] ← \(url.lastPathComponent) (\(data.count)B)")
        loadedImage = img
    }

    @ViewBuilder
    private func placeholderView(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [coverColor.opacity(0.8), coverColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 4) {
                Text("📖")
                    .font(.system(size: min(size.width, size.height) * 0.28))
                Text(title)
                    .font(.system(size: min(size.width * 0.14, 11), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var coverColor: Color {
        let hash = abs(title.hashValue)
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .cyan, .mint, .green, .orange]
        return colors[hash % colors.count]
    }
}
