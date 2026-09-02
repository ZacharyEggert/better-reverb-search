import Foundation
import Testing

@testable import ReverbSearch

/// The rejection path, offline: a search with nothing in it never reaches the
/// network, and says what's missing. Everything past the guard needs Reverb —
/// see `LiveTests`.
@MainActor
@Suite("Search model — empty-search guard", .serialized,
       .disabled(if: liveTestsEnabled, quotaSuiteReason))
struct SearchModelGuardTests {
    @Test("An empty search is refused before any request is made")
    func emptySearchBlocked() {
        let model = SearchModel()
        model.search()
        #expect(model.task == nil)
        #expect(model.result == nil)
        #expect(!model.loading)
        #expect(model.errorMessage == SearchQuery.emptyHint)
    }

    @Test("The refusal says what to type and where the filters are")
    func hintIsActionable() {
        #expect(SearchQuery.emptyHint.contains("search term"))
        #expect(SearchQuery.emptyHint.contains("Filters"))
    }

    @Test("Whitespace isn't input")
    func whitespaceIsEmpty() {
        let model = SearchModel()
        model.query.query = "   \n "
        model.search()
        #expect(model.task == nil)
        #expect(model.errorMessage == SearchQuery.emptyHint)
        // And the whitespace is normalised away rather than kept as a term.
        #expect(model.query.query.isEmpty)
    }

    @Test("Flipping to sold comps with nothing entered is still an empty search")
    func soldToggleAloneBlocked() {
        let model = SearchModel()
        model.query.showOnlySold = true
        model.search()
        #expect(model.task == nil)
        #expect(model.errorMessage == SearchQuery.emptyHint)
    }

    @Test("A blocked search spends no quota")
    func blockedSearchIsFree() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        let before = QueryQuota.remaining
        let model = SearchModel()
        model.search()
        model.search()
        #expect(QueryQuota.remaining == before)
    }

    @Test("Out of quota, a search raises the paywall instead of erroring")
    func paywallInsteadOfError() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        // A subscriber has no quota to run out of, so there is nothing to assert.
        guard !Store.shared.isSubscribed else { return }
        for _ in 0..<QueryQuota.dailyLimit { QueryQuota.consume() }
        let model = SearchModel()
        model.query.query = "stratocaster"
        model.search()
        #expect(model.showPaywall)
        #expect(model.task == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("Filters alone are a real search — no term required")
    func filtersAloneSearch() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        let model = SearchModel()
        model.query.make = "Fender"
        model.search()
        #expect(model.errorMessage == nil)
        #expect(model.task != nil)
        // The assertion is about the guard letting it through; the request itself
        // is cancelled on the spot so the offline plan stays offline.
        model.task?.cancel()
        // A browse with no term costs nothing.
        #expect(QueryQuota.used == 0)
    }

    @Test("Clear resets the search, the filters, and the error")
    func clear() {
        let model = SearchModel()
        model.query.query = "strat"
        model.filters.blacklist = "relic"
        model.search()
        model.clear()
        #expect(model.query == SearchQuery())
        #expect(model.filters == ListingFilters())
        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.loading)
        #expect(model.listings.isEmpty)
    }

    @Test("Paging is refused while there is nothing to page through")
    func loadMoreNeedsResults() {
        let model = SearchModel()
        #expect(!model.canLoadMore)
        model.loadMore()
        #expect(model.task == nil)
        #expect(model.errorMessage == nil)
    }
}
