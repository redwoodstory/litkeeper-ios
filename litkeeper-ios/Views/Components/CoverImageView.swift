import SwiftUI

struct CoverImageView: View {
    let url: URL?
    let title: String
    let author: String

    var body: some View {
        GeometryReader { geo in
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    case .failure, .empty:
                        placeholderView(size: geo.size)
                    @unknown default:
                        placeholderView(size: geo.size)
                    }
                }
            } else {
                placeholderView(size: geo.size)
            }
        }
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
        // Deterministic color from title
        let hash = abs(title.hashValue)
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .cyan, .mint, .green, .orange]
        return colors[hash % colors.count]
    }
}
