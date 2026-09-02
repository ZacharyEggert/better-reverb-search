import Foundation
import Testing

@testable import ReverbSearch

/// Talks to api.reverb.com for real. These are the wire-format canary: if Reverb
/// renames a field, `Failable` would quietly hand the app an empty page and only
/// these tests would notice.
///
/// Run with the Live test plan (it sets RUN_LIVE_TESTS); the Offline plan skips
/// them. Serialized with a 500ms gap per request so a run can't trip the rate
/// limiter.
@Suite("Live", .serialized, .enabled(if: liveTestsEnabled))
struct LiveTests {

    /// Reverb answers one caller at a time here: `.serialized` on the parent covers
    /// its descendants, so no two live tests can burst requests past the pacing.
    @Suite("Reverb API")
    struct APITests {
        private func search(_ query: SearchQuery) async throws -> SearchResult {
            try await paceLiveRequest()
            return try await ReverbAPI.search(query, apiKey: APIKeyStore.load())
        }

        @Test("A plain search comes back with listings and a page count")
        func basicSearch() async throws {
            let result = try await search(SearchQuery(query: "stratocaster", perPage: 12))
            #expect(result.total > 0)
            #expect(result.currentPage == 1)
            #expect(result.totalPages > 0)
            #expect(!result.listings.isEmpty)
        }

        @Test("Every listing decodes with the fields the UI renders")
        func wireFormat() async throws {
            let result = try await search(SearchQuery(query: "fender telecaster", perPage: 24))
            // `Failable` drops what it can't decode — a shrunken page means the wire
            // format moved. A stray bad listing is normal; half a page is not.
            #expect(result.listings.count >= 20)
            for listing in result.listings {
                #expect(listing.id > 0)
                #expect(!listing.title.isEmpty)
                #expect(listing.webURL != nil)
            }
            // Prices and photos are what the list rows are made of.
            #expect(result.listings.contains { $0.price?.amountCents ?? 0 > 0 })
            #expect(result.listings.contains { $0.thumbnailURL != nil })
            #expect(result.listings.contains { $0.monthsAgo() != nil })
        }

        @Test("Sold comps come back sold, with URLs that don't 404")
        func soldComps() async throws {
            let result = try await search(
                SearchQuery(query: "stratocaster", showOnlySold: true, perPage: 12))
            #expect(!result.listings.isEmpty)
            let sold = result.listings.filter { $0.state?.slug == "sold" }
            #expect(sold.count == result.listings.count)
            #expect(sold.allSatisfy { $0.webURL?.query()?.contains("show_sold=true") == true })
        }

        @Test("Reverb echoes the filters it actually applied")
        func humanizedParams() async throws {
            let result = try await search(
                SearchQuery(make: "Fender", productType: .electricGuitars, perPage: 12))
            #expect(!result.humanizedParams.isEmpty)
            #expect(result.humanizedParams.localizedCaseInsensitiveContains("fender"))
        }

        @Test("Price bounds are honoured, not silently ignored")
        func priceFilter() async throws {
            let result = try await search(
                SearchQuery(query: "stratocaster", priceMin: 2000, priceMax: 4000, perPage: 24))
            let dollars = result.listings.compactMap { $0.price?.amountCents }.map { Double($0) / 100 }
            #expect(!dollars.isEmpty)
            // Reverb's own tolerance on the bound is a few percent; a filter it ignored
            // would put four-figure gaps on both sides of the range.
            #expect(dollars.allSatisfy { $0 >= 1800 && $0 <= 4400 })
        }

        @Test("per_page is respected, so paging math means something")
        func perPage() async throws {
            let result = try await search(SearchQuery(query: "guitar", perPage: 12))
            #expect(result.listings.count <= 12)
            #expect(result.listings.count >= 10)
        }

        @Test("Page 2 is a different page, not the first one again")
        func pagingReturnsNewListings() async throws {
            let query = SearchQuery(query: "les paul", sort: .newest, perPage: 12)
            let first = try await search(query)
            var next = query
            next.page = 2
            let second = try await search(next)
            #expect(second.currentPage == 2)
            let overlap = Set(first.listings.map(\.id)).intersection(second.listings.map(\.id))
            #expect(overlap.isEmpty)
        }

        @Test("A search nothing matches is an empty result, not an error")
        func noMatches() async throws {
            let result = try await search(
                SearchQuery(query: "zzzqqq-not-a-real-instrument-xyzzy", perPage: 12))
            #expect(result.listings.isEmpty)
            #expect(result.total == 0)
        }

