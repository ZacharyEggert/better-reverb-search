package llc.exnihilo.betterreverbsearch.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import llc.exnihilo.betterreverbsearch.R
import llc.exnihilo.betterreverbsearch.data.Billing
import llc.exnihilo.betterreverbsearch.data.BypassCode
import llc.exnihilo.betterreverbsearch.data.Listing
import llc.exnihilo.betterreverbsearch.data.PriceStats
import llc.exnihilo.betterreverbsearch.data.Prefs
import llc.exnihilo.betterreverbsearch.data.QueryQuota
import llc.exnihilo.betterreverbsearch.data.formatted

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(model: SearchViewModel = viewModel()) {
  var showFilters by remember { mutableStateOf(false) }
  var showApiKey by remember { mutableStateOf(false) }
  var showPromoCode by remember { mutableStateOf(false) }
  var showMenu by remember { mutableStateOf(false) }
  var toast by remember { mutableStateOf<String?>(null) }
  var grid by remember { mutableStateOf(Prefs.gridView) }
  var paging by remember { mutableStateOf(Paging.stored()) }
  // Mirrors QueryQuota.dailyLimit so a promo code taking effect re-renders the count — the quota
  // itself is an object with nothing to observe.
  var dailyLimit by remember { mutableStateOf(QueryQuota.dailyLimit) }
  val subscribed by Billing.isSubscribed.collectAsStateWithLifecycle()

  // Re-check the stored promo code once per launch.
  LaunchedEffect(Unit) {
    if (BypassCode.refresh() == BypassCode.Check.UNREACHABLE) {
      toast = "Promo service unreachable — daily limit stays at ${QueryQuota.dailyLimit}."
    }
    dailyLimit = QueryQuota.dailyLimit
  }

  Scaffold(
    topBar = {
      TopAppBar(
        // titleMedium: the full name overflows at titleLarge next to three actions.
        title = {
          Text(
            "Better Reverb Search",
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
        },
        actions = {
          IconButton(
            onClick = {
              grid = !grid
              Prefs.gridView = grid
            }
          ) {
            if (grid) Icon(Icons.AutoMirrored.Filled.List, contentDescription = "List view")
            else Icon(painterResource(R.drawable.ic_grid), contentDescription = "Grid view")
          }
          IconButton(onClick = { showFilters = true }) {
            Icon(painterResource(R.drawable.ic_filter), contentDescription = "Filters")
          }
          Box {
            IconButton(onClick = { showMenu = true }) {
              Icon(Icons.Default.MoreVert, contentDescription = "More")
            }
            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
              if (!subscribed && QueryQuota.offerUpgrade) {
                DropdownMenuItem(
                  text = { Text("${QueryQuota.remaining} of $dailyLimit searches left today") },
                  leadingIcon = { Icon(painterResource(R.drawable.ic_infinity), null) },
                  onClick = {
                    showMenu = false
                    model.showPaywall = true
                  },
                )
              }
              Paging.entries.forEach { mode ->
                DropdownMenuItem(
                  text = { Text(mode.label) },
                  leadingIcon = {
                    if (mode == paging) Icon(Icons.Default.Check, null)
                    else Spacer(Modifier.size(24.dp))
                  },
                  onClick = {
                    showMenu = false
                    paging = mode
                    Prefs.paging = mode.name
                  },
                )
              }
              HorizontalDivider()
              DropdownMenuItem(
                text = { Text("API key") },
                leadingIcon = { Icon(Icons.Default.Lock, null) },
                onClick = {
                  showMenu = false
                  showApiKey = true
                },
              )
              DropdownMenuItem(
                text = { Text("Promo code") },
                leadingIcon = { Icon(painterResource(R.drawable.ic_tag), null) },
                onClick = {
                  showMenu = false
                  showPromoCode = true
                },
              )
              DropdownMenuItem(
                text = { Text("Clear", color = MaterialTheme.colorScheme.error) },
                leadingIcon = {
                  Icon(Icons.Default.Clear, null, tint = MaterialTheme.colorScheme.error)
                },
                onClick = {
                  showMenu = false
                  model.clear()
                },
              )
            }
          }
        },
      )
    },
    snackbarHost = {
      toast?.let {
        Snackbar(modifier = Modifier.padding(16.dp)) { Text(it, textAlign = TextAlign.Center) }
      }
    },
  ) { padding ->
    Column(Modifier.padding(padding).fillMaxSize()) {
      SearchField(model)
      SoldToggle(model)
      Box(Modifier.fillMaxSize()) {
        Results(model, grid, paging)
        if (model.loading) CircularProgressIndicator(Modifier.align(Alignment.Center))
      }
    }
  }

  // Load-all: walk the remaining pages one at a time, with a gap — Reverb rate-limits. Each fetch
  // flips `loading`, which re-runs this effect and schedules the next; an error stops the walk.
  LaunchedEffect(paging, model.result?.currentPage, model.loading, model.errorMessage) {
    if (paging == Paging.ALL && !model.loading && model.errorMessage == null && model.canLoadMore) {
      delay(ALL_PAGES_DELAY_MS)
      model.loadMore()
    }
  }

  LaunchedEffect(toast) {
    if (toast != null) {
      delay(4000)
      toast = null
    }
  }

  if (showFilters) {
    FiltersSheet(
      query = model.query,
      filters = model.filters,
      onDismiss = { showFilters = false },
      onFilters = { model.filters = it },
      onApply = {
        model.query = it
        showFilters = false
        model.search()
      },
    )
  }
  if (showApiKey) ApiKeySheet(onDismiss = { showApiKey = false })
  if (showPromoCode) {
    // Code entered or cleared — the limit may have moved.
    PromoCodeSheet(
      onDismiss = {
        showPromoCode = false
        dailyLimit = QueryQuota.dailyLimit
      }
    )
  }
  if (model.showPaywall) PaywallSheet(onDismiss = { model.showPaywall = false })
}

