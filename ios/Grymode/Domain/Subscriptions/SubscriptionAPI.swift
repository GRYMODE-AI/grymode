import Foundation

struct SyncSubscriptionResponse: Codable, Equatable, Sendable {
    let entitlement: Entitlement
    let productId: String
    let status: String
    let environment: String
}

struct StoreProductIDs: Codable, Equatable, Sendable {
    let productIds: [String]
}

enum SubscriptionAPI {
    static func productIDs() -> Endpoint<StoreProductIDs> {
        Endpoint(method: .get, path: "/v1/subscriptions/products", requiresAuthentication: false)
    }

    static func sync(signedTransaction: String) throws(AppError) -> Endpoint<SyncSubscriptionResponse> {
        let body = try JSONCoding.encode(SyncBody(signedTransaction: signedTransaction))
        return Endpoint(method: .post, path: "/v1/subscriptions/sync", body: body)
    }
}

private struct SyncBody: Encodable {
    let signedTransaction: String
}
