import SwiftUI

/// Centralized look & feel. Warm, outdoorsy, identity-forward — not a social app.
enum Theme {
    static let accent = Color(hex: "2E7D5B")      // pine green
    static let accentSoft = Color(hex: "5FA77F")
    static let sand = Color(hex: "F4EFE6")
    static let ink = Color(hex: "27332E")
    static let sunset = Color(hex: "E08A3C")

    static let cardCorner: CGFloat = 18
    static let screenPadding: CGFloat = 20

    static func categoryColor(_ category: ChallengeCategory) -> Color {
        switch category {
        case .outdoor: return accent
        case .creative: return Color(hex: "8E5BB5")
        case .reflection: return Color(hex: "3C7CE0")
        case .tradition: return sunset
        }
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
