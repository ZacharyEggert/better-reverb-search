package llc.exnihilo.betterreverbsearch.ui.main

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlin.math.min
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import llc.exnihilo.betterreverbsearch.data.ApiKeyStore
import llc.exnihilo.betterreverbsearch.data.Billing
import llc.exnihilo.betterreverbsearch.data.Listing
import llc.exnihilo.betterreverbsearch.data.ListingFilters
import llc.exnihilo.betterreverbsearch.data.PriceStats
import llc.exnihilo.betterreverbsearch.data.QueryQuota
import llc.exnihilo.betterreverbsearch.data.ReverbApi
import llc.exnihilo.betterreverbsearch.data.SearchQuery
import llc.exnihilo.betterreverbsearch.data.SearchResult

/**
 * Port of `use-search.ts`: searches fire from an explicit submit, never from a query-change
 * observer, so there is no race to lose. A newer search cancels the in-flight one.
 */
class SearchViewModel : ViewModel() {
  var query by mutableStateOf(SearchQuery())

  /** Client-side cuts over the loaded listings — see [ListingFilters]. */
  var filters by mutableStateOf(ListingFilters())

  /** Everything fetched so far, before [filters]. */
  var loaded by mutableStateOf<List<Listing>>(emptyList())
    private set

  /** What the UI shows: the loaded listings minus the client-side cuts. */
  val listings: List<Listing>
    get() = loaded.filter { filters.matches(it) }

  /** How many loaded listings the filters are currently removing. */
  val hiddenCount: Int
    get() = loaded.size - listings.size

  var result by mutableStateOf<SearchResult?>(null)
    private set

  var errorMessage by mutableStateOf<String?>(null)
    private set

  var loading by mutableStateOf(false)
    private set

  /** Set when a search is refused for want of quota; drives the paywall sheet. */
  var showPaywall by mutableStateOf(false)

  /**
   * The mode the *loaded* results were fetched in — not the pending toggle, so Ask/Off never render
   * against active listings.
   */
  var resultsAreSold by mutableStateOf(false)
    private set

  private var job: Job? = null

  /**
   * The search term quota was last spent on. Refining filters, flipping to sold, or paging re-runs
   * the same term — only a new term costs a query.
   */
  private var chargedTerm: String? = null

  /** Free re-runs left on [chargedTerm], so filters can't be toggled forever on one paid search. */
  private var rerunsLeft = 0

  /** Stats describe what's on screen, so they move with the filters. */
  val stats: PriceStats?
    get() = PriceStats.of(listings)

  /** Reverb caps at 50 pages regardless of `total`. */
  val totalPages: Int
    get() = result?.let { min(it.totalPages, 50) } ?: 0

  val canLoadMore: Boolean
    get() = (result?.currentPage ?: 0) < totalPages

  fun search(page: Int = 1, appending: Boolean = false) {
    // Only a new search term spends quota — paging and re-running the same term under different
    // filters are free, so neither `loadMore` nor a filter tweak can strand you mid-list.
    val term = query.query.trim()
    // A blank term is a browse, not a search — free, and it leaves the charged term's re-run budget
    // alone.
    if (!appending && term.isNotEmpty()) {
      val isRerun = term == chargedTerm && rerunsLeft > 0
      if (!isRerun && !Billing.isSubscribed.value) {
        if (QueryQuota.remaining <= 0) {
          showPaywall = true
          return
        }
        QueryQuota.consume()
      }
      chargedTerm = term
      rerunsLeft = if (isRerun) rerunsLeft - 1 else RERUN_CAP
    }

    job?.cancel()
    query = query.copy(page = page)
    val query = query
    loading = true
    errorMessage = null

    job =
      viewModelScope.launch {
        try {
          val result = ReverbApi.search(query, ApiKeyStore.load())
          this@SearchViewModel.result = result
          loaded = if (appending) loaded + result.listings else result.listings
          resultsAreSold = query.showOnlySold
          loading = false
        } catch (e: kotlinx.coroutines.CancellationException) {
          throw e
        } catch (e: Exception) {
          errorMessage = e.message
          loading = false
        }
      }
  }

  fun loadMore() {
    val result = result ?: return
    if (!canLoadMore || loading) return
    search(page = result.currentPage + 1, appending = true)
  }

  /**
   * Clears filters and results. The list/grid choice is a display preference, not part of the
   * search, so it lives outside this model and survives.
   */
  fun clear() {
    job?.cancel()
    query = SearchQuery()
    filters = ListingFilters()
    loaded = emptyList()
    result = null
    errorMessage = null
    loading = false
    resultsAreSold = false
    chargedTerm = null
    rerunsLeft = 0
  }

  private companion object {
    const val RERUN_CAP = 10
  }
}
