import SwiftUI

@MainActor
final class BadgesViewModel: ObservableObject {
    @Published var badges: [EarnedBadge] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            badges = try await CampService.shared.fetchBadges()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var earnedCount: Int { badges.filter { $0.isEarned }.count }
}

struct BadgesView: View {
    @StateObject private var model = BadgesViewModel()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(model.earnedCount) of \(model.badges.count) earned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if model.badges.isEmpty && !model.isLoading {
                        StateView(
                            systemImage: "rosette",
                            title: "No badges yet",
                            message: "Complete challenges to start earning badges."
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(model.badges) { BadgeTile(earned: $0) }
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.sand.ignoresSafeArea())
            .navigationTitle("Badges")
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }
}

struct BadgeTile: View {
    let earned: EarnedBadge

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: earned.badge.icon)
                .font(.system(size: 36))
                .foregroundStyle(earned.isEarned ? Theme.sunset : Color.secondary.opacity(0.4))
                .frame(height: 44)
            Text(earned.badge.name)
                .font(.subheadline.bold())
                .foregroundStyle(earned.isEarned ? Theme.ink : .secondary)
                .multilineTextAlignment(.center)
            Text(earned.badge.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .opacity(earned.isEarned ? 1 : 0.7)
        .overlay(alignment: .topTrailing) {
            if earned.isEarned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
                    .padding(10)
            }
        }
    }
}
