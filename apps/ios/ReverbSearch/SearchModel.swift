import Foundation

/// Port of `use-search.ts`: searches fire from an explicit submit, never from a
/// query-change observer, so there is no race to lose. A newer search cancels
/// the in-flight one.
@MainActor
@Observable
final class SearchModel {
    var query = SearchQuery()
    var listings: [Listing] = []
    var result: SearchResult?
    var errorMessage: String?
    var loading = false
    /// Set when a search is refused for want of quota; drives the paywall sheet.
    var showPaywall = false

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

    var stats: PriceStats? { PriceStats(listings) }

    /// Reverb caps at 50 pages regardless of `total`.
    var canLoadMore: Bool {
        guard let result else { return false }
        return result.currentPage < min(result.totalPages, 50)
    }

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
        query.page = page
        let query = query
        loading = true
        errorMessage = nil

        task = Task {
            do {
                let result = try await ReverbAPI.search(query, apiKey: APIKeyStore.load())
                guard !Task.isCancelled else { return }
                self.result = result
                self.listings = appending ? self.listings + result.listings : result.listings
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
        guard let result, canLoadMore, !loading else { return }
        search(page: result.currentPage + 1, appending: true)
    }

    /// Clears filters and results. The list/grid choice is a display preference,
    /// not part of the search, so it lives outside this model and survives.
    func clear() {
        task?.cancel()
        query = SearchQuery()
        listings = []
        result = nil
        errorMessage = nil
        loading = false
        resultsAreSold = false
        chargedTerm = nil
        rerunsLeft = 0
    }
}
