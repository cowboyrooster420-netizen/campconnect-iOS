import SwiftUI
import PhotosUI

/// Capture/select the camper's submission for one challenge and upload it.
struct SubmissionSheet: View {
    let challenge: SeasonChallenge
    let onSuccess: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var mediaData: Data?
    @State private var previewImage: Image?
    @State private var fileExtension: String?
    @State private var isSubmitting = false
    @State private var error: String?

    private var format: SubmissionFormat { challenge.template.submissionFormat }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(challenge.template.title).font(.title3.bold())

                    switch format {
                    case .text:
                        textEditor
                    case .photo, .video:
                        mediaPicker
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    PrimaryButton(title: "Submit", isLoading: isSubmitting) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.sand.ignoresSafeArea())
            .navigationTitle("New submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Write your response").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 180)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var mediaPicker: some View {
        VStack(spacing: 12) {
            if let previewImage {
                previewImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if mediaData != nil {
                Label("Video selected", systemImage: "video.fill")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }

            PhotosPicker(
                selection: $pickerItem,
                matching: format == .video ? .videos : .images
            ) {
                Label(
                    mediaData == nil ? format.prompt : "Choose a different file",
                    systemImage: format == .video ? "video.badge.plus" : "photo.badge.plus"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadMedia(newItem) }
            }
        }
    }

    private var canSubmit: Bool {
        switch format {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo, .video: return mediaData != nil
        }
    }

    private func loadMedia(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            mediaData = data
            fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
                ?? (format == .video ? "mov" : "jpg")
            if format == .photo, let uiImage = UIImage(data: data) {
                previewImage = Image(uiImage: uiImage)
            }
        } catch {
            self.error = "Couldn't load that file. Try another."
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await CampService.shared.submit(
                challenge: challenge,
                text: format == .text ? text : nil,
                media: mediaData,
                fileExtension: fileExtension
            )
            await onSuccess()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
