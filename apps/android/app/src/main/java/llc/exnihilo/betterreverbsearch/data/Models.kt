package llc.exnihilo.betterreverbsearch.data

import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Port of packages/reverb-api/src/search.ts — the typed layer over Reverb's
// listings API. Typed rather than a param bag for the reason the TS port gives:
// Reverb silently ignores unknown params (`condition=bogus` returns the
// *unfiltered* set) and misroutes others, so a typo looks like a real result.

enum class Condition(val wire: String) {
  // Coarse buckets — a different axis from the seven grades below rather than more members of it:
  // `used` and `new` split the whole result set, while `excellent` is a slice of `used`. Valid as a
  // search filter only; a listing's own `condition.slug` is always a grade.
  USED("used"),
  NEW("new"),
  B_STOCK("b-stock"),
  MINT("mint"),
  EXCELLENT("excellent"),
  VERY_GOOD("very-good"),
  GOOD("good"),
  FAIR("fair"),
  POOR("poor"),
  NON_FUNCTIONING("non-functioning");

  val label: String
    get() = wire.replace('-', ' ')

  companion object {
    val buckets = listOf(USED, NEW, B_STOCK)
    val grades = entries - buckets.toSet()
  }
}

enum class ProductType(val wire: String) {
  ELECTRIC_GUITARS("electric-guitars"),
  EFFECTS_AND_PEDALS("effects-and-pedals"),
  ACOUSTIC_GUITARS("acoustic-guitars"),
  BASS_GUITARS("bass-guitars"),
  PRO_AUDIO("pro-audio"),
  AMPS("amps");

  val label: String
    get() = wire.replace('-', ' ')
}

enum class Sort(val wire: String) {
  PRICE_ASC("price|asc"),
  PRICE_DESC("price|desc"),
  NEWEST("published_at|desc"),
  OLDEST("published_at|asc");

  val label: String
    get() = wire.replace('|', ' ')
}

data class SearchQuery(
  val query: String = "",
  val make: String = "",
  val model: String = "",
  val productType: ProductType? = null,
  val condition: Condition? = null,
  val sort: Sort? = null,
  val priceMin: Int? = null,
  val priceMax: Int? = null,
  val yearMin: Int? = null,
  val yearMax: Int? = null,
  val showOnlySold: Boolean = false,
  val page: Int = 1,
  val perPage: Int = 24,
) {
  /**
   * snake_case wire params. Mirrors `toParams` in search.ts, including its default sort and the
   * priceMin/priceMax ordering check.
   */
  fun queryParams(): List<Pair<String, String>> {
    listOf(query, make, model).forEach(::checkSafeString)
    if (priceMin != null && priceMax != null && priceMin > priceMax) {
      throw RevException.Validation("priceMin cannot exceed priceMax")
    }

    val items = mutableListOf<Pair<String, String>>()
    fun add(name: String, value: String?) {
      if (!value.isNullOrEmpty()) items += name to value
    }
    add("query", query)
    add("make", make)
    add("model", model)
    add("product_type", productType?.wire)
    add("condition", condition?.wire)
    add("price_min", priceMin?.toString())
    add("price_max", priceMax?.toString())
    add("year_min", yearMin?.toString())
    add("year_max", yearMax?.toString())
    // Sold comps are `show_only_sold` — `show_sold`/`state=sold` do nothing.
    if (showOnlySold) add("show_only_sold", "true")
    add("sort", (sort ?: Sort.NEWEST).wire)
    add("page", page.toString())
    add("per_page", perPage.toString())
    return items
  }
}

// MARK: - Wire types

@Serializable
data class Money(
  val amount: String? = null,
  @SerialName("amount_cents") val amountCents: Int? = null,
  val currency: String? = null,
  val display: String? = null,
)

@Serializable data class Named(val slug: String? = null, @SerialName("display_name") val displayName: String? = null)

@Serializable data class Photo(@SerialName("_links") val links: HalLinks? = null)

