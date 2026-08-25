package llc.exnihilo.betterreverbsearch.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import llc.exnihilo.betterreverbsearch.data.Listing
import llc.exnihilo.betterreverbsearch.data.ListingFilters
import llc.exnihilo.betterreverbsearch.data.Recency

/**
 * Histogram of when the loaded listings went live, with a draggable window over it. Port of
 * `recency-filter.tsx`: bars are 3-month buckets, the window is a [newest, oldest] pair in months
 * ago, and the last bucket is open-ended.
 *
 * The chart describes the loaded sample only — Reverb has no date-range param, so this is a
 * client-side cut like the title terms.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecencyFilter(
  /** Everything loaded, before any client-side cut: the axis must not jump as terms are typed. */
  listings: List<Listing>,
  filters: ListingFilters,
  onChange: (ListingFilters) -> Unit,
) {
  val counts = Recency.buckets(listings)
  val span = Recency.span(counts.size)
  // The stored bounds clamped to the current span, which grows as older pages are appended.
  val oldest = minOf(filters.oldestMonths ?: span, span)
  val newest = minOf(filters.newestMonths, oldest - Recency.BUCKET_MONTHS)

  Card(
    Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Label("Listed date range")
        Label(
          "${if (newest == 0) "now" else "$newest mo ago"} – ${if (oldest >= span) "oldest" else "$oldest mo ago"}"
        )
      }

      val peak = maxOf(counts.max(), 1)
      Row(
        Modifier.fillMaxWidth().height(64.dp).semantics { contentDescription = "Listing date histogram" },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.Bottom,
      ) {
        counts.forEachIndexed { i, count ->
          val start = i * Recency.BUCKET_MONTHS
          val included = start >= newest && start < oldest
          Box(
            Modifier.weight(1f)
              // A hair of height on empty buckets keeps the axis readable.
              .height(maxOf(count.toFloat() / peak * 64f, 2f).dp)
              .clip(RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp))
              .background(
                if (included) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
              )
          )
        }
      }

      // Buckets are equal width, so only the ends need labelling to stay legible when narrow.
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Label("now")
        Label("$span+ mo ago")
      }

      // Steps are the interior bucket edges, so the window can only land on a bucket boundary.
      RangeSlider(
        value = newest.toFloat()..oldest.toFloat(),
        onValueChange = { range ->
          val from = snap(range.start, span)
          val to = maxOf(snap(range.endInclusive, span), from + Recency.BUCKET_MONTHS)
          onChange(
            filters.copy(
              newestMonths = minOf(from, span - Recency.BUCKET_MONTHS),
              // The oldest end stays open when it sits at the span, so appended pages extend the
              // window instead of being filtered out on arrival.
              oldestMonths = if (to >= span) null else to,
            )
          )
        },
        valueRange = 0f..span.toFloat(),
        steps = maxOf(counts.size - 1, 0),
      )
    }
  }
}

private fun snap(months: Float, span: Int): Int =
  (months / Recency.BUCKET_MONTHS).roundToInt().times(Recency.BUCKET_MONTHS).coerceIn(0, span)

@Composable
private fun Label(text: String) =
  Text(
    text,
    style = MaterialTheme.typography.labelSmall,
    color = MaterialTheme.colorScheme.onSurfaceVariant,
  )
