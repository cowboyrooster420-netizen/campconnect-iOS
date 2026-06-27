import Foundation

// MARK: - Enums

enum UserRole: String, Codable, Sendable {
    case camper, counselor, operator_ = "operator", parent
}

enum ChallengeCategory: String, Codable, CaseIterable, Sendable {
    case outdoor, creative, reflection, tradition

    var displayName: String {
        switch self {
        case .outdoor: return "Outdoor"
        case .creative: return "Creative"
        case .reflection: return "Reflection"
        case .tradition: return "Tradition"
        }
    }

    /// SF Symbol used on cards and chips.
    var icon: String {
        switch self {
        case .outdoor: return "leaf.fill"
        case .creative: return "paintbrush.fill"
        case .reflection: return "book.fill"
        case .tradition: return "flame.fill"
        }
    }
}

enum SubmissionFormat: String, Codable, Sendable {
    case photo, video, text

    var prompt: String {
        switch self {
        case .photo: return "Add a photo"
        case .video: return "Record a video"
        case .text: return "Write your response"
        }
    }
}

enum SubmissionStatus: String, Codable, Sendable {
    case pending, approved, rejected
}

enum SeasonChallengeStatus: String, Codable, Sendable {
    case scheduled, active, closed
}

// MARK: - Camp

struct Camp: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let logoURL: String?
    let primaryColor: String?
    let seasonYear: Int

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case logoURL = "logo_url"
        case primaryColor = "primary_color"
        case seasonYear = "season_year"
    }
}

// MARK: - Profile

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var campID: UUID?
    var role: UserRole
    var displayName: String
    var cabin: String?
    var avatarURL: String?
    var totalPoints: Int

    enum CodingKeys: String, CodingKey {
        case id, role, cabin
        case campID = "camp_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case totalPoints = "total_points"
    }
}

// MARK: - Challenge template (shared library)

struct ChallengeTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let category: ChallengeCategory
    let instructions: String
    let counselorScript: String
    let submissionFormat: SubmissionFormat
    let points: Int

    enum CodingKeys: String, CodingKey {
        case id, title, summary, category, instructions, points
        case counselorScript = "counselor_script"
        case submissionFormat = "submission_format"
    }
}

// MARK: - Season challenge (a camp's run of a template)

/// Decoded with the embedded template via PostgREST resource embedding:
/// `select=*,template:challenge_templates(*)`
struct SeasonChallenge: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let campID: UUID
    let templateID: UUID
    let sequenceOrder: Int
    // Stored value is either a full external URL (http…) or a storage path in the
    // `counselor-videos` bucket. CampService resolves bare paths into signed URLs.
    var counselorVideoURL: String?
    let releaseAt: Date?
    let dueAt: Date?
    let status: SeasonChallengeStatus
    let template: ChallengeTemplate

    enum CodingKeys: String, CodingKey {
        case id, status, template
        case campID = "camp_id"
        case templateID = "template_id"
        case sequenceOrder = "sequence_order"
        case counselorVideoURL = "counselor_video_url"
        case releaseAt = "release_at"
        case dueAt = "due_at"
    }
}

// MARK: - Submission

struct Submission: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let seasonChallengeID: UUID
    let camperID: UUID
    let contentType: SubmissionFormat
    let mediaPath: String?
    let textContent: String?
    let status: SubmissionStatus
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case seasonChallengeID = "season_challenge_id"
        case camperID = "camper_id"
        case contentType = "content_type"
        case mediaPath = "media_path"
        case textContent = "text_content"
        case createdAt = "created_at"
    }
}

/// Payload used when inserting a new submission.
struct NewSubmission: Encodable, Sendable {
    let seasonChallengeID: UUID
    let camperID: UUID
    let contentType: SubmissionFormat
    let mediaPath: String?
    let textContent: String?

    enum CodingKeys: String, CodingKey {
        case seasonChallengeID = "season_challenge_id"
        case camperID = "camper_id"
        case contentType = "content_type"
        case mediaPath = "media_path"
        case textContent = "text_content"
    }
}

// MARK: - Badges

struct Badge: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let campID: UUID?
    let name: String
    let description: String
    let icon: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon
        case campID = "camp_id"
    }
}

/// A badge joined with whether the current camper has earned it.
struct EarnedBadge: Codable, Identifiable, Hashable, Sendable {
    let badge: Badge
    let awardedAt: Date?

    var id: UUID { badge.id }
    var isEarned: Bool { awardedAt != nil }
}
