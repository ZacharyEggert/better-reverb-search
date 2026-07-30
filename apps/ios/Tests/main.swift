// Self-check for the non-UI logic: param serialization, sold-URL handling,
// discount math, stats, and input validation.
//
//   cd apps/ios && swiftc -o /tmp/reverb-tests Tests/main.swift ReverbSearch/Models.swift \
//       ReverbSearch/ReverbAPI.swift && /tmp/reverb-tests
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

print("ok")
