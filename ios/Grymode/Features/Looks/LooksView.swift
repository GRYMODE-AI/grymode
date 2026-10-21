import SwiftUI

struct LooksView: View {
    @Environment(AppModel.self) private var app
    @State private var model = LooksModel(api: nil)
    @State private var detailLook: OutfitLook?
    @State private var showPaywall = false
    @AppStorage("looks.wardrobeReadyDismissed") private var wardrobeReadyDismissed = false

    var body: some View {
        AdaptiveScrollScreen(contentWidth: .grid, accessibilityIdentifier: "screen.looks") { layout in
            VStack(alignment: .leading, spacing: GMSpacing.lg) {
                GMSectionHeader(
                    overline: "Your library",
                    title: "Looks",
                    message: headerMessage
                )

                if shouldShowWardrobeReady {
                    wardrobeReadyCard
                }

                if model.acceptedCount > 0 {
                    filterBar
                }

                if let message = model.statusMessage {
                    GMLoadingStateView(message: message)
                }

                if let error = model.actionError {
                    GMInlineError(error: error)
                }

                content(layout: layout)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GMBottomActionBar {
                if model.hasLooks || model.acceptedCount > 0 {
                    Button {
                        Task { await model.generateLooks() }
                    } label: {
                        GMProgressLabel(
                            title: "Refresh looks",
                            isWorking: model.isGenerating
                        )
                    }
                    .buttonStyle(.gmSecondary)
                    .disabled(model.isGenerating || model.activeJob != nil)
                    .accessibilityIdentifier("looks.refresh")
                } else {
                    Button {
                        Task { await model.generateLooks() }
                    } label: {
                        GMProgressLabel(
                            title: "Create looks",
                            isWorking: model.isGenerating
                        )
                    }
                    .buttonStyle(.gmPrimary)
                    .disabled(model.isGenerating || model.activeJob != nil)
                    .accessibilityIdentifier("looks.generate")
                }
            }
        }
        .sheet(item: $detailLook) { look in
            OutfitDetailView(
                look: look,
                isSaving: model.isTogglingSave,
                onToggleSave: { current in
                    await model.toggleSave(current)
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(store: app.subscriptions, lockedCount: model.lockedCount) {
                Task { await model.refresh(autoGenerateIfEmpty: false) }
            }
        }
        .task {
            model.bind(api: app.apiClient)
            await model.refresh()
        }
        .task(id: model.hasStylingLooks) {
            await model.followStylingLooks()
        }
        .refreshable {
            await model.refresh()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GMSpacing.sm) {
                GMChoiceChip(
                    title: "All",
                    isSelected: model.selectedOccasion == nil && !model.savedOnly,
                    expands: false
                ) {
                    Task { await model.applyFilters(occasion: nil, savedOnly: false) }
                }
                .accessibilityIdentifier("looks.filter.all")

                GMChoiceChip(
                    title: model.savedCount > 0 ? "Saved (\(model.savedCount))" : "Saved",
                    isSelected: model.savedOnly,
                    expands: false
                ) {
                    Task { await model.applyFilters(occasion: nil, savedOnly: true) }
                }
                .accessibilityIdentifier("looks.filter.saved")

                ForEach(model.filterOccasions, id: \.self) { occasion in
                    GMChoiceChip(
                        title: occasion.capitalized,
                        isSelected: model.selectedOccasion?.lowercased() == occasion.lowercased() && !model.savedOnly,
                        expands: false
                    ) {
                        Task { await model.applyFilters(occasion: occasion, savedOnly: false) }
                    }
                    .accessibilityIdentifier("looks.filter.\(occasion.lowercased())")
                }
            }
        }
        .accessibilityIdentifier("looks.filters")
    }

    @ViewBuilder
    private func content(layout: AdaptiveLayout) -> some View {
        switch model.loadState {
        case .loading where !model.hasLooks && model.acceptedCount == 0:
            GMLoadingStateView(message: "Loading your looks…")
        case .failed(let error) where !model.hasLooks && model.acceptedCount == 0:
            GMErrorStateView(error: error) {
                Task { await model.refresh() }
            }
        case .idle where !model.hasLooks && model.acceptedCount == 0:
            GMLoadingStateView(message: "Loading your looks…")
        case .idle, .loading, .loaded, .failed:
            if model.hasLooks {
                looksGrid(columns: layout.gridColumnCount)
            } else if model.statusMessage == nil {
                filteredEmptyState
            }
        }
    }

    private var filteredEmptyState: some View {
        Group {
            if model.savedOnly {
                GMEmptyStateView(
                    systemImage: "heart",
                    title: "No saved looks",
                    message: "Open a look you like and tap Save look to keep it here."
                )
            } else if model.selectedOccasion != nil {
                GMEmptyStateView(
                    systemImage: "line.3.horizontal.decrease",
                    title: "Nothing for this occasion",
                    message: "Try All, or refresh looks after confirming more wardrobe pieces."
                )
            } else {
                GMEmptyStateView(
                    systemImage: "square.grid.2x2",
                    title: "No looks yet",
                    message:
                        "Looks are created only from your confirmed wardrobe. Label and confirm a few pieces, then tap Create looks.",
                    action: GMStateAction(title: "Create looks") {
                        Task { await model.generateLooks() }
                    }
                )
            }
        }
        .gmCard(padding: GMSpacing.lg)
        .accessibilityIdentifier("looks.empty")
    }

    private var wardrobeReadyCard: some View {
        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            Text("Your wardrobe is ready")
                .gmTextStyle(.title)
                .foregroundStyle(GMColor.textPrimary)
            Text("Open your free look below. \(model.lockedCount) more \(model.lockedCount == 1 ? "look is" : "looks are") waiting in your library.")
                .gmTextStyle(.body)
                .foregroundStyle(GMColor.textSecondary)
            HStack(spacing: GMSpacing.sm) {
                if let free = model.freeReveal {
                    Button("Open free look") {
                        Task { await open(free) }
                    }
                    .buttonStyle(.gmPrimary)
                    .accessibilityIdentifier("looks.openFree")
                }
                Button("Dismiss") { wardrobeReadyDismissed = true }
                    .buttonStyle(.gmSecondary)
            }
        }
        .gmCard(padding: GMSpacing.lg)
        .accessibilityIdentifier("looks.wardrobeReady")
    }

    private func looksGrid(columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: GMSpacing.sm), count: columns)
        return LazyVGrid(columns: grid, spacing: GMSpacing.sm) {
            ForEach(model.looks) { look in
                Button {
                    Task { await open(look) }
                } label: {
                    LookTile(look: look)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("looks.item.\(look.id.uuidString.lowercased())")
            }
        }
    }