@Serializable
data class Listing(
  val id: Int,
  val title: String = "",
  val make: String? = null,
  val model: String? = null,
  val year: String? = null,
  val condition: Named? = null,
  val price: Money? = null,
  /** Present on sold listings — the pre-discount ask. */
  @SerialName("original_price") val originalPrice: Money? = null,
  val state: Named? = null,
  @SerialName("shop_name") val shopName: String? = null,
  val photos: List<Photo>? = null,
  @SerialName("_links") val links: HalLinks? = null,
  /** When the listing went live; [createdAt] is the fallback for drafts Reverb never published. */
  @SerialName("published_at") val publishedAt: String? = null,
  @SerialName("created_at") val createdAt: String? = null,
) {
  val thumbnailUrl: String?
    get() = photos?.firstOrNull()?.links?.get("thumbnail") ?: links?.get("photo")

  /**
   * Public reverb.com URL. Sold listings 404 on their bare URL — reverb only renders a completed
   * sale with `?show_sold=true` — so it is appended for anything whose own state is sold, not based
   * on the current view mode.
   */
  val webUrl: String?
    get() {
      val href = links?.get("web") ?: return null
      if (state?.slug != "sold" || href.contains("show_sold=")) return href
      return href + (if (href.contains('?')) "&" else "?") + "show_sold=true"
    }

  /** How far below the ask a sold listing actually cleared. */
  val discountPercent: Int?
    get() {
      val ask = originalPrice?.amountCents ?: return null
      val sold = price?.amountCents ?: return null
      if (ask <= 0 || sold > ask) return null
      return Math.round((ask - sold).toDouble() / ask * 100).toInt()
    }

  /**
   * Months since the listing went live — the recency a shopper cares about. Null when Reverb omitted
   * or garbled both timestamps.
   */
  fun monthsAgo(now: Long = System.currentTimeMillis()): Double? {
    val raw = publishedAt ?: createdAt ?: return null
    val t = parseIso(raw) ?: return null
    return maxOf(0.0, (now - t) / MS_PER_MONTH)
  }

  val subtitle: String
    get() = listOfNotNull(year, condition?.displayName, shopName).joinToString(" · ")
}

/** Average month. The month ladder is a coarse cut — calendar-exact edges buy nothing. */
private const val MS_PER_MONTH = 30.44 * 24 * 60 * 60 * 1000

// java.time needs API 26 and this module is minSdk 24, so SimpleDateFormat it is.
private val ISO_FORMATS =
  listOf("yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ss'Z'")

private fun parseIso(raw: String): Long? =
  ISO_FORMATS.firstNotNullOfOrNull { pattern ->
    runCatching { java.text.SimpleDateFormat(pattern, Locale.US).parse(raw)?.time }.getOrNull()
  }

/**
 * Cuts applied to the listings already loaded, not to the query. Port of the web app's recency +
 * blacklist/whitelist filters.
 *
 * ponytail: a fixed month ladder instead of the web's histogram-derived span — same semantics, no
 * chart to build. Swap in a computed span if the ladder ever misses the data.
 */
data class ListingFilters(
  /** Bounds in months ago. A null [oldestMonths] means "no older bound". */
  val newestMonths: Int = 0,
  val oldestMonths: Int? = null,
  /**
   * Comma-separated regexes. Titles matching any blacklist term are dropped; a non-empty whitelist
   * drops titles matching none of its terms.
   */
  val blacklist: String = "",
  val whitelist: String = "",
) {
  val isActive: Boolean
    get() = this != ListingFilters()

  /**
   * Undated listings pass the date cut: dropping one because Reverb omitted a timestamp would be a
   * silent data loss the user can't see or undo.
   */
  fun matches(listing: Listing, now: Long = System.currentTimeMillis()): Boolean {
    listing.monthsAgo(now)?.let { months ->
      if (months < newestMonths) return false
      if (oldestMonths != null && months >= oldestMonths) return false
    }
    val title = listing.title
    // Blacklist wins over whitelist: an explicitly excluded title stays excluded.
    if (regexes(blacklist).any { it.containsMatchIn(title) }) return false
    val white = regexes(whitelist)
    return white.isEmpty() || white.any { it.containsMatchIn(title) }
  }

  companion object {
    /** The steps offered for either bound. */
    val MONTH_OPTIONS = listOf(0, 3, 6, 12, 18, 24, 36)

    /**
     * Split on commas, trim, drop blanks. A term that doesn't compile is dropped rather than thrown
     * — the user is typing, and a half-written `(fender` shouldn't blank the results.
     */
    fun regexes(input: String): List<Regex> =
      terms(input).mapNotNull { runCatching { Regex(it, RegexOption.IGNORE_CASE) }.getOrNull() }

    /** Terms that were typed but don't compile — surfaced so a typo isn't silent. */
    fun invalidTerms(input: String): List<String> =
      terms(input).filter { runCatching { Regex(it) }.isFailure }

    private fun terms(input: String) = input.split(',').map(String::trim).filter(String::isNotEmpty)
  }
}

