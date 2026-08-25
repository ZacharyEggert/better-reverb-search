package llc.exnihilo.betterreverbsearch.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** Port of apps/ios/Tests/main.swift — param serialization, sold-URL handling, discount math, stats, validation. */
class SearchTest {
  private fun params(q: SearchQuery) = q.queryParams().toMap()

  @Test
  fun defaults_applySortAndOmitEmpties() {
    val p = params(SearchQuery())
    assertEquals("published_at|desc", p["sort"])
    assertNull(p["make"])
    assertNull(p["show_only_sold"])
  }

  @Test
  fun soldCompsUseShowOnlySold() {
    val p =
      params(
        SearchQuery(
          showOnlySold = true,
          condition = Condition.VERY_GOOD,
          productType = ProductType.ELECTRIC_GUITARS,
          priceMin = 500,
        )
      )
    assertEquals("true", p["show_only_sold"])
    assertEquals("very-good", p["condition"])
    assertEquals("electric-guitars", p["product_type"])
    assertEquals("500", p["price_min"])
  }

  @Test
  fun priceMinAbovePriceMaxIsRejected() {
    // Rather than silently returning nothing.
    assertThrows(RevException.Validation::class.java) {
      SearchQuery(priceMin = 500, priceMax = 100).queryParams()
    }
  }

  @Test
  fun unsafeCharactersAreRejected() {
    for (bad in listOf("a\u0007b", "a\u202Eb", "a\u200Bb")) {
      assertThrows(RevException.Validation::class.java) { checkSafeString(bad) }
    }
    checkSafeString("1963 Stratocaster — sunburst")
  }

  @Test
  fun malformedListingDoesNotTakeDownThePage() {
    val page = parsePage(JSON)
    // One malformed listing doesn't take the page down; a bad _links value doesn't take its
    // listing down.
    assertEquals(2, page.listings.size)
    assertEquals(90, page.totalPages)
    assertEquals("Fender", page.humanizedParams)
    assertEquals("https://img/1", page.listings[0].thumbnailUrl)
  }

  @Test
  fun soldListingsGetShowSoldAndLiveOnesAreLeftAlone() {
    val listings = parsePage(JSON).listings
    assertEquals("https://reverb.com/item/1?show_sold=true", listings[0].webUrl)
    assertEquals("https://reverb.com/item/2?foo=bar", listings[1].webUrl)
  }

  @Test
  fun discountPercent() {
    val listings = parsePage(JSON).listings
    assertEquals(10, listings[0].discountPercent)
    assertNull(listings[1].discountPercent)
  }

  @Test
  fun stats() {
    val stats = PriceStats.of(parsePage(JSON).listings)!!
    assertEquals(2, stats.count)
    assertEquals(5000.0, stats.min, 0.001)
    assertEquals(7000.0, stats.median, 0.001)
    assertEquals(9000.0, stats.max, 0.001)
    assertNull(PriceStats.of(emptyList()))
  }

  @Test
  fun conditionBucketsAreSearchFilterValuesAlongsideTheGrades() {
    assertEquals(listOf("used", "new", "b-stock"), Condition.buckets.map { it.wire })
    assertEquals(Condition.entries.size, Condition.buckets.size + Condition.grades.size)
    assertEquals("b-stock", params(SearchQuery(condition = Condition.B_STOCK))["condition"])
  }

  @Test
  fun recencyFilterBoundsTheLoadedListings() {
    val f = ListingFilters()
    assertEquals(false, f.isActive)
    for (l in listOf(RECENT, OLD, UNDATED)) assertEquals(true, f.matches(l, NOW))

    // Newest bound drops anything more recent than it; the oldest bound is exclusive.
    val newest = ListingFilters(newestMonths = 6)
    assertEquals(false, newest.matches(RECENT, NOW))
    assertEquals(true, newest.matches(OLD, NOW))
    // An undated listing always passes the date cut rather than vanishing silently.
    assertEquals(true, newest.matches(UNDATED, NOW))

    val oldest = ListingFilters(oldestMonths = 12)
    assertEquals(true, oldest.matches(RECENT, NOW))
    assertEquals(false, oldest.matches(OLD, NOW))
  }

  @Test
  fun blacklistWinsOverWhitelistAndBadRegexesAreDropped() {
    ListingFilters(blacklist = "relic, mini").let {
      assertEquals(true, it.matches(RECENT, NOW))
      assertEquals(false, it.matches(OLD, NOW))
    }
    ListingFilters(whitelist = "strat(ocaster)?").let {
      assertEquals(true, it.matches(RECENT, NOW))
      assertEquals(false, it.matches(OLD, NOW))
    }
    assertEquals(false, ListingFilters(blacklist = "fender", whitelist = "strat").matches(RECENT, NOW))

    // A half-typed regex is dropped, not thrown — and surfaced rather than silent.
    assertEquals(true, ListingFilters(blacklist = "(fender").matches(RECENT, NOW))
    assertEquals(listOf("(fender"), ListingFilters.invalidTerms("(fender, relic"))
  }

  private companion object {
    /** 2023-11-14T22:13:20Z. */
    const val NOW = 1_700_000_000_000L
    val RECENT = // ~1.5 months old
      Listing(id = 1, title = "Fender Stratocaster", publishedAt = "2023-10-01T00:00:00Z")
    val OLD = // ~23 months old
      Listing(id = 2, title = "Fender Telecaster Relic", publishedAt = "2022-01-01T00:00:00Z")
    val UNDATED = Listing(id = 3, title = "Gibson Les Paul")

    const val JSON =
      """
{
  "total": 2, "current_page": 1, "total_pages": 90, "humanized_params": "Fender",
  "listings": [
    { "id": 1, "title": "Sold Strat", "year": "1963",
      "price": {"amount_cents": 900000, "currency": "USD", "display": "${'$'}9,000"},
      "original_price": {"amount_cents": 1000000, "currency": "USD", "display": "${'$'}10,000"},
      "state": {"slug": "sold"}, "shop_name": "Shop A",
      "photos": [{"_links": {"thumbnail": {"href": "https://img/1"}}}],
      "_links": {"web": {"href": "https://reverb.com/item/1"}, "photos": ["not-an-object"]} },
    { "id": 2, "title": "Live Strat",
      "price": {"amount_cents": 500000, "currency": "USD", "display": "${'$'}5,000"},
      "state": {"slug": "live"},
      "_links": {"web": {"href": "https://reverb.com/item/2?foo=bar"}} },
    { "id": "not-an-int", "title": "Malformed" }
  ]
}
"""
  }
}
