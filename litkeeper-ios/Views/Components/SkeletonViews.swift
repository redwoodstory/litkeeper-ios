import SwiftUI

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.45), location: 0.4),
                            .init(color: .clear, location: 0.7),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2.5)
                    .offset(x: phase * geo.size.width * 2.5 - geo.size.width * 0.75)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Building block

struct SkeletonShape: View {
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.15))
            .shimmer()
    }
}

// MARK: - Library skeleton

struct LibrarySkeletonView: View {
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    SkeletonShape(cornerRadius: 8)
                        .aspectRatio(2/3, contentMode: .fit)
                }
            }
            .padding()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reading Queue skeleton

struct ReadingQueueSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    SkeletonShape(cornerRadius: 8)
                        .frame(width: 60, height: 90)

                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonShape(cornerRadius: 4)
                            .frame(height: 14)
                        SkeletonShape(cornerRadius: 4)
                            .frame(width: 140, height: 12)
                        SkeletonShape(cornerRadius: 4)
                            .frame(height: 8)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
    }
}

// MARK: - Queue / History skeleton

struct QueueSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonShape(cornerRadius: 4)
                        .frame(height: 13)

                    Spacer()

                    SkeletonShape(cornerRadius: 4)
                        .frame(width: 20, height: 20)
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
    }
}
