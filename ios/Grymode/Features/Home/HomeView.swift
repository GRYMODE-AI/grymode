import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var home = HomeModel(api: nil)
    @State private var avatar = AvatarModel(api: nil)
    @State private var detailLook: OutfitLook?
    @State private var showPaywall = false
    @State private var showAvatarSetup = false
    @State private var tryOnLook: OutfitLook?
    @State private var isStartingTryOn = false

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.home") { layout in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(
                    overline: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    title: Self.greeting(for: .now)
                )

                if let error = home.actionError {
                    GMInlineError(error: error)
                }

                switch home.loadState {
                case .idle, .loading:
                    if home.snapshot == nil {
                        GMLoadingStateView(message: "Loading today’s look…")
                    } else {
                        homeContent(layout: layout)
                    }
                case .failed(let error):
                    if home.snapshot == nil {
                        GMErrorStateView(error: error) {
                            Task { await home.refresh() }
                        }
                    } else {
                        homeContent(layout: layout)
                    }
                case .loaded:
                    homeContent(layout: layout)
                }
            }
        }
        .sheet(item: $detailLook) { look in
            OutfitDetailView(
                look: look,
                isSaving: home.isTogglingSave,
                onToggleSave: { current in
                    await home.toggleSave(current)
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(store: model.subscriptions, lockedCount: home.lockedCount) {
                Task { await home.refresh() }
            }
        }
        .sheet(isPresented: $showAvatarSetup) {
            AvatarSetupSheet(avatar: avatar) {
                Task { await startTryOn() }
            }
        }
        .sheet(item: $tryOnLook) { look in
            TryOnView(look: look)
        }
        .task(id: model.apiClient != nil) {
            home.bind(api: model.apiClient)
            avatar.bind(api: model.apiClient)
            await home.refresh()
            await avatar.refresh()
        }
        .task(id: home.todaysLook?.isStyling == true) {
            await home.followTodaysLookVisual()
        }
        .refreshable {
            await home.refresh()
        }
    }

    @ViewBuilder
    private func homeContent(layout: AdaptiveLayout) -> some View {
        todaysLookSection
        libraryEntry(layout: layout)
    }

    @ViewBuilder
    private var todaysLookSection: some View {
        if let look = home.todaysLook {
            VStack(alignment: .leading, spacing: GMSpacing.md) {
                GMSectionHeader(
                    overline: "Wear this today",
                    title: look.title,
                    message: look.occasionTags.joined(separator: " · ").nilIfEmpty
                        ?? "A complete look from your wardrobe.",
                    titleStyle: .headline
                )

                Button {
                    Task { await open(look) }
                } label: {
                    TodaysLookHero(look: look)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.todaysLook")
                .disabled(look.isLocked && !home.isPremium)

                HStack(spacing: GMSpacing.sm) {
                    if look.isLocked {
                        Button("Unlock full library") { showPaywall = true }
                            .buttonStyle(.gmPrimary)
                            .accessibilityIdentifier("home.unlock")
                    } else {
                        Button {
                            Task { await startTryOn() }
                        } label: {
                            GMProgressLabel(title: "Try on", isWorking: isStartingTryOn)
                        }
                        .buttonStyle(.gmPrimary)
                        .disabled(isStartingTryOn)
                        .accessibilityIdentifier("home.tryOn")

                        Button("Open") {
                            Task { await open(look) }
                        }
                        .buttonStyle(.gmSecondary)
                        .accessibilityIdentifier("home.openLook")

                        Button(look.isSaved ? "Saved" : "Save") {
                            Task { _ = await home.toggleSave(look) }
                        }
                        .buttonStyle(.gmSecondary)
                        .disabled(home.isTogglingSave)
                        .accessibilityIdentifier("home.saveLook")
                    }
                }
            }
        } else if home.wardrobeCount < 2 {
            HomeCard(
                overline: "Start here",
                title: "Build your wardrobe",
                message:
                    "Your looks are created only from clothes you own. Begin with photos or a short video of your wardrobe.",
                actionTitle: "Go to Wardrobe",
                identifier: "home.goToWardrobe"
            ) {
                model.router.select(.wardrobe)
            }
        } else if home.acceptedCount == 0 {
            HomeCard(
                overline: "Your library",
                title: "Create your looks",
                message: "You have confirmed pieces ready. Open Looks to compose outfits from your wardrobe.",
                actionTitle: "Go to Looks",
                identifier: "home.goToLooks"
            ) {
                model.router.select(.looks)
            }
        } else {
            HomeCard(
                overline: "Wear this today",
                title: "Today’s look isn’t ready",
                message: "Your library has looks, but today’s pick couldn’t load. Open Looks or pull to refresh.",
                actionTitle: "Open Looks",
                identifier: "home.goToLooksFallback"
            ) {
                model.router.select(.looks)
            }
        }
    }

    @ViewBuilder
    private func libraryEntry(layout: AdaptiveLayout) -> some View {
        let cards = Group {
            if home.acceptedCount > 0 {
                HomeCard(
                    overline: home.isPremium ? "Library" : "Preview",
                    title: home.isPremium
                        ? "\(home.acceptedCount) looks ready"
                        : "\(home.acceptedCount) looks · \(home.lockedCount) locked",
                    message: home.savedCount > 0
                        ? "\(home.savedCount) saved. Browse occasions and open any look from your wardrobe."
                        : "Browse your full library, filter by occasion, and save favourites.",
                    actionTitle: "Open library",
                    identifier: "home.openLibrary"
                ) {
                    model.router.select(.looks)
                }
            }

            HomeCard(
                overline: "Your style",
                title: model.styleProfiles.profile.headline,
                message: "Your preferences help order your looks. Update them whenever your taste changes.",
                actionTitle: "View style profile",
                identifier: "home.viewStyle"
            ) {
                model.router.select(.style)
            }

            if home.wardrobeCount > 0 {
                HomeCard(
                    overline: "Wardrobe",
                    title: "\(home.wardrobeCount) confirmed pieces",
                    message: "Add, relabel, or remove pieces anytime. New confirms refresh your looks.",
                    actionTitle: "Manage wardrobe",
                    identifier: "home.manageWardrobe"
                ) {
                    model.router.select(.wardrobe)
                }
            }
        }

        if layout.prefersSideBySide && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: GMSpacing.md) { cards }
        } else {
            VStack(spacing: GMSpacing.md) { cards }
        }
    }

    private func open(_ look: OutfitLook) async {
        if look.isLocked {
            showPaywall = true
            return
        }
        do throws(AppError) {
            detailLook = try await home.openLook(id: look.id)
        } catch {
            if case .api(let status, _, _, _, _) = error, status == 403 {
                showPaywall = true
            } else {
                home.presentError(error)
            }
        }
    }

    private func startTryOn() async {
        guard let look = home.todaysLook, !look.isLocked else { return }
        guard !isStartingTryOn else { return }
        isStartingTryOn = true
        defer { isStartingTryOn = false }
        if !avatar.isReadyForTryOn {
            await avatar.refresh()
        }
        if avatar.isReadyForTryOn {
            tryOnLook = look
        } else {
            showAvatarSetup = true
        }
    }

    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct TodaysLookHero: View {
    let look: OutfitLook

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            if look.isLocked {
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(GMColor.surfaceSunken)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        VStack(spacing: GMSpacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                                .foregroundStyle(GMColor.textSecondary)
                            Text("\(look.pieceCount) pieces locked")
                                .gmTextStyle(.caption)
                                .foregroundStyle(GMColor.textSecondary)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(GMColor.surfaceSunken)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .overlay { LookVisualView(look: look) }
                    .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))

                Text(look.orderedGarments.map(\.displayName).joined(separator: " · "))
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textPrimary)
                    .lineLimit(3)
            }

            if !look.styleTags.isEmpty {
                Text(look.styleTags.prefix(4).joined(separator: " · "))
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
            }
        }
        .padding(GMSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
        )
    }
}

private struct HomeCard: View {
    let overline: String
    let title: String
    let message: String
    let actionTitle: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GMSpacing.md) {
            GMSectionHeader(overline: overline, title: title, message: message, titleStyle: .headline)
            Spacer(minLength: 0)
            Button(actionTitle, action: action)
                .buttonStyle(.gmSecondary)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .gmCard(padding: GMSpacing.lg)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview("iPhone") {
    NavigationStack { HomeView() }
        .environment(AppModel.preview())
}

#Preview("iPad", traits: .fixedLayout(width: 1024, height: 768)) {
    NavigationStack { HomeView() }
        .environment(AppModel.preview())
}
