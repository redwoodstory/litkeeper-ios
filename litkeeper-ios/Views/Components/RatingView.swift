import SwiftUI

struct RatingView: View {
    let rating: Int?
    let onRate: (Int) -> Void

    @State private var tappedStar: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let isClear = star == rating
                    if isClear {
                        HapticManager.shared.selectionChanged()
                    } else {
                        HapticManager.shared.impact(.soft)
                    }
                    tappedStar = star
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        onRate(isClear ? 0 : star)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        tappedStar = nil
                    }
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (rating ?? 0) ? .yellow : .secondary)
                        .font(.title3)
                        .scaleEffect(tappedStar == star ? 1.35 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: tappedStar)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
