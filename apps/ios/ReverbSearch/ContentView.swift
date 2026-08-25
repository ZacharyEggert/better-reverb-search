import SwiftUI

/// Nominative use of the Reverb mark — say plainly whose app this isn't.
let affiliationDisclaimer = "Created by Ex Nihilo LLC. Not affiliated with Reverb.com LLC."

/// How more results are reached. Persisted as its raw value.
enum Paging: String, CaseIterable {
    case more, scroll, all

    var label: String {
        switch self {
        case .more: "Load more"
        case .scroll: "Infinite scroll"
        case .all: "Load all pages"
        }
    }
}

/// Gap between the automatic page fetches in `.all` — Reverb rate-limits.
private let allPagesDelay = Duration.milliseconds(500)

struct ContentView: View {
    @State private var model = SearchModel()
    @State private var showFilters = false
    @State private var showAPIKey = false
    @State private var showPromoCode = false
    @State private var toast: String?
    @State private var store = Store.shared
    // Mirrors QueryQuota.dailyLimit so a promo code taking effect re-renders the
    // count — the quota itself is a static with nothing to observe.
    @State private var dailyLimit = QueryQuota.dailyLimit
    // Display preference, not part of the search — survives Clear.
    @AppStorage("view") private var grid = false
    // Display preference too — how more results are reached.
    @AppStorage("paging") private var paging = Paging.more

