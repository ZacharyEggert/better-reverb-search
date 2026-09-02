// Self-check for the non-UI logic: param serialization, sold-URL handling,
// discount math, stats, and input validation.
//
//   cd apps/ios && swiftc -o /tmp/reverb-tests Tests/main.swift ReverbSearch/Models.swift \
//       ReverbSearch/ReverbAPI.swift ReverbSearch/QueryQuota.swift ReverbSearch/BypassCode.swift \
//       && /tmp/reverb-tests
import Foundation

func params(_ q: SearchQuery) -> [String: String] {
    Dictionary(uniqueKeysWithValues: try! q.queryItems().map { ($0.name, $0.value ?? "") })
}

// Defaults: sort applied, empty strings omitted.
var q = SearchQuery()
assert(params(q)["sort"] == "published_at|desc")
assert(params(q)["make"] == nil)
assert(params(q)["show_only_sold"] == nil)

// Sold comps use show_only_sold, not show_sold/state.
q.showOnlySold = true
q.condition = .veryGood
q.productType = .electricGuitars
q.priceMin = 500
assert(params(q)["show_only_sold"] == "true")
assert(params(q)["condition"] == "very-good")
assert(params(q)["product_type"] == "electric-guitars")
assert(params(q)["price_min"] == "500")

// priceMin > priceMax is rejected rather than silently returning nothing.
q.priceMax = 100
do {
    _ = try q.queryItems()
    assertionFailure("expected validation error")
} catch {}

// Control/bidi/zero-width characters are rejected.
for bad in ["a\u{0007}b", "a\u{202E}b", "a\u{200B}b"] {
    do {
        try checkSafeString(bad)
        assertionFailure("expected rejection of \(bad.debugDescription)")
    } catch {}
}
try! checkSafeString("1963 Stratocaster — sunburst")

let json = """
{
  "total": 2, "current_page": 1, "total_pages": 90, "humanized_params": "Fender",
  "listings": [
    { "id": 1, "title": "Sold Strat", "year": "1963",
      "price": {"amount_cents": 900000, "currency": "USD", "display": "$9,000"},
      "original_price": {"amount_cents": 1000000, "currency": "USD", "display": "$10,000"},
      "state": {"slug": "sold"}, "shop_name": "Shop A",
      "photos": [{"_links": {"thumbnail": {"href": "https://img/1"}}}],
      "_links": {"web": {"href": "https://reverb.com/item/1"}, "photos": ["not-an-object"]} },
    { "id": 2, "title": "Live Strat",
      "price": {"amount_cents": 500000, "currency": "USD", "display": "$5,000"},
      "state": {"slug": "live"},
      "_links": {"web": {"href": "https://reverb.com/item/2?foo=bar"}} },
    { "id": "not-an-int", "title": "Malformed" }
  ]
}
"""

struct Page: Decodable {
    var listings: [Failable<Listing>]
}
let listings = try! JSONDecoder().decode(Page.self, from: Data(json.utf8)).listings.compactMap { $0.value }

// One malformed listing doesn't take the page down; a bad _links value doesn't
// take its listing down.
assert(listings.count == 2)
assert(listings[0].thumbnailURL?.absoluteString == "https://img/1")

// Sold listings 404 without show_sold; live ones must be left alone.
assert(listings[0].webURL?.absoluteString == "https://reverb.com/item/1?show_sold=true")
assert(listings[1].webURL?.absoluteString == "https://reverb.com/item/2?foo=bar")

assert(listings[0].discountPercent == 10)
assert(listings[1].discountPercent == nil)

let stats = PriceStats(listings)!
assert(stats.count == 2 && stats.min == 5000 && stats.median == 7000 && stats.max == 9000)
assert(PriceStats([]) == nil)

// Client-side filters: recency ladder + blacklist/whitelist over titles.
func listing(_ title: String, published: String?) -> Listing {
    let dated = published.map { ", \"published_at\": \"\($0)\"" } ?? ""
    let raw = "{ \"id\": 1, \"title\": \"\(title)\"\(dated) }"
    return try! JSONDecoder().decode(Listing.self, from: Data(raw.utf8))
}

let now = Date(timeIntervalSince1970: 1_700_000_000)
let recent = listing("Fender Stratocaster", published: "2023-10-01T00:00:00Z")  // ~1.5 mo
let old = listing("Fender Telecaster Relic", published: "2022-01-01T00:00:00Z")  // ~23 mo
let undated = listing("Gibson Les Paul", published: nil)

var f = ListingFilters()
assert(!f.isActive)
assert([recent, old, undated].allSatisfy { f.matches($0, now: now) })

