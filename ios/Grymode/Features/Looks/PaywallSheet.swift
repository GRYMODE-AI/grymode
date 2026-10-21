import StoreKit
import SwiftUI

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var store: SubscriptionStore
    let lockedCount: Int
    var onUnlocked: () -> Void = {}

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(contentWidth: .readable, accessibilityIdentifier: "screen.paywall") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.lg) {
                    GMSectionHeader(
                        overline: "Grymode",
                        title: "See what else you can wear.",
                        message:
                            "Grymode has created a personal outfit library from your wardrobe. Unlock your looks and make your wardrobe work harder."
                    )

                    Text(lockedSummary)
                        .gmTextStyle(.body)
                        .foregroundStyle(GMColor.textSecondary)

                    if store.products.isEmpty {
                        if case .failed(let error) = store.phase {
                            GMInlineError(error: error)
                        } else {
                            GMLoadingStateView(message: "Loading plans from the App Store…")
                        }
                    } else {
                        VStack(spacing: GMSpacing.sm) {
                            ForEach(store.products, id: \.id) { product in
                                planRow(product)
                            }
                        }
                    }

                    if case .failed(let error) = store.phase {
                        GMInlineError(error: error)
                    }

                    Button {
                        Task {
                            await store.purchaseSelected()
                            if store.lastEntitlement?.canOpenFullLibrary == true {
                                onUnlocked()
                                dismiss()
                            }
                        }
                    } label: {
                        GMProgressLabel(title: "Continue", isWorking: store.isBusy)
                    }
                    .buttonStyle(.gmPrimary)
                    .disabled(store.isBusy || store.selectedProductID == nil)
                    .accessibilityIdentifier("paywall.purchase")

                    Button {
                        Task {
                            await store.restore()
                            if store.lastEntitlement?.canOpenFullLibrary == true {
                                onUnlocked()
                                dismiss()
                            }
                        }
                    } label: {
                        GMProgressLabel(title: "Restore Purchases", isWorking: store.phase == .restoring)
                    }
                    .buttonStyle(.gmSecondary)
                    .disabled(store.isBusy)
                    .accessibilityIdentifier("paywall.restore")

                    VStack(alignment: .leading, spacing: GMSpacing.xs) {
                        Text(
                            "Subscriptions renew automatically until cancelled. Manage or cancel anytime in Settings > your name > Subscriptions."
                        )
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                        HStack(spacing: GMSpacing.md) {
                            Button("Terms") { openURL(LegalLinks.terms) }
                            Button("Privacy") { openURL(LegalLinks.privacy) }
                            if let url = Self.manageSubscriptionsURL {
                                Button("Manage") { openURL(url) }
                            }
                        }
                        .gmTextStyle(.caption)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("paywall.dismiss")
                }
            }
            .task {
                store.startListeningForTransactions()
                await store.loadProducts()
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = store.selectedProductID == product.id
        return Button {
            store.selectedProductID = product.id
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                    Text(product.displayName)
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                    Text(product.description)
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: GMSpacing.sm)
                Text(product.displayPrice)
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textPrimary)
            }
            .padding(GMSpacing.md)
            .background(GMColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .strokeBorder(selected ? GMColor.accent : GMColor.border, lineWidth: selected ? 2 : GMBorder.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.product.\(product.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var lockedSummary: String {
        lockedCount == 1
            ? "1 more look is ready in your library."
            : "\(lockedCount) more looks are ready in your library."
    }
}
