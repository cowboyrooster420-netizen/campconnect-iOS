import SwiftUI
import AVKit
import PhotosUI

struct ChallengeDetailView: View {
    let challenge: SeasonChallenge
    let existing: Submission?
    /// Called after a successful submission so the list can refresh.
    let onSubmitted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSubmit = false

    private var template: ChallengeTemplate { challenge.template }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                counselorVideo

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CategoryChip(category: template.category)
                        Spacer()
                        Text("\(template.points) pts")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(template.title).font(.title.bold()).foregroundStyle(Theme.ink)
                    Text(template.summary).font(.body).foregroundStyle(.secondary)
                }

                section(title: "From your counselor", icon: "quote.bubble.fill") {
                    Text(template.counselorScript)
                        .font(.body)
                        .italic()
                        .foregroundStyle(Theme.ink)
                }

                section(title: "Your challenge", icon: "list.bullet.clipboard.fill") {
                    Text(template.instructions).font(.body).foregroundStyle(Theme.ink)
                }

                submitSection
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.sand.ignoresSafeArea())
        .navigationTitle(template.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSubmit) {
            SubmissionSheet(challenge: challenge) {
                await onSubmitted()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var counselorVideo: some View {
        if let urlString = challenge.counselorVideoURL, let url = URL(string: urlString) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(Theme.accent.opacity(0.12))
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    Text("Counselor video coming soon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        if let existing {
            VStack(alignment: .leading, spacing: 8) {
                StatusTag(status: existing.status)
                if existing.status == .rejected {
                    PrimaryButton(title: "Submit again") { showSubmit = true }
                }
            }
        } else {
            PrimaryButton(title: template.submissionFormat.prompt) { showSubmit = true }
        }
    }

    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}
