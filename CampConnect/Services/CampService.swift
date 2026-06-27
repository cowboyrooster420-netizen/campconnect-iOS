import Foundation
import Supabase

/// All Postgres/storage reads + writes for the camper experience.
/// Operator-side mutations (scheduling challenges, approving submissions, awarding
/// badges) are intentionally out of scope for this MVP scaffold — they live behind
/// the operator role and will get their own service.
struct CampService {
    static let shared = CampService()

    private var db: PostgrestClient { SupabaseManager.shared.db }
    private var storage: SupabaseStorageClient { SupabaseManager.shared.storage }

    // MARK: - Profile & camp

    func fetchMyProfile() async throws -> Profile {
        let userID = try await SupabaseManager.shared.auth.session.user.id
        return try await db
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    func fetchCamp(id: UUID) async throws -> Camp {
        try await db
            .from("camps")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Challenges

    /// Active (released) challenges for the camper's camp, in the camp's sequence.
    func fetchActiveChallenges() async throws -> [SeasonChallenge] {
        try await db
            .from("season_challenges")
            .select("*, template:challenge_templates(*)")
            .eq("status", value: SeasonChallengeStatus.active.rawValue)
            .order("sequence_order", ascending: true)
            .execute()
            .value
    }

    // MARK: - Submissions

    /// The current camper's submissions, keyed for quick "already done?" lookups.
    func fetchMySubmissions() async throws -> [Submission] {
        let userID = try await SupabaseManager.shared.auth.session.user.id
        return try await db
            .from("submissions")
            .select()
            .eq("camper_id", value: userID)
            .execute()
            .value
    }

    /// Upload optional media to the `submissions` bucket, then insert the row.
    func submit(
        challenge: SeasonChallenge,
        text: String?,
        media: Data?,
        fileExtension: String?
    ) async throws -> Submission {
        let userID = try await SupabaseManager.shared.auth.session.user.id

        var mediaPath: String?
        if let media, let fileExtension {
            let path = "\(userID.uuidString)/\(challenge.id.uuidString).\(fileExtension)"
            try await storage
                .from("submissions")
                .upload(path, data: media, options: FileOptions(upsert: true))
            mediaPath = path
        }

        let payload = NewSubmission(
            seasonChallengeID: challenge.id,
            camperID: userID,
            contentType: challenge.template.submissionFormat,
            mediaPath: mediaPath,
            textContent: text
        )

        return try await db
            .from("submissions")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Badges

    /// All badges available to the camper plus whether/when they earned each.
    func fetchBadges() async throws -> [EarnedBadge] {
        let badges: [Badge] = try await db
            .from("badges")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value

        let userID = try await SupabaseManager.shared.auth.session.user.id
        let awards: [BadgeAwardRow] = try await db
            .from("badge_awards")
            .select("badge_id, awarded_at")
            .eq("camper_id", value: userID)
            .execute()
            .value

        let awardedAt = Dictionary(uniqueKeysWithValues: awards.map { ($0.badgeID, $0.awardedAt) })
        return badges.map { EarnedBadge(badge: $0, awardedAt: awardedAt[$0.id] ?? nil) }
    }

    private struct BadgeAwardRow: Decodable {
        let badgeID: UUID
        let awardedAt: Date?
        enum CodingKeys: String, CodingKey {
            case badgeID = "badge_id"
            case awardedAt = "awarded_at"
        }
    }
}
