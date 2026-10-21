import Observation
import SwiftUI

/// Owns navigation state for the main experience. Keeping it outside the views means the
/// selected section and each section's stack survive switching between the compact tab bar
/// and the regular-width sidebar (rotation, Split View, window resizing).
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    private var paths: [AppTab: NavigationPath] = [:]

    func path(for tab: AppTab) -> NavigationPath {
        paths[tab] ?? NavigationPath()
    }

    func setPath(_ path: NavigationPath, for tab: AppTab) {
        paths[tab] = path
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = NavigationPath()
    }

    /// Clears section stacks and returns to Home. Called when the user signs out so the next
    /// session does not reopen Profile (or another tab) over an empty welcome → sign-in flow.
    func resetToHome() {
        paths = [:]
        selectedTab = .home
    }

    func pathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.path(for: tab) },
            set: { self.setPath($0, for: tab) }
        )
    }

    var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { self.selectedTab },
            set: { if let tab = $0 { self.selectedTab = tab } }
        )
    }
}