    var body: some View {
        NavigationStack {
            results
                .navigationTitle("Better Reverb Search")
                // Inline: the full name doesn't fit a large title.
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $model.query.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "e.g. 1963 Stratocaster")
                // Without this the search field hides the toolbar while it's
                // active — taking Filters with it.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .onSubmit(of: .search) { model.search() }
                // Load-all owns the page size while it's the chosen mode.
                .onChange(of: paging, initial: true) { model.loadAllPages = paging == .all }
                .toolbar { toolbar }
                .sheet(isPresented: $showFilters) {
                    FiltersView(query: $model.query, filters: $model.filters) { model.search() }
                }
                .sheet(isPresented: $showAPIKey) { APIKeyView() }
                // Code entered or cleared — the limit may have moved.
                .sheet(isPresented: $showPromoCode) { dailyLimit = QueryQuota.dailyLimit } content: {
                    PromoCodeView()
                }
                .sheet(isPresented: $model.showPaywall) { PaywallView() }
                // Re-check the stored promo code once per launch.
                .task {
                    if await BypassCode.refresh() == .unreachable {
                        toast =
                            "Promo service unreachable — daily limit stays at \(QueryQuota.dailyLimit)."
                    }
                    dailyLimit = QueryQuota.dailyLimit
                }
                .overlay(alignment: .bottom) {
                    if let toast {
                        ToastView(text: toast)
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                self.toast = nil
                            }
                    }
                }
                .animation(.default, value: toast)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // Sold comps answer "what did this clear for", not "what are people asking".
            Button {
                model.query.showOnlySold.toggle()
                model.search()
            } label: {
                Label(
                    model.query.showOnlySold ? "Sold comps" : "Active",
                    systemImage: model.query.showOnlySold ? "tag.fill" : "tag")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { grid.toggle() } label: {
                Label("View", systemImage: grid ? "square.grid.2x2.fill" : "list.bullet")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showFilters = true } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !store.isSubscribed, QueryQuota.offerUpgrade {
                    Button(
                        "\(QueryQuota.remaining) of \(dailyLimit) searches left today",
                        systemImage: "infinity"
                    ) { model.showPaywall = true }
                }
                Picker("Load more", selection: $paging) {
                    ForEach(Paging.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Button("API key", systemImage: "key") { showAPIKey = true }
                Button("Promo code", systemImage: "ticket") { showPromoCode = true }
                Button("Clear", systemImage: "xmark.circle", role: .destructive) { model.clear() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.red.opacity(0.1), in: .rect(cornerRadius: 12))
                }

                if let result = model.result {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(result.total.formatted()) matches")
                            .font(.headline)
                        // Reverb's echo of how it parsed the filters — the cheapest
                        // guard against a filter silently doing nothing.
                        if !result.humanizedParams.isEmpty {
                            Text(result.humanizedParams)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Client-side cuts are invisible otherwise — a filter
                        // quietly eating half the page would look like a bad search.
                        if model.hiddenCount > 0 {
                            Text(
                                "showing \(model.listings.count.formatted()) — \(model.hiddenCount.formatted()) hidden by filters"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    // The histogram describes everything loaded, so its axis
                    // doesn't jump as the title terms are typed.
                    if !model.loaded.isEmpty {
                        RecencyFilterView(listings: model.loaded, filters: $model.filters)
                    }

                    if let stats = model.stats {
                        StatsView(stats: stats, total: result.total, sold: model.resultsAreSold)
                    }
                }

                if model.listings.isEmpty {
                    ContentUnavailableView(
                        model.result == nil ? "Search Reverb" : "No listings matched",
                        systemImage: "guitars",
                        description: Text(
                            model.result == nil
                                ? "Search active listings, or flip to sold comps to see what gear actually clears for."
                                : model.hiddenCount > 0
                                    ? "\(model.hiddenCount.formatted()) loaded listings are hidden by the date range or title terms."
                                    : "Try loosening a filter."))
                        .padding(.top, 40)
                    Text(affiliationDisclaimer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if grid {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12
                    ) {
                        ForEach(model.listings) { listing in
                            ListingCard(listing: listing, sold: model.resultsAreSold)
                        }
                    }
                } else {
                    ForEach(model.listings) { listing in
                        ListingRow(listing: listing, sold: model.resultsAreSold)
                        Divider()
                    }
                }

                if model.canLoadMore {
                    Group {
                        switch paging {
                        case .more:
                            Button("Load more", action: model.loadMore).buttonStyle(.bordered)
                        case .scroll:
                            // Infinite scroll: the footer entering the viewport is the trigger.
                            Text(model.loading ? "Loading…" : " ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .all:
                            // Past the cap the walk stops and paging is manual again.
                            if model.canLoadAll {
                                Text("Loading page \(model.currentPage + 1) of \(model.totalPages)…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Button("Load more", action: model.loadMore).buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear { if paging == .scroll { model.loadMore() } }
                }
            }
            .padding()
        }
        // Load-all: walk the remaining pages one at a time, with a gap. Each fetch moves the id,
        // which restarts this task and schedules the next; an error stops the walk.
        .task(id: "\(paging.rawValue)-\(model.currentPage)-\(model.loading)") {
            guard paging == .all, !model.loading, model.errorMessage == nil, model.canLoadAll
            else { return }
            try? await Task.sleep(for: allPagesDelay)
            guard !Task.isCancelled else { return }
            model.loadMore()
        }
        .overlay { if model.loading { ProgressView() } }
    }
}

/// ponytail: one transient message at the bottom of the screen. That's the
/// whole toast system — no queue, no library.
private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(12)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct StatsView: View {
    let stats: PriceStats
    let total: Int
    let sold: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { cells }
                VStack(alignment: .leading, spacing: 8) { cells }
            }
            // The API caps at 50 pages; stats only ever describe what we loaded.
            Text(
                "Over the \(stats.count) loaded \(sold ? "sold listings" : "listings") — not all \(total.formatted()) matches."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var cells: some View {
        cell(sold ? "Lowest sold" : "Lowest ask", stats.format(stats.min), emphasis: false)
        cell(sold ? "Median sold" : "Median ask", stats.format(stats.median), emphasis: true)
        cell(sold ? "Highest sold" : "Highest ask", stats.format(stats.max), emphasis: false)
    }

    private func cell(_ label: String, _ value: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(emphasis ? .bold : .medium)
                .monospacedDigit()
        }
    }
}

private struct ListingRow: View {
    let listing: Listing
    let sold: Bool

    var body: some View {
        Link(destination: listing.webURL ?? URL(string: "https://reverb.com")!) {
            HStack(alignment: .top, spacing: 12) {
                Thumbnail(url: listing.thumbnailURL, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title).font(.subheadline).lineLimit(2)
                    PriceLine(listing: listing, sold: sold)
                    Text(listing.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ListingCard: View {
    let listing: Listing
    let sold: Bool

    var body: some View {
        Link(destination: listing.webURL ?? URL(string: "https://reverb.com")!) {
            VStack(alignment: .leading, spacing: 6) {
                Thumbnail(url: listing.thumbnailURL, size: nil)
                Text(listing.title).font(.caption).lineLimit(2)
                PriceLine(listing: listing, sold: sold)
                Text(listing.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PriceLine: View {
    let listing: Listing
    let sold: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(listing.price?.display ?? "—").fontWeight(.semibold).monospacedDigit()
            if sold, let ask = listing.originalPrice?.display {
                Text(ask).font(.caption).strikethrough().foregroundStyle(.secondary)
            }
            if let off = listing.discountPercent {
                Text("−\(off)%").font(.caption).fontWeight(.medium).foregroundStyle(.red)
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL?
    /// nil = fill the available width at 4:3 (grid); a number = fixed square (row).
    let size: CGFloat?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.15)
        }
        .frame(width: size, height: size)
        .aspectRatio(size == nil ? 4 / 3 : nil, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
    }
}
