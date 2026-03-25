import SwiftUI

struct HighlightRow: View {
    let highlight: Highlight

    private var relativeDate: String? {
        guard let raw = highlight.createdAt else { return nil }
        let date = Self.parseDate(raw)
        guard let date else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { let m = Int(seconds / 60); return "\(m) minute\(m == 1 ? "" : "s") ago" }
        if seconds < 86400 { let h = Int(seconds / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if seconds < 604800 { let d = Int(seconds / 86400); return "\(d) day\(d == 1 ? "" : "s") ago" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        // Try with fractional seconds + timezone
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        // Try without fractional seconds
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: raw) { return d }
        // Python isoformat() with no timezone, with microseconds
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = f3.date(from: raw) { return d }
        // Without microseconds
        let f4 = DateFormatter()
        f4.locale = Locale(identifier: "en_US_POSIX")
        f4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f4.date(from: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text(highlight.quoteText)
                    .font(.body)
                    .italic()
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.storyTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("by \(highlight.storyAuthor)\(relativeDate.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 24)
        }
        .padding(.vertical, 4)
    }
}