/**
 * HAL `_links`: a bag of `{ rel: { href } }`. Decoded leniently — an unexpected shape under one rel
 * must not take down the whole listing.
 */
@Serializable(with = HalLinksSerializer::class)
class HalLinks(private val hrefs: Map<String, String>) {
  operator fun get(rel: String): String? = hrefs[rel]
}

object HalLinksSerializer : kotlinx.serialization.KSerializer<HalLinks> {
  private val delegate =
    kotlinx.serialization.builtins.MapSerializer(
      String.serializer(),
      JsonElement.serializer(),
    )
  override val descriptor = delegate.descriptor

  override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): HalLinks {
    val raw = delegate.deserialize(decoder)
    return HalLinks(
      raw.mapNotNull { (rel, value) ->
        val href = runCatching { value.jsonObject["href"]?.jsonPrimitive?.content }.getOrNull()
        href?.let { rel to it }
      }.toMap()
    )
  }

  override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: HalLinks) =
    throw UnsupportedOperationException("read-only")
}

data class SearchResult(
  val total: Int = 0,
  val currentPage: Int = 1,
  val totalPages: Int = 0,
  /** Reverb's own echo of how it parsed the filters — the cheapest check that a filter did something. */
  val humanizedParams: String = "",
  val listings: List<Listing> = emptyList(),
)

internal val json = Json { ignoreUnknownKeys = true }

/** One malformed listing shouldn't empty the whole page of results. */
fun parsePage(body: String): SearchResult {
  val root = json.parseToJsonElement(body) as JsonObject
  fun int(key: String) = root[key]?.jsonPrimitive?.content?.toIntOrNull()
  val listings =
    (root["listings"] as? kotlinx.serialization.json.JsonArray).orEmpty().mapNotNull {
      runCatching { json.decodeFromJsonElement(Listing.serializer(), it) }.getOrNull()
    }
  return SearchResult(
    total = int("total") ?: 0,
    currentPage = int("current_page") ?: 1,
    totalPages = int("total_pages") ?: 0,
    humanizedParams = runCatching { root["humanized_params"]!!.jsonPrimitive.content }.getOrDefault(""),
    listings = listings,
  )
}

private fun kotlinx.serialization.json.JsonArray?.orEmpty(): List<JsonElement> = this ?: emptyList()

// MARK: - Stats

class PriceStats
private constructor(
  val count: Int,
  val min: Double,
  val median: Double,
  val max: Double,
  val currency: String,
) {
  fun format(value: Double): String =
    NumberFormat.getCurrencyInstance(Locale.getDefault()).apply {
      runCatching { this.currency = Currency.getInstance(this@PriceStats.currency) }
      maximumFractionDigits = 0
      minimumFractionDigits = 0
    }.format(value)

  companion object {
    /** Only ever describes the listings actually loaded — the API caps at 50 pages. */
    fun of(listings: List<Listing>): PriceStats? {
      val cents = listings.mapNotNull { it.price?.amountCents }.filter { it > 0 }.sorted()
      if (cents.isEmpty()) return null
      val mid = cents.size / 2
      val median =
        if (cents.size % 2 == 0) (cents[mid - 1] + cents[mid]).toDouble() / 2 else cents[mid].toDouble()
      return PriceStats(
        count = cents.size,
        min = cents.first() / 100.0,
        median = median / 100,
        max = cents.last() / 100.0,
        currency = listings.firstNotNullOfOrNull { it.price?.currency } ?: "USD",
      )
    }
  }
}

fun Int.formatted(): String = NumberFormat.getIntegerInstance(Locale.getDefault()).format(this)

// MARK: - Validation

/**
 * Port of `validate.ts` / `validate.rs`: reject control, bidi-override, and zero-width characters in
 * user input before it reaches a URL.
 */
fun checkSafeString(s: String) {
  for (ch in s) {
    val cp = ch.code
    val bad =
      when (cp) {
        in 0x00..0x1f, in 0x7f..0x9f -> "control"
        in 0x202a..0x202e, in 0x2066..0x2069, 0x200e, 0x200f -> "bidirectional override"
        0x200b, 0xfeff -> "zero-width"
        else -> null
      }
    if (bad != null) {
      throw RevException.Validation(String.format("input contains %s character U+%04X", bad, cp))
    }
  }
}
