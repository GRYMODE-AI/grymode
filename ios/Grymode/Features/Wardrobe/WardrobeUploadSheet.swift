import PhotosUI
import SwiftUI

/// Explains the upload flow, then opens the system photo picker. Photos only for this pass.
struct WardrobeUploadSheet: View {
    @Bindable var model: WardrobeModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingSelection = false
    @State private var loadError: AppError?

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(accessibilityIdentifier: "screen.wardrobeUpload") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.xl) {
                    GMSectionHeader(
                        overline: "Add to wardrobe",
                        title: "Upload photos",
                        message:
                            "Choose clear photos of your clothes. Each upload becomes a draft piece for you to label — Grymode does not invent categories for you yet."
                    )

                    VStack(alignment: .leading, spacing: GMSpacing.sm) {
                        Label("Well-lit photos of single items work best", systemImage: "sun.max")
                        Label("You'll choose a category for each piece", systemImage: "tag")
                        Label("Short video frames are coming in a later update", systemImage: "video")
                    }
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textPrimary)
                    .gmCard(padding: GMSpacing.lg)

                    if let loadError {
                        GMInlineError(error: loadError)
                    }
                    if case .failed(let error) = model.uploadPhase {
                        GMInlineError(error: error)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GMBottomActionBar {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 8,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        GMProgressLabel(
                            title: "Choose photos",
                            isWorking: isLoadingSelection || model.isUploading
                        )
                    }
                    .buttonStyle(.gmPrimary)
                    .disabled(isLoadingSelection || model.isUploading)
                    .accessibilityIdentifier("wardrobeUpload.choosePhotos")
                }
            }
            .navigationTitle("Add photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(model.isUploading)
                }
            }
            .interactiveDismissDisabled(model.isUploading || isLoadingSelection)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingSelection = true
        loadError = nil
        defer {
            isLoadingSelection = false
            pickerItems = []
        }

        var payloads: [Data] = []
        for item in items {
            do {
                guard let transfer = try await item.loadTransferable(type: PhotoDataTransfer.self) else {
                    loadError = .api(
                        status: 422,
                        code: "photo_unreadable",
                        message: "One of the photos couldn't be loaded. Try again.",
                        requestID: nil,
                        retryable: false
                    )
                    return
                }
                payloads.append(transfer.data)
            } catch {
                loadError = .api(
                    status: 422,
                    code: "photo_unreadable",
                    message: "One of the photos couldn't be loaded. Try again.",
                    requestID: nil,
                    retryable: false
                )
                return
            }
        }

        guard !payloads.isEmpty else { return }
        await model.uploadPhotoData(payloads)
        if case .failed = model.uploadPhase { return }
        dismiss()
    }
}
