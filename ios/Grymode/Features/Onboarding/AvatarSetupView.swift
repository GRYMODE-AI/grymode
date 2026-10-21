import PhotosUI
import SwiftUI
import UIKit

/// Captures height, body build, and a private face photo for personal try-on previews.
struct AvatarSetupView: View {
    @Bindable var model: OnboardingModel
    @State private var avatar: AvatarModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var facePreview: UIImage?

    init(model: OnboardingModel) {
        self.model = model
        _avatar = State(initialValue: AvatarModel(api: nil))
    }

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.avatarSetup") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: "Personal try-on",
                    title: "Your fit profile",
                    message:
                        "Height, body build, and a clear face photo power your personal try-on, so you can turn each look on yourself from every angle. Photos stay private."
                )

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Text("Height · \(avatar.draftHeightCm) cm")
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                    Slider(
                        value: Binding(
                            get: { Double(avatar.draftHeightCm) },
                            set: { avatar.draftHeightCm = Int($0.rounded()) }
                        ),
                        in: 140...210,
                        step: 1
                    )
                    .tint(GMColor.accent)
                    .accessibilityIdentifier("avatar.height")
                }

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Text("Body build")
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
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
                }

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Text("Face photo")
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                    HStack(spacing: GMSpacing.md) {
                        facePreviewTile
                        PhotosPicker(
                            facePreview == nil ? "Choose photo" : "Replace photo",
                            selection: $pickerItem,
                            matching: .images
                        )
                        .buttonStyle(.gmSecondary)
                        .accessibilityIdentifier("avatar.facePicker")
                    }
                    Text("Use a well-lit front-facing photo. Avoid sunglasses and heavy filters.")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                }

                if let error = avatar.actionError ?? model.finishError {
                    GMInlineError(error: error)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                Button {
                    Task { await continueOnboarding() }
                } label: {
                    GMProgressLabel(title: "Continue", isWorking: avatar.isSaving || model.isFinishing)
                }
                .buttonStyle(.gmPrimary)
                .disabled(avatar.isSaving || model.isFinishing || !canContinue)
                .accessibilityIdentifier("avatar.continue")

                Button("Skip for now") {
                    model.showResult()
                }
                .buttonStyle(.gmTertiary)
                .disabled(avatar.isSaving || model.isFinishing)
                .accessibilityIdentifier("avatar.skip")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            avatar.bind(api: model.accountAPIClient)
            await avatar.refresh()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicker(item) }
        }
    }

    private var canContinue: Bool {
        facePreview != nil || model.pendingFaceJPEG != nil || avatar.profile?.hasFace == true
    }

    private var facePreviewTile: some View {
        Circle()
            .fill(GMColor.surfaceSunken)
            .frame(width: 88, height: 88)
            .overlay {
                if let facePreview {
                    Image(uiImage: facePreview)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(GMColor.textSecondary)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(GMColor.border, lineWidth: GMBorder.hairline))
    }

    private func loadPicker(_ item: PhotosPickerItem) async {
        do {
            guard let transfer = try await item.loadTransferable(type: PhotoDataTransfer.self) else { return }
            let encoded = try WardrobeImageEncoder.jpegData(from: transfer.data)
            facePreview = UIImage(data: encoded)
            model.pendingFaceJPEG = encoded
            model.pendingHeightCm = avatar.draftHeightCm
            model.pendingBodyBuild = avatar.draftBuild
        } catch {
            avatar.presentError((error as? AppError) ?? .unexpected)
        }
    }

    private func continueOnboarding() async {
        model.pendingHeightCm = avatar.draftHeightCm
        model.pendingBodyBuild = avatar.draftBuild
        if model.isSignedIn {
            avatar.draftHeightCm = model.pendingHeightCm ?? avatar.draftHeightCm
            avatar.draftBuild = model.pendingBodyBuild ?? avatar.draftBuild
            guard await avatar.saveMeasurements() else { return }
            if let jpeg = model.pendingFaceJPEG {
                guard await avatar.uploadFaceJPEG(jpeg) else { return }
            }
        }
        model.showResult()
    }
}
