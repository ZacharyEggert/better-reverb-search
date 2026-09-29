import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = Store.shared
    @State private var working = false
    @State private var errorMessage: String?

    // Apple's standard EULA. Swap for your own if you ever write one.
    private let terms = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacy = URL(string: "https://www.ex-nihilo.llc/privacy")!

    /// Falls back to the configured price only if the App Store is unreachable —
    /// the storefront's own `displayPrice` is the one that's correct abroad.
    private var price: String { store.monthly?.displayPrice ?? "$49.99" }
    private var lifetimePrice: String { store.lifetime?.displayPrice ?? "$999.99" }

    /// Apple 3.1.2(c): the billed amount is the biggest pricing element; the
    /// intro price sits below it, smaller.
    private var billedAmount: String { "\(price) per month" }

    private var subtext: String {
        let free = "\(QueryQuota.dailyLimit) searches a day are free."
        guard let intro = store.introOffer else { return free }
        return "\(free) First \(period(intro.period)) \(intro.displayPrice)."
    }

    /// App Review rejects an offer that doesn't spell out what happens after it.
    private var disclosure: String {
        guard let intro = store.introOffer else {
            return "Auto-renews monthly until cancelled. Manage or cancel in Settings › Apple Account › Subscriptions."
        }
        return "\(intro.displayPrice) for your first \(period(intro.period)), then \(price) per month. Auto-renews until cancelled. Manage or cancel in Settings › Apple Account › Subscriptions."
    }

    private func period(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "guitars")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .padding(.top, 24)

                    VStack(spacing: 8) {
                        Text("Unlimited Queries")
                            .font(.title.bold())
                        Text(billedAmount)
                            .font(.title2.bold())
                        Text(subtext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Apple 3.1.2(c): list only what the subscription adds. Sold comps
                    // and stats are free, so they don't belong here.
                    benefit("infinity", "Unlimited searches, every day")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        buy(store.monthly)
                    } label: {
                        Text("Subscribe")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working || store.monthly == nil)

                    Button {
                        buy(store.lifetime)
                    } label: {
                        Text("Unlock forever — \(lifetimePrice) once")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(working || store.lifetime == nil)

                    Button("Restore purchases") {
                        run {
                            try await store.restore()
                            if store.isUnlocked { dismiss() }
                            else { errorMessage = "No active purchase found on this account." }
                        }
                    }
                    .disabled(working)

                    Text("\(disclosure) Lifetime is a one-time purchase and never renews.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Link("Terms", destination: terms)
                        Link("Privacy", destination: privacy)
                    }
                    .font(.caption2)

                    Text(affiliationDisclaimer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .overlay { if working { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
    }

    private func buy(_ product: Product?) {
        guard let product else { return }
        run { if try await store.purchase(product) { dismiss() } }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        errorMessage = nil
        Task {
            do { try await work() } catch { errorMessage = error.localizedDescription }
            working = false
        }
    }
}
