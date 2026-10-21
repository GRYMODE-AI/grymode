import SwiftUI

struct OutfitDetailView: View {
    let look: OutfitLook
    var isSaving: Bool = false
    var onToggleSave: ((OutfitLook) async -> OutfitLook?)?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var current: OutfitLook
    @State private var isRequestingVisual = false
    @State private var showTryOn = false

    init(
        look: OutfitLook,
        isSaving: Bool = false,
        onToggleSave: ((OutfitLook) async -> OutfitLook?)? = nil
    ) {
        self.look = look
        self.isSaving = isSaving
        self.onToggleSave = onToggleSave
        _current = State(initialValue: look)
    }

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(contentWidth: .readable, accessibilityIdentifier: "screen.lookDetail") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.lg) {
                    GMSectionHeader(
                        overline: current.isFreeReveal ? "Your free look" : "Look",
                        title: current.title,
                        message: current.occasionTags.joined(separator: " · ").nilIfEmpty
                    )

                    hero

                    if !current.isLocked {
                        actions
                    }

                    piecesSection

                    if !current.styleTags.isEmpty {
                        Text(current.styleTags.joined(separator: " · "))
                            .gmTextStyle(.caption)
                            .foregroundStyle(GMColor.textSecondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("lookDetail.done")
                }
            }
            .sheet(isPresented: $showTryOn) {
                TryOnView(look: current)
            }
            .task {
                if !current.isLocked, current.visual == nil || current.isStyling {
                    await requestVisual()
                }
            }
            .task(id: current.isStyling) {
                await followVisual()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                .fill(GMColor.surfaceSunken)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { LookVisualView(look: current) }
                .clipShape(RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                        .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
                )
                .accessibilityLabel(heroAccessibilityLabel)
                .accessibilityIdentifier("lookDetail.visual")

            if current.visual?.status == .failed {
                HStack(spacing: GMSpacing.sm) {
                    Text("The styled image couldn't be created.")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                    Button("Try again") {
                        Task { await requestVisual() }
                    }
                    .gmTextStyle(.caption)
                    .disabled(isRequestingVisual)
                    .accessibilityIdentifier("lookDetail.retryVisual")
                }
            } else if current.isStyling {
                Text("Styling all \(current.pieceCount) pieces together from your photos…")
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: GMSpacing.sm) {
            Button {
                showTryOn = true
            } label: {
                Label("Try it on", systemImage: "person.crop.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gmPrimary)
            .accessibilityIdentifier("lookDetail.tryOn")

            if onToggleSave != nil {
                Button {
                    Task {
                        if let updated = await onToggleSave?(current) {
                            current = updated
                        }
                    }
                } label: {
                    GMProgressLabel(
                        title: current.isSaved ? "Saved" : "Save look",
                        isWorking: isSaving
                    )
                }
                .buttonStyle(.gmSecondary)
                .disabled(isSaving)
                .accessibilityIdentifier("lookDetail.save")
            }
        }
    }

    private var piecesSection: some View {
        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            Text("How to wear it")
                .gmTextStyle(.headline)
                .foregroundStyle(GMColor.textPrimary)
            Text("Every piece is from your wardrobe.")
                .gmTextStyle(.caption)
                .foregroundStyle(GMColor.textSecondary)
            VStack(spacing: GMSpacing.xs) {
                ForEach(current.orderedGarments) { piece in
                    pieceRow(piece)
                }
            }
        }
        .accessibilityIdentifier("lookDetail.pieces")
    }

    private func pieceRow(_ piece: OutfitGarmentRef) -> some View {
        HStack(spacing: GMSpacing.md) {
            Color.white
                .frame(width: 64, height: 80)
                .overlay { GMRemoteImage(url: piece.imageURL, contentMode: .fill) }
                .clipShape(RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous)
                        .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
                )
            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text(piece.roleTitle.uppercased())
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
                Text(piece.displayName)
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textPrimary)
                if let material = piece.material, !material.isEmpty {
                    Text(material.capitalized)
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(GMSpacing.xs)
        .background(GMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var heroAccessibilityLabel: String {
        let pieces = current.orderedGarments.map(\.displayName).joined(separator: ", ")
        return current.styledImageURL != nil ? "Styled look: \(pieces)" : "Look pieces: \(pieces)"
    }

    private func requestVisual() async {
        guard let api = app.apiClient, !isRequestingVisual else { return }
        isRequestingVisual = true
        defer { isRequestingVisual = false }
        do throws(AppError) {
            current = try await api.send(LooksAPI.requestVisual(id: current.id)).withSaved(current.isSaved)
        } catch {
            Log.networking.error("Look visual request failed: \(error.apiCode ?? "transport", privacy: .public)")
        }
    }

    private func followVisual() async {
        guard let api = app.apiClient else { return }
        var polls = 0
        while current.isStyling, polls < 90, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            polls += 1
            do throws(AppError) {
                current = try await api.send(LooksAPI.outfit(id: current.id)).withSaved(current.isSaved)
            } catch {
                Log.networking.error("Look visual refresh failed: \(error.apiCode ?? "transport", privacy: .public)")
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
