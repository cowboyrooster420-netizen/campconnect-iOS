import SwiftUI

/// A pill chip showing a challenge category with its icon + color.
struct CategoryChip: View {
    let category: ChallengeCategory

    var body: some View {
        Label(category.displayName, systemImage: category.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.categoryColor(category).opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.categoryColor(category))
    }
}

/// A status badge for whether a challenge submission exists / its review state.
struct StatusTag: View {
    let status: SubmissionStatus?

    var body: some View {
        let (text, color, icon): (String, Color, String) = {
            switch status {
            case .none:        return ("Not started", .secondary, "circle")
            case .pending:     return ("In review", Theme.sunset, "clock.fill")
            case .approved:    return ("Completed", Theme.accent, "checkmark.seal.fill")
            case .rejected:    return ("Try again", .red, "arrow.counterclockwise")
            }
        }()
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

/// Primary call-to-action button used across the app.
struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(isLoading)
    }
}

/// Empty/loading/error container used by list screens.
struct StateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Theme.accentSoft)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