        @Test("A junk API key doesn't break search — Reverb ignores it on public listings")
        func badAPIKeyStillSearches() async throws {
            try await paceLiveRequest()
            // Confirmed against the live API: search answers unauthenticated, and an
            // unusable token is ignored rather than rejected. So a stale key in the
            // keychain can't lock a user out of the app.
            let result = try await ReverbAPI.search(
                SearchQuery(query: "stratocaster", perPage: 12), apiKey: "not-a-real-token")
            #expect(!result.listings.isEmpty)
        }
    }

    /// The model against the real API: quota accounting, appending, and cancellation
    /// are only observable once a search actually completes.
    @MainActor
    @Suite("Search model")
    struct SearchModelTests {
        /// A promo-code limit rather than the free five, so a full run can't be cut
        /// short by its own quota — and the tester's real counters go back after.
        private func sandbox() -> DefaultsSandbox {
            let sandbox = DefaultsSandbox("quota", "bypassCode")
            UserDefaults.standard.set("test", forKey: "bypassCode")
            BypassCode.verified = true
            return sandbox
        }

        private func run(_ model: SearchModel, page: Int = 1, appending: Bool = false) async throws {
            try await paceLiveRequest()
            model.search(page: page, appending: appending)
            await model.task?.value
        }

        @Test("A search fills in results, stats, and the page count")
        func search() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "stratocaster"
            model.query.perPage = 12
            try await run(model)

            #expect(model.errorMessage == nil)
            #expect(!model.loading)
            #expect(model.result?.total ?? 0 > 0)
            #expect(!model.listings.isEmpty)
            #expect(model.stats != nil)
            #expect(model.totalPages > 0)
            #expect(model.canLoadMore)
        }

        @Test("Load more appends the next page instead of replacing it")
        func loadMoreAppends() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "les paul"
            model.query.perPage = 12
            try await run(model)
            let first = model.listings.count
            let firstIDs = Set(model.listings.map(\.id))

            try await paceLiveRequest()
            model.loadMore()
            await model.task?.value

            #expect(model.currentPage == 2)
            #expect(model.listings.count > first)
            #expect(Set(model.listings.map(\.id)).isSuperset(of: firstIDs))
        }

        @Test("Only a new term spends quota — paging and refiltering are free")
        func quotaAccounting() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "telecaster"
            model.query.perPage = 12

            let start = QueryQuota.remaining
            try await run(model)
            #expect(QueryQuota.remaining == start - 1)

            // Same term, different filter: a re-run, not a new search.
            model.query.condition = .excellent
            try await run(model)
            #expect(QueryQuota.remaining == start - 1)

            // Paging is free too.
            try await paceLiveRequest()
            model.loadMore()
            await model.task?.value
            #expect(QueryQuota.remaining == start - 1)

            // A different term is a new search.
            model.query.query = "jazzmaster"
            try await run(model)
            #expect(QueryQuota.remaining == start - 2)
        }

        @Test("A newer search cancels the one in flight rather than racing it")
        func newerSearchWins() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "stratocaster"
            model.query.perPage = 50
            model.search()

            try await paceLiveRequest()
            model.query.query = "jazz bass"
            model.query.perPage = 12
            model.search()
            await model.task?.value

            #expect(!model.loading)
            #expect(model.errorMessage == nil)
            #expect(model.listings.count <= 12)
        }

        @Test("Sold results are flagged as sold, so the UI never labels asks as clears")
        func soldModeFlag() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "stratocaster"
            model.query.perPage = 12
            model.query.showOnlySold = true
            try await run(model)
            #expect(model.resultsAreSold)
            #expect(model.listings.allSatisfy { $0.state?.slug == "sold" })
        }

        @Test("Client-side filters cut the loaded listings without another request")
        func filtersAreClientSide() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "stratocaster"
            model.query.perPage = 24
            try await run(model)
            let loaded = model.listings.count

            model.filters.whitelist = "zzzqqq-matches-nothing"
            #expect(model.listings.isEmpty)
            #expect(model.hiddenCount == loaded)
            #expect(model.stats == nil)

            model.filters = ListingFilters()
            #expect(model.listings.count == loaded)
        }

        @Test("A search too broad to load in full says so once")
        func broadSearchNotice() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "guitar"
            model.query.perPage = 12
            try await run(model)
            #expect(model.result?.total ?? 0 > SearchModel.loadAllCap)
            #expect(model.notice?.contains("more specific") == true)
        }

        @Test("A nonsense term is an empty result with no error banner")
        func noMatches() async throws {
            let sandbox = sandbox()
            defer { sandbox.restore() }
            let model = SearchModel()
            model.query.query = "zzzqqq-not-a-real-instrument-xyzzy"
            try await run(model)
            #expect(model.errorMessage == nil)
            #expect(model.listings.isEmpty)
            #expect(model.result?.total == 0)
            #expect(!model.canLoadMore)
        }
    }
}
