import PhotosUI
import SwiftUI

struct WardrobeView: View {
    @Environment(AppModel.self) private var app
    @State private var model = WardrobeModel(api: nil)
    @State private var showUploadIntro = false
    @State private var editingGarment: WardrobeGarment?
    @State private var imageReloadToken = 0

    var body: some View {
        @Bindable var model = model
        AdaptiveScrollScreen(contentWidth: .grid, accessibilityIdentifier: "screen.wardrobe") { layout in
            VStack(alignment: .leading, spacing: GMSpacing.lg) {
                GMSectionHeader(
                    overline: "Your pieces",
                    title: "Wardrobe",
                    message: headerMessage
                )

                if let message = model.uploadStatusMessage {
                    GMLoadingStateView(message: message)
                } else if case .failed(let error) = model.uploadPhase {
                    GMInlineError(error: error)
                }

                if let error = model.actionError {
                    GMInlineError(error: error)
                }

                content(layout: layout)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasPieces {
                GMBottomActionBar {
                    if !model.confirmableGarments.isEmpty {
                        Button {
                            Task {
                                await model.confirmLabeledPieces()
                                imageReloadToken &+= 1
                            }
                        } label: {
                            GMProgressLabel(
                                title: confirmTitle,
                                isWorking: model.isConfirming
                            )
                        }
                        .buttonStyle(.gmPrimary)
                        .disabled(model.isConfirming || model.isUploading)
                        .accessibilityIdentifier("wardrobe.confirm")
                    }
                    if model.confirmableGarments.isEmpty {
                        Button("Add photos") { showUploadIntro = true }
                            .buttonStyle(.gmPrimary)
                            .disabled(model.isUploading)
                            .accessibilityIdentifier("wardrobe.addPhotos")
                    } else {
                        Button("Add photos") { showUploadIntro = true }
                            .buttonStyle(.gmSecondary)
                            .disabled(model.isUploading)
                            .accessibilityIdentifier("wardrobe.addPhotos")
                    }
                }
            }
        }
        .sheet(isPresented: $showUploadIntro) {
            WardrobeUploadSheet(model: model)
        }
        .sheet(item: $editingGarment) { garment in
            GarmentEditorSheet(garment: garment, model: model)
        }
        .task {
            model.bind(api: app.apiClient)
            await model.refresh()
            imageReloadToken &+= 1
        }
        .refreshable {
            await model.refresh()
            imageReloadToken &+= 1
        }
    }

    @ViewBuilder
    private func content(layout: AdaptiveLayout) -> some View {
        switch model.loadState {
        case .idle,
            .loading where !model.hasPieces:
            GMLoadingStateView(message: "Loading your wardrobe…")
        case .failed(let error) where !model.hasPieces:
            GMErrorStateView(error: error) {
                Task { await model.refresh() }
            }
        case .loading, .loaded, .failed, .idle:
            if model.hasPieces {
                garmentGrid(columns: layout.gridColumnCount)
            } else if !model.isUploading {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        GMEmptyStateView(
            systemImage: "hanger",
            title: "No pieces yet",
            message:
                "Add photos of your clothes. Grymode identifies each piece; you check the details and confirm them so looks are built only from what you own.",
            action: GMStateAction(title: "Add photos") { showUploadIntro = true }
        )
        .gmCard(padding: GMSpacing.lg)
        .accessibilityIdentifier("wardrobe.empty")
    }

    private func garmentGrid(columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: GMSpacing.sm), count: columns)
        return LazyVGrid(columns: grid, spacing: GMSpacing.sm) {
            ForEach(model.garments) { garment in
                Button {
                    editingGarment = garment
                } label: {
                    GarmentTile(garment: garment, reloadToken: imageReloadToken)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wardrobe.garment.\(garment.id.uuidString.lowercased())")
            }
        }
    }

    private var headerMessage: String? {
        if model.unlabeledCount > 0 {
            return "Pick a category for pieces marked Label, then confirm the ones that are ready."
        }
        if !model.confirmableGarments.isEmpty {
            return "Grymode identified these pieces. Tap one to check its details, then confirm to style from them."
        }
        if model.hasPieces {
            return "Pieces you confirm appear here, grouped by category. You can correct or remove any of them."
        }
        return nil
    }

    private var confirmTitle: String {
        let count = model.confirmableGarments.count
        return count == 1 ? "Confirm 1 piece" : "Confirm \(count) pieces"
    }
}

private struct GarmentTile: View {
    let garment: WardrobeGarment
    let reloadToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                garmentImage
                if garment.needsLabel || !garment.userConfirmed {
                    Text(garment.needsLabel ? "Label" : "Review")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textPrimary)
                        .padding(.horizontal, GMSpacing.xs)
                        .padding(.vertical, GMSpacing.xxs)
                        .background(GMColor.surface.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous))
                        .padding(GMSpacing.xs)
                }
            }
            Text(garment.displayName)
                .gmTextStyle(.callout)
                .foregroundStyle(GMColor.textPrimary)
                .lineLimit(1)
            if garment.displayName != garment.category.title {
                Text(garment.category.title)
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(garment.displayName), \(garment.category.title), \(garment.userConfirmed ? "confirmed" : "not confirmed")"
        )
    }

    @ViewBuilder
    private var garmentImage: some View {
        let url = URL(string: garment.imageUrl)
        RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
            .fill(GMColor.surfaceSunken)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(GMColor.textSecondary)
                        case .empty:
                            ProgressView().tint(GMColor.accent)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .id("\(garment.id.uuidString)-\(reloadToken)")
                    .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
            )
    }
}

#Preview {
    NavigationStack { WardrobeView() }
        .environment(AppModel.preview())
}