    private func open(_ look: OutfitLook) async {
        if look.isLocked {
            showPaywall = true
            return
        }
        do throws(AppError) {
            detailLook = try await model.openLook(id: look.id)
        } catch {
            if case .api(let status, _, _, _, _) = error, status == 403 {
                showPaywall = true
            } else {
                model.presentError(error)
            }
        }
    }

    private var shouldShowWardrobeReady: Bool {
        !wardrobeReadyDismissed && model.hasLooks && model.freeReveal != nil && !model.isPremium
            && model.selectedOccasion == nil && !model.savedOnly
    }

    private var headerMessage: String? {
        if model.acceptedCount > 0 {
            if model.isPremium {
                return "\(model.acceptedCount) looks from your confirmed wardrobe."
            }
            let freeNote = model.freeReveal == nil ? "" : " One is unlocked for you."
            if model.lockedCount > 0 {
                return "\(model.acceptedCount) looks ready.\(freeNote) \(model.lockedCount) locked until you unlock Grymode."
            }
            return "\(model.acceptedCount) looks from your confirmed wardrobe.\(freeNote)"
        }
        return "Create a library of complete outfits from pieces you've confirmed."
    }
}

private struct LookTile: View {
    let look: OutfitLook

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(GMColor.surfaceSunken)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        if look.isLocked {
                            VStack(spacing: GMSpacing.xs) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(GMColor.textSecondary)
                                Text("\(look.pieceCount) pieces")
                                    .gmTextStyle(.caption)
                                    .foregroundStyle(GMColor.textSecondary)
                            }
                        } else {
                            LookVisualView(look: look)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                            .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
                    )
                    .opacity(look.isLocked ? 0.92 : 1)

                VStack(alignment: .trailing, spacing: GMSpacing.xxs) {
                    if look.isFreeReveal {
                        badge("Free")
                    } else if look.isLocked {
                        badge("Locked")
                    }
                    if look.isSaved {
                        badge("Saved")
                    }
                }
                .padding(GMSpacing.xs)
            }

            Text(look.title)
                .gmTextStyle(.callout)
                .foregroundStyle(GMColor.textPrimary)
                .lineLimit(2)
            if let occasion = look.occasionTags.first {
                Text(occasion)
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [look.title]
        if look.isLocked { parts.append("locked") }
        if look.isSaved { parts.append("saved") }
        return parts.joined(separator: ", ")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .gmTextStyle(.caption)
            .foregroundStyle(GMColor.textPrimary)
            .padding(.horizontal, GMSpacing.xs)
            .padding(.vertical, GMSpacing.xxs)
            .background(GMColor.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous))
    }
}
