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
    private let privacy = URL(string: "https://ex-nihilo.llc/privacy")!

    /// Falls back to the configured price only if the App Store is unreachable —
    /// the storefront's own `displayPrice` is the one that's correct abroad.
    private var price: String { store.product?.displayPrice ?? "$49.99" }

    private var pitch: String {
        guard let intro = store.introOffer else {
            return "\(QueryQuota.dailyLimit) searches a day are free. Go unlimited for \(price) per month."
        }
        return "\(QueryQuota.dailyLimit) searches a day are free. Go unlimited for \(intro.displayPrice) your first \(period(intro.period)), then \(price) per month."
    }

    private var callToAction: String {
        guard let intro = store.introOffer else { return "Subscribe — \(price)/month" }
        return "Start for \(intro.displayPrice)"
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
                        Text(pitch)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        benefit("infinity", "Unlimited searches, every day")
                        benefit("tag.fill", "Sold comps — what gear actually clears for")
                        benefit("chart.bar.fill", "Low / median / high on every result set")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        run { if try await store.purchase() { dismiss() } }
                    } label: {
                        Text(callToAction)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working || store.product == nil)

                    Button("Restore purchases") {
                        run {
                            try await store.restore()
                            if store.isSubscribed { dismiss() }
                            else { errorMessage = "No active subscription found on this account." }
                        }
                    }
                    .disabled(working)

                    Text(disclosure)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Link("Terms", destination: terms)
                        Link("Privacy", destination: privacy)
                    }
                    .font(.caption2)
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

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        errorMessage = nil
        Task {
            do { try await work() } catch { errorMessage = error.localizedDescription }
            working = false
        }
    }
}