// Newest bound drops anything more recent than it; the oldest bound is exclusive.
f.newestMonths = 6
assert(!f.matches(recent, now: now) && f.matches(old, now: now))
// An undated listing always passes the date cut rather than vanishing silently.
assert(f.matches(undated, now: now))
f = ListingFilters(newestMonths: 0, oldestMonths: 12)
assert(f.matches(recent, now: now) && !f.matches(old, now: now))

// Blacklist wins over whitelist; both are case-insensitive regexes.
f = ListingFilters(blacklist: "relic, mini")
assert(f.matches(recent, now: now) && !f.matches(old, now: now))
f = ListingFilters(whitelist: "strat(ocaster)?")
assert(f.matches(recent, now: now) && !f.matches(old, now: now))
f = ListingFilters(blacklist: "fender", whitelist: "strat")
assert(!f.matches(recent, now: now))

// A half-typed regex is dropped, not thrown — and surfaced rather than silent.
f = ListingFilters(blacklist: "(fender")
assert(f.matches(recent, now: now))
assert(ListingFilters.invalidTerms("(fender, relic") == ["(fender"])

// The histogram: 3-month buckets, oldest listing setting the last index, and a
// span that covers every bucket.
let bucketed = Recency.buckets([recent, recent, old, undated], now: now)
assert(bucketed.count == 8)  // old is ~22.6 mo => bucket 7
assert(bucketed[0] == 2 && bucketed[7] == 1)  // undated listings aren't plotted
assert(bucketed.reduce(0, +) == 3)
assert(Recency.span(bucketCount: bucketed.count) == 24)
// An empty result still has a span to drag over rather than a zero-width track.
assert(Recency.buckets([], now: now) == [0] && Recency.span(bucketCount: 1) == 3)

// Buckets are search-filter values alongside the seven grades.
assert(Condition.buckets.map(\.rawValue) == ["used", "new", "b-stock"])
assert(Condition.allCases.count == Condition.buckets.count + Condition.grades.count)
assert(params(SearchQuery(condition: .bStock))["condition"] == "b-stock")

// Free-tier quota: counts down, clamps at zero, and a stale day starts over.
UserDefaults.standard.removeObject(forKey: "quota")
assert(QueryQuota.remaining == QueryQuota.dailyLimit)
for _ in 0..<QueryQuota.dailyLimit { QueryQuota.consume() }
assert(QueryQuota.used == QueryQuota.dailyLimit && QueryQuota.remaining == 0)
QueryQuota.consume()
assert(QueryQuota.remaining == 0)
UserDefaults.standard.set(["day": 1, "count": 99], forKey: "quota")
assert(QueryQuota.remaining == QueryQuota.dailyLimit)
UserDefaults.standard.removeObject(forKey: "quota")

// A stored code alone doesn't raise the limit — only a server-confirmed one,
// so an unreachable service leaves the user at the default.
assert(!BypassCode.isActive && QueryQuota.dailyLimit == 5)
UserDefaults.standard.set("code", forKey: "bypassCode")
assert(BypassCode.hasCode && !BypassCode.isActive && QueryQuota.dailyLimit == 5)
BypassCode.verified = true
assert(BypassCode.isActive && QueryQuota.dailyLimit == BypassCode.raisedLimit)

// With a code, the upgrade pitch stays hidden until half the quota is spent.
assert(!QueryQuota.offerUpgrade)
UserDefaults.standard.set(
    ["day": Calendar.current.ordinality(of: .day, in: .era, for: .now)!,
     "count": BypassCode.raisedLimit / 2],
    forKey: "quota")
assert(QueryQuota.offerUpgrade)
UserDefaults.standard.removeObject(forKey: "quota")

BypassCode.remove()
assert(!BypassCode.isActive && QueryQuota.dailyLimit == 5)
// Without one it's always available.
assert(QueryQuota.offerUpgrade)

// An empty search is blocked before it reaches Reverb; the sold toggle alone
// isn't input, but any real filter is.
assert(SearchQuery().isEmpty)
assert(SearchQuery(showOnlySold: true).isEmpty)
assert(!SearchQuery(query: "strat").isEmpty)
assert(!SearchQuery(productType: .amps).isEmpty)
assert(!SearchQuery(priceMin: 100).isEmpty)

// Server faults read as advice, never as a raw status code.
let serverError = RevError.message(for: RevError.api(500, "Unknown Error"))
assert(!serverError.contains("500") && serverError.contains("temporarily unavailable"))
assert(RevError.message(for: URLError(.notConnectedToInternet)).contains("No internet"))
assert(RevError.message(for: URLError(.timedOut)).contains("timed out"))

print("ok")