@Composable
private fun SearchField(model: SearchViewModel) {
  OutlinedTextField(
    value = model.query.query,
    onValueChange = { model.query = model.query.copy(query = it) },
    placeholder = { Text("e.g. 1963 Stratocaster") },
    leadingIcon = {
      Icon(Icons.Default.Search, contentDescription = null)
    },
    trailingIcon = {
      if (model.query.query.isNotEmpty()) {
        IconButton(onClick = { model.query = model.query.copy(query = "") }) {
          Icon(Icons.Default.Clear, contentDescription = "Clear")
        }
      }
    },
    singleLine = true,
    shape = RoundedCornerShape(28.dp),
    colors =
      OutlinedTextFieldDefaults.colors(
        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
      ),
    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
    keyboardActions = KeyboardActions(onSearch = { model.search() }),
    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
  )
}

@Composable
private fun SoldToggle(model: SearchViewModel) {
  // Sold comps answer "what did this clear for", not "what are people asking".
  val sold = model.query.showOnlySold
  Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
    FilterChip(
      selected = sold,
      onClick = {
        model.query = model.query.copy(showOnlySold = !sold)
        model.search()
      },
      label = { Text(if (sold) "Sold comps" else "Active") },
      leadingIcon = {
        Icon(
          painterResource(R.drawable.ic_tag),
          contentDescription = null,
          modifier = Modifier.size(FilterChipDefaults.IconSize),
        )
      },
    )
  }
}

