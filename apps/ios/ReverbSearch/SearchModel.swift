import Foundation

/// Port of `use-search.ts`: searches fire from an explicit submit, never from a
/// query-change observer, so there is no race to lose. A newer search cancels
/// the in-flight one.
@MainActor
@Observable
final class SearchModel {
    var query = SearchQuery()
    /// Client-side cuts over the loaded listings — see `ListingFilters`.
    var filters = ListingFilters()
    /// Everything fetched so far, before `filters`.
    private(set) var loaded: [Listing] = []
    var result: SearchResult?
    var errorMessage: String?
    var loading = false
    /// Set when a search is refused for want of quota; drives the paywall sheet.
    var showPaywall = false

    /// Load-all walks every page, so it asks for the biggest page Reverb allows —
    /// fewest requests, and the per-page choice in Filters is overridden while it's on.
    var loadAllPages = false {
        didSet {
            // A half-loaded result set can't switch page size mid-walk without
            // skipping or repeating listings — restart from page 1 instead.
            guard loadAllPages, query.perPage != SearchQuery.maxPerPage, result != nil else { return }
            search()
        }
    }

    /// The mode the *loaded* results were fetched in — not the pending toggle,
    /// so Ask/Off never render against active listings.
    private(set) var resultsAreSold = false

    private var task: Task<Void, Never>?

    /// The search term quota was last spent on. Refining filters, flipping to
    /// sold, or paging re-runs the same term — only a new term costs a query.
    private var chargedTerm: String?
    /// Free re-runs left on `chargedTerm`, so filters can't be toggled forever
    /// on one paid search.
    private var rerunsLeft = 0
    private static let rerunCap = 10

    /// What the UI shows: the loaded listings minus the client-side cuts.
    var listings: [Listing] { loaded.filter { filters.matches($0) } }

    /// How many loaded listings the filters are currently removing.
    var hiddenCount: Int { loaded.count - listings.count }

    /// Stats describe what's on screen, so they move with the filters.
    var stats: PriceStats? { PriceStats(listings) }

    /// Reverb caps at 50 pages regardless of `total`.
    var totalPages: Int { result.map { min($0.totalPages, 50) } ?? 0 }

    var currentPage: Int { result?.currentPage ?? 0 }

    var canLoadMore: Bool { currentPage < totalPages }

    /// Ten pages of 50 — past that a "load all" is fetching more than anyone reads,
    /// and most searches don't have this many. The walk stops; the button stays.
    static let loadAllCap = 500

    /// Whether the load-all walk keeps going, as opposed to handing back the button.
    var canLoadAll: Bool { canLoadMore && loaded.count < Self.loadAllCap }

    func search(page: Int = 1, appending: Bool = false) {
        // Only a new search term spends quota — paging and re-running the same
        // term under different filters are free, so neither `loadMore` nor a
        // filter tweak can strand you mid-list.
        let term = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank term is a browse, not a search — free, and it leaves the
        // charged term's re-run budget alone.
        if !appending && !term.isEmpty {
            let isRerun = term == chargedTerm && rerunsLeft > 0
            if !isRerun && !Store.shared.isSubscribed {
                guard QueryQuota.remaining > 0 else {
                    showPaywall = true
                    return
                }
                QueryQuota.consume()
            }
            chargedTerm = term
            rerunsLeft = isRerun ? rerunsLeft - 1 : Self.rerunCap
        }

        task?.cancel()
        if loadAllPages { query.perPage = SearchQuery.maxPerPage }
        query.page = page
        let query = query
        loading = true
        errorMessage = nil

        task = Task {
            do {
                let result = try await ReverbAPI.search(query, apiKey: APIKeyStore.load())
                guard !Task.isCancelled else { return }
                self.result = result
                self.loaded = appending ? self.loaded + result.listings : result.listings
                self.resultsAreSold = query.showOnlySold
                self.loading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.loading = false
            }
        }
    }

    func loadMore() {
        guard canLoadMore, !loading else { return }
        search(page: currentPage + 1, appending: true)
    }

    /// Clears filters and results. The list/grid choice is a display preference,
    /// not part of the search, so it lives outside this model and survives.
    func clear() {
        task?.cancel()
        query = SearchQuery()
        filters = ListingFilters()
        loaded = []
        result = nil
        errorMessage = nil
        loading = false
        resultsAreSold = false
        chargedTerm = nil
        rerunsLeft = 0
    }
}
