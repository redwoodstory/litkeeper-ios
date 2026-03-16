import SwiftUI

struct RatingView: View {
    let rating: Int?
    let onRate: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onRate(star == rating ? 0 : star)  // tap same star to clear
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (rating ?? 0) ? .yellow : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
