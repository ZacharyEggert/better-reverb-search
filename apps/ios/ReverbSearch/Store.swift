import Foundation
import StoreKit

/// The subscription and the lifetime unlock. There is no backend — the app talks to Reverb directly —
/// so entitlement lives entirely on-device. That's safe: StoreKit 2 hands back
/// transactions Apple has already signed, and `.verified` is the check.
@MainActor
@Observable
final class Store {
    /// One entitlement, app-wide. A singleton so `SearchModel` can consult it
    /// without every view threading it through.
    static let shared = Store()

    static let monthlyID = "com.betterreverbsearch.unlimited.monthly"
    /// Non-consumable. Either product unlocks the same thing.
    static let lifetimeID = "llc.exnihilo.betterreverbsearch.unlimited.lifetime"

    private(set) var monthly: Product?
    private(set) var lifetime: Product?
    private(set) var isUnlocked = false
    /// Non-nil only while this Apple Account can still claim the first-month
    /// price — one per subscription group, per account, ever.
    private(set) var introOffer: Product.SubscriptionOffer?

    private init() {
        Task {
            let products = (try? await Product.products(for: [Self.monthlyID, Self.lifetimeID])) ?? []
            monthly = products.first { $0.id == Self.monthlyID }
            lifetime = products.first { $0.id == Self.lifetimeID }
            await refresh()
            // Renewals, refunds, and purchases made on another device arrive here.
            for await _ in Transaction.updates { await refresh() }
        }
    }

    func refresh() async {
        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if [Self.monthlyID, Self.lifetimeID].contains(transaction.productID),
                transaction.revocationDate == nil
            {
                entitled = true
            }
        }
        isUnlocked = entitled

        if let subscription = monthly?.subscription, let offer = subscription.introductoryOffer {
            introOffer = await subscription.isEligibleForIntroOffer ? offer : nil
        } else {
            introOffer = nil
        }
    }

    /// Returns false if the user cancelled or the purchase is awaiting approval.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
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
