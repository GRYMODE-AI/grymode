import SwiftUI

/// Chooses the navigation container from the available space, not the device model:
/// a tab bar for compact widths (iPhone portrait, iPad Slide Over / narrow Split View) and a
/// sidebar split view when there is room (iPad, large iPhones in landscape).
///
/// At accessibility text sizes the tab bar is used everywhere: a sidebar wide enough for the
/// enlarged section names would cover the content on smaller iPads.
struct MainShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let router: AppRouter

    var body: some View {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            SidebarShell(router: router)
        } else {
            TabShell(router: router)
        }
    }
}

private struct TabShell: View {
    @Bindable var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: router.pathBinding(for: tab)) {
                    TabRootView(tab: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
    }
}

private struct SidebarShell: View {
    let router: AppRouter
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: router.sidebarSelection) {
                ForEach(AppTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.systemImage)
                            .gmTextStyle(.body)
                    }
                    .accessibilityIdentifier("sidebar.\(tab.rawValue)")
                }
            }
            .navigationTitle("Grymode")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack(path: router.pathBinding(for: router.selectedTab)) {
                TabRootView(tab: router.selectedTab)
            }
            .id(router.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// The root screen for each section.
struct TabRootView: View {
    let tab: AppTab

    var body: some View {
        Group {
            switch tab {
            case .home: HomeView()
            case .style: StyleView()
            case .wardrobe: WardrobeView()
            case .looks: LooksView()
            case .profile: ProfileView()
            }
        }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { GMWordmark() }
        }
    }
}
