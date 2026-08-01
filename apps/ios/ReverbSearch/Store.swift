import Foundation
import StoreKit

/// The subscription. There is no backend — the app talks to Reverb directly —
/// so entitlement lives entirely on-device. That's safe: StoreKit 2 hands back
/// transactions Apple has already signed, and `.verified` is the check.
@MainActor
@Observable
final class Store {
    /// One entitlement, app-wide. A singleton so `SearchModel` can consult it
    /// without every view threading it through.
    static let shared = Store()

    static let productID = "com.betterreverbsearch.unlimited.monthly"

    private(set) var product: Product?
    private(set) var isSubscribed = false
    /// Non-nil only while this Apple Account can still claim the first-month
    /// price — one per subscription group, per account, ever.
    private(set) var introOffer: Product.SubscriptionOffer?

    private init() {
        Task {
            product = try? await Product.products(for: [Self.productID]).first
            await refresh()
            // Renewals, refunds, and purchases made on another device arrive here.
            for await _ in Transaction.updates { await refresh() }
        }
    }

    func refresh() async {
        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                entitled = true
            }
        }
        isSubscribed = entitled

        if let subscription = product?.subscription, let offer = subscription.introductoryOffer {
            introOffer = await subscription.isEligibleForIntroOffer ? offer : nil
        } else {
            introOffer = nil
        }
    }

    /// Returns false if the user cancelled or the purchase is awaiting approval.
    @discardableResult
    func purchase() async throws -> Bool {
        guard let product else { return false }
        guard case .success(let verification) = try await product.purchase() else { return false }
        guard case .verified(let transaction) = verification else { return false }
        await transaction.finish()
        await refresh()
        return true
    }

    /// Apple requires a restore path for anyone who reinstalls or switches device.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }
}
