import SwiftUI

struct RateStoryModalView: View {
    let story: Story
    @Binding var isPresented: Bool
    let onRatingChanged: (Int?) -> Void

    @State private var currentRating: Int?

    init(story: Story, isPresented: Binding<Bool>, onRatingChanged: @escaping (Int?) -> Void) {
        self.story = story
        self._isPresented = isPresented
        self.onRatingChanged = onRatingChanged
        _currentRating = State(initialValue: story.rating)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            card
                .padding(.horizontal, 28)
        }
    }

    private var card: some View {
        VStack(spacing: 20) {
            Text("Rate this story")
                .font(.title3.bold())
                .padding(.top, 28)

            RatingView(rating: currentRating) { newRating in
                let value = newRating == 0 ? nil : Optional(newRating)
                currentRating = value
                onRatingChanged(value)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    await MainActor.run { isPresented = false }
                }
            }
            .font(.system(size: 36))
            .padding(.bottom, 28)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: 8)
        .padding(.horizontal, 4)
    }
}
