import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    greeting

                    if model.isLoading && model.challenges.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if model.challenges.isEmpty {
                        StateView(
                            systemImage: "flag.checkered",
                            title: "No active challenges",
                            message: "Your camp hasn't released a challenge yet. Check back soon!"
                        )
                    } else {
                        ForEach(model.challenges) { challenge in
                            NavigationLink(value: challenge) {
                                ChallengeCard(
                                    challenge: challenge,
                                    status: model.status(for: challenge)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.sand.ignoresSafeArea())
            .navigationTitle("Challenges")
            .navigationDestination(for: SeasonChallenge.self) { challenge in
                ChallengeDetailView(
                    challenge: challenge,
                    existing: model.submissionByChallenge[challenge.id]
                ) { await model.load() }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hi \(session.profile?.displayName ?? "Camper")!")
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            if let camp = session.camp {
                Text("\(camp.name) • \(model.completedCount) completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A single challenge card in the list.
struct ChallengeCard: View {
    let challenge: SeasonChallenge
    let status: SubmissionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryChip(category: challenge.template.category)
                Spacer()
                Text("\(challenge.template.points) pts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(challenge.template.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text(challenge.template.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                StatusTag(status: status)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}
