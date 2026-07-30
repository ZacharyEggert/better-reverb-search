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

    /// The mode the *loaded* results were fetched in — not the pending toggle,
    /// so Ask/Off never render against active listings.
    private(set) var resultsAreSold = false

    private var task: Task<Void, Never>?

    var stats: PriceStats? { PriceStats(listings) }

    /// Reverb caps at 50 pages regardless of `total`.
    var canLoadMore: Bool {
        guard let result else { return false }
        return result.currentPage < min(result.totalPages, 50)
    }

    func search(page: Int = 1, appending: Bool = false) {
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
    }
}
