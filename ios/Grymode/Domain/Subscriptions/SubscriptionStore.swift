import Foundation
import Observation
import StoreKit

/// Loads StoreKit 2 products, purchases, restores, and syncs entitlements with the Grymode API.
@MainActor
@Observable
final class SubscriptionStore {
    enum Phase: Equatable {
        case idle
        case loadingProducts
        case purchasing
        case restoring
        case syncing
        case failed(AppError)
    }

    private(set) var products: [Product] = []
    private(set) var phase: Phase = .idle
    private(set) var lastEntitlement: Entitlement?
    var selectedProductID: String?

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    static let fallbackProductIDs = [
        "com.grymode.stylist.premium.monthly",
        "com.grymode.stylist.premium.yearly",
    ]

    var isBusy: Bool {
        switch phase {
        case .loadingProducts, .purchasing, .restoring, .syncing: true
        case .idle, .failed: false
        }
    }

    var monthly: Product? {
        products.first { $0.id.hasSuffix(".monthly") }
    }

    var yearly: Product? {
        products.first { $0.id.hasSuffix(".yearly") }
    }

    func bind(api: APIClient?) {
        self.api = api
    }

    func startListeningForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(verification: update)
            }
        }
    }

    func loadProducts() async {
        phase = .loadingProducts
        var ids = Self.fallbackProductIDs
        if let api {
            do throws(AppError) {
                let remote = try await api.send(SubscriptionAPI.productIDs())
                if !remote.productIds.isEmpty { ids = remote.productIds }
            } catch {
                // Fall back to compiled product IDs when the catalog endpoint is unreachable.
                Log.networking.error("Product ID catalog failed: \(error.apiCode ?? "transport", privacy: .public)")
            }
        }
        do {
            let loaded = try await Product.products(for: Set(ids))
            products = loaded.sorted { lhs, rhs in
                if lhs.id.contains("monthly") { return true }
                if rhs.id.contains("monthly") { return false }
                return lhs.displayName < rhs.displayName
            }
            if selectedProductID == nil {
                selectedProductID = yearly?.id ?? monthly?.id ?? products.first?.id
            }
            phase = .idle
        } catch {
            phase = .failed(
                .api(
                    status: 500,
                    code: "products_unavailable",
                    message: "Plans couldn't be loaded from the App Store. Try again shortly.",
                    requestID: nil,
                    retryable: true
                )
            )
        }
    }

    func purchaseSelected() async {
        guard let id = selectedProductID, let product = products.first(where: { $0.id == id }) else {
            phase = .failed(
                .api(
                    status: 422,
                    code: "no_product",
                    message: "Choose a plan to continue.",
                    requestID: nil,
                    retryable: false
                )
            )
            return
        }
        await purchase(product)
    }

    func purchase(_ product: Product) async {
        phase = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification: verification)
                phase = lastEntitlement?.canOpenFullLibrary == true ? .idle : phase
                if case .failed = phase { return }
                phase = .idle
            case .userCancelled:
                phase = .idle
            case .pending:
                phase = .failed(
                    .api(
                        status: 202,
                        code: "purchase_pending",
                        message: "This purchase is pending approval. Grymode will unlock when it completes.",
                        requestID: nil,
                        retryable: true
                    )
                )
            @unknown default:
                phase = .failed(.unexpected)
            }
        } catch {
            phase = .failed(
                .api(
                    status: 500,
                    code: "purchase_failed",
                    message: "The purchase couldn't be completed. Please try again.",
                    requestID: nil,
                    retryable: true
                )
            )
        }
    }

    func restore() async {
        phase = .restoring
        do {
            try await AppStore.sync()
            var synced = false
            for await result in Transaction.currentEntitlements {
                await handle(verification: result)
                if lastEntitlement?.canOpenFullLibrary == true { synced = true }
            }
            phase = synced
                ? .idle
                : .failed(
                    .api(
                        status: 404,
                        code: "nothing_to_restore",
                        message: "No active Grymode subscription was found for this Apple ID.",
                        requestID: nil,
                        retryable: false
                    )
                )
        } catch {
            phase = .failed(
                .api(
                    status: 500,
                    code: "restore_failed",
                    message: "Restore couldn't finish. Check your connection and try again.",
                    requestID: nil,
                    retryable: true
                )
            )
        }
    }

    func syncCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await handle(verification: result)
        }
    }

    private func handle(verification: VerificationResult<Transaction>) async {
        let jws = verification.jwsRepresentation
        switch verification {
        case .unverified:
            phase = .failed(
                .api(
                    status: 400,
                    code: "unverified_transaction",
                    message: "Apple couldn't verify this purchase.",
                    requestID: nil,
                    retryable: false
                )
            )
        case .verified(let transaction):
            await sync(jws: jws)
            await transaction.finish()
        }
    }

    private func sync(jws: String) async {
        guard let api else { return }
        phase = .syncing
        do throws(AppError) {
            let response = try await api.send(SubscriptionAPI.sync(signedTransaction: jws))
            lastEntitlement = response.entitlement
            phase = .idle
            Log.networking.info("Subscription synced product=\(response.productId, privacy: .public)")
        } catch {
            phase = .failed(error)
        }
    }
}
