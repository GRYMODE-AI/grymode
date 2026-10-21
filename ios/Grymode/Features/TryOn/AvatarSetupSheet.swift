import PhotosUI
import SwiftUI
import UIKit

/// Lets signed-in users finish their fit profile from Home before trying on a look.
struct AvatarSetupSheet: View {
    @Bindable var avatar: AvatarModel
    var onReady: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var facePreview: UIImage?

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(accessibilityIdentifier: "screen.avatarSetupSheet") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.lg) {
                    GMSectionHeader(
                        overline: "Personal try-on",
                        title: "Finish your fit profile",
                        message:
                            "Add height, body build, and a clear face photo. Grymode keeps these private and uses them to show each look on you from every angle."
                    )

                    VStack(alignment: .leading, spacing: GMSpacing.sm) {
                        Text("Height · \(avatar.draftHeightCm) cm")
                            .gmTextStyle(.callout)
                        Slider(
                            value: Binding(
                                get: { Double(avatar.draftHeightCm) },
                                set: { avatar.draftHeightCm = Int($0.rounded()) }
                            ),
                            in: 140...210,
                            step: 1
                        )
                        .tint(GMColor.accent)
                    }

                    HStack(spacing: GMSpacing.sm) {
                        ForEach(BodyBuild.allCases) { build in
                            GMChoiceChip(
                                title: build.title,
                                isSelected: avatar.draftBuild == build,
                                expands: true
                            ) {
                                avatar.draftBuild = build
                            }
                        }
                    }

                    HStack(spacing: GMSpacing.md) {
                        Circle()
                            .fill(GMColor.surfaceSunken)
                            .frame(width: 72, height: 72)
                            .overlay {
                                if let facePreview {
                                    Image(uiImage: facePreview).resizable().scaledToFill()
                                } else if let url = avatar.profile?.faceURL {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        }
                                    }
                                } else {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(GMColor.textSecondary)
                                }
                            }
                            .clipShape(Circle())

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text(facePreview == nil && avatar.profile?.hasFace != true ? "Add face photo" : "Replace photo")
                        }
                        .buttonStyle(.gmSecondary)
                    }

                    if let error = avatar.actionError {
                        GMInlineError(error: error)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GMBottomActionBar {
                    Button {
                        Task { await save() }
                    } label: {
                        GMProgressLabel(title: "Save and continue", isWorking: avatar.isSaving)
                    }
                    .buttonStyle(.gmPrimary)
                    .disabled(avatar.isSaving)
                    .accessibilityIdentifier("avatarSheet.save")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadFace(item) }
        }
    }

    private func loadFace(_ item: PhotosPickerItem) async {
        do {
            guard let transfer = try await item.loadTransferable(type: PhotoDataTransfer.self) else { return }
            let jpeg = try WardrobeImageEncoder.jpegData(from: transfer.data)
            facePreview = UIImage(data: jpeg)
            guard await avatar.saveMeasurements() else { return }
            _ = await avatar.uploadFaceJPEG(jpeg)
        } catch {
            avatar.presentError((error as? AppError) ?? .unexpected)
        }
    }

    private func save() async {
        guard await avatar.saveMeasurements() else { return }
        if let preview = facePreview, let data = preview.jpegData(compressionQuality: 0.9) {
            let jpeg = (try? WardrobeImageEncoder.jpegData(from: data)) ?? data
            guard await avatar.uploadFaceJPEG(jpeg) else { return }
        }
        if avatar.isReadyForTryOn {
            onReady()
            dismiss()
        } else {
            avatar.presentError(.configuration("Add a clear face photo to continue."))
        }
    }
}
