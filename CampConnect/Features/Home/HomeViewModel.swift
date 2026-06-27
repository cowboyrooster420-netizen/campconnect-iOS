import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var challenges: [SeasonChallenge] = []
    @Published var submissionByChallenge: [UUID: Submission] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let challenges = CampService.shared.fetchActiveChallenges()
            async let submissions = CampService.shared.fetchMySubmissions()
            self.challenges = try await challenges
            self.submissionByChallenge = Dictionary(
                uniqueKeysWithValues: try await submissions.map { ($0.seasonChallengeID, $0) }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func status(for challenge: SeasonChallenge) -> SubmissionStatus? {
        submissionByChallenge[challenge.id]?.status
    }

    var completedCount: Int {
        submissionByChallenge.values.filter { $0.status == .approved }.count
    }
}