@Composable
private fun Results(model: SearchViewModel, grid: Boolean, paging: Paging) {
  val result = model.result
  val state = rememberLazyGridState()

  // Infinite scroll: fetch the next page once the tail of the list is in view. `loadMore` ignores
  // the call while a fetch is in flight, so a fast scroll can't double-fetch.
  if (paging == Paging.SCROLL) {
    LaunchedEffect(state) {
      snapshotFlow { state.layoutInfo.visibleItemsInfo.lastOrNull()?.index }
        .collect { last ->
          if (last != null && last >= state.layoutInfo.totalItemsCount - 3) model.loadMore()
        }
    }
  }

  LazyVerticalGrid(
    state = state,
    columns = if (grid) GridCells.Adaptive(150.dp) else GridCells.Fixed(1),
    contentPadding = PaddingValues(16.dp),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalArrangement = Arrangement.spacedBy(if (grid) 12.dp else 8.dp),
  ) {
    fun header(content: @Composable () -> Unit) =
      item(span = { GridItemSpan(maxLineSpan) }) { content() }

    model.errorMessage?.let { message ->
      header {
        Text(
          message,
          color = MaterialTheme.colorScheme.onErrorContainer,
          style = MaterialTheme.typography.bodyMedium,
          modifier =
            Modifier.fillMaxWidth()
              .clip(RoundedCornerShape(12.dp))
              .background(MaterialTheme.colorScheme.errorContainer)
              .padding(16.dp),
        )
      }
    }

    if (result != null) {
      header {
        Column {
          Text("${result.total.formatted()} matches", style = MaterialTheme.typography.titleMedium)
          // Reverb's echo of how it parsed the filters — the cheapest guard against a filter
          // silently doing nothing.
          if (result.humanizedParams.isNotEmpty()) {
            Text(
              result.humanizedParams,
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
          // Client-side cuts are invisible otherwise — a filter quietly eating half the page
          // would look like a bad search.
          if (model.hiddenCount > 0) {
            Text(
              "showing ${model.listings.size.formatted()} — ${model.hiddenCount.formatted()} hidden by filters",
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
      }
      // The histogram describes everything loaded, so its axis doesn't jump as the title terms
      // are typed.
      if (model.loaded.isNotEmpty()) {
        header { RecencyFilter(model.loaded, model.filters) { model.filters = it } }
      }
      model.stats?.let { stats ->
        header { StatsCard(stats, result.total, model.resultsAreSold) }
      }
    }

    if (model.listings.isEmpty()) {
      header {
        Column(
          Modifier.fillMaxWidth().padding(top = 40.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
        ) {
          Icon(
            painterResource(R.drawable.ic_glyph),
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(56.dp).padding(bottom = 12.dp),
          )
          Text(
            if (result == null) "Search Reverb" else "No listings matched",
            style = MaterialTheme.typography.titleLarge,
          )
          Spacer(Modifier.padding(4.dp))
          Text(
            if (result == null)
              "Search active listings, or flip to sold comps to see what gear actually clears for."
            else if (model.hiddenCount > 0)
              "${model.hiddenCount.formatted()} loaded listings are hidden by the date range or title terms."
            else "Try loosening a filter.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
          )
          Text(
            AFFILIATION_DISCLAIMER,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 24.dp),
          )
        }
      }
    } else {
      items(model.listings, key = { it.id }) { listing ->
        if (grid) ListingCard(listing, model.resultsAreSold)
        else {
          Column {
            ListingRow(listing, model.resultsAreSold)
            HorizontalDivider(Modifier.padding(top = 8.dp))
          }
        }
      }
    }

    if (model.canLoadMore) {
      header {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
          when (paging) {
            Paging.MORE -> OutlinedButton(onClick = model::loadMore) { Text("Load more") }
            Paging.SCROLL ->
              if (model.loading) {
                Text(
                  "Loading…",
                  style = MaterialTheme.typography.bodySmall,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
              }
            Paging.ALL ->
              Text(
                "Loading page ${model.result?.currentPage?.plus(1)} of ${model.totalPages}…",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
          }
        }
      }
    }
  }
}

@Composable
private fun StatsCard(stats: PriceStats, total: Int, sold: Boolean) {
  Card(
    Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    colors =
      CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        StatCell(if (sold) "Lowest sold" else "Lowest ask", stats.format(stats.min), false)
        StatCell(if (sold) "Median sold" else "Median ask", stats.format(stats.median), true)
        StatCell(if (sold) "Highest sold" else "Highest ask", stats.format(stats.max), false)
      }
      // The API caps at 50 pages; stats only ever describe what we loaded.
      Text(
        "Over the ${stats.count} loaded ${if (sold) "sold listings" else "listings"} — not all ${total.formatted()} matches.",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
private fun StatCell(label: String, value: String, emphasis: Boolean) {
  Column {
    Text(
      label,
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(
      value,
      style = MaterialTheme.typography.titleMedium,
      fontWeight = if (emphasis) FontWeight.Bold else FontWeight.Medium,
    )
  }
}

@Composable
private fun ListingRow(listing: Listing, sold: Boolean) {
  val uriHandler = LocalUriHandler.current
  Row(
    Modifier.fillMaxWidth().clickable { uriHandler.openUri(listing.webUrl ?: REVERB_HOME) },
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Thumbnail(listing.thumbnailUrl, Modifier.size(64.dp))
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(listing.title, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
      PriceLine(listing, sold)
      Text(
        listing.subtitle,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun ListingCard(listing: Listing, sold: Boolean) {
  val uriHandler = LocalUriHandler.current
  Column(
    Modifier.clickable { uriHandler.openUri(listing.webUrl ?: REVERB_HOME) },
    verticalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Thumbnail(listing.thumbnailUrl, Modifier.fillMaxWidth().aspectRatio(4f / 3f))
    Text(listing.title, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
    PriceLine(listing, sold)
    Text(
      listing.subtitle,
      style = MaterialTheme.typography.labelSmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
private fun PriceLine(listing: Listing, sold: Boolean) {
  Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(listing.price?.display ?: "—", fontWeight = FontWeight.SemiBold)
    if (sold) {
      listing.originalPrice?.display?.let {
        Text(
          it,
          style = MaterialTheme.typography.bodySmall,
          textDecoration = TextDecoration.LineThrough,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
    listing.discountPercent?.let {
      Text(
        "−$it%",
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.error,
      )
    }
  }
}

@Composable
private fun Thumbnail(url: String?, modifier: Modifier) {
  AsyncImage(
    model = url,
    contentDescription = null,
    contentScale = ContentScale.Crop,
    modifier = modifier.clip(RoundedCornerShape(8.dp)).background(Color.Gray.copy(alpha = 0.15f)),
  )
}

/** How more results are reached. Persisted by name in [Prefs.paging]. */
enum class Paging(val label: String) {
  MORE("Load more"),
  SCROLL("Infinite scroll"),
  ALL("Load all pages");

  companion object {
    fun stored(): Paging = entries.firstOrNull { it.name == Prefs.paging } ?: MORE
  }
}

/** Gap between the automatic page fetches in [Paging.ALL] — Reverb rate-limits. */
private const val ALL_PAGES_DELAY_MS = 500L

private const val REVERB_HOME = "https://reverb.com"

/** Nominative use of the Reverb mark — say plainly whose app this isn't. */
const val AFFILIATION_DISCLAIMER = "Created by Ex Nihilo LLC. Not affiliated with Reverb.com LLC."
