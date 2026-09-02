import Foundation
import Testing

@testable import ReverbSearch

@Suite("Listing decoding")
struct ListingTests {
    /// The shape Reverb actually sends, trimmed: one sold listing with a
    /// discount, one live listing with a query string already on its web URL,
    /// one listing malformed past saving, and a `_links` value of the wrong type.
    static let page = """
        {
          "total": 2, "current_page": 1, "total_pages": 90, "humanized_params": "Fender",
          "listings": [
            { "id": 1, "title": "Sold Strat", "year": "1963", "make": "Fender",
              "condition": {"slug": "excellent", "display_name": "Excellent"},
              "price": {"amount_cents": 900000, "currency": "USD", "display": "$9,000"},
              "original_price": {"amount_cents": 1000000, "currency": "USD", "display": "$10,000"},
              "state": {"slug": "sold"}, "shop_name": "Shop A",
              "photos": [{"_links": {"thumbnail": {"href": "https://img/1"}}}],
              "_links": {"web": {"href": "https://reverb.com/item/1"}, "photos": ["not-an-object"]} },
            { "id": 2, "title": "Live Strat",
              "price": {"amount_cents": 500000, "currency": "USD", "display": "$5,000"},
              "state": {"slug": "live"},
              "_links": {"web": {"href": "https://reverb.com/item/2?foo=bar"},
                         "photo": {"href": "https://img/2"}} },
            { "id": "not-an-int", "title": "Malformed" }
          ]
        }
        """

    private struct Page: Decodable { var listings: [Failable<Listing>] }

    static func decoded() -> [Listing] {
        try! JSONDecoder().decode(Page.self, from: Data(page.utf8)).listings.compactMap(\.value)
    }

    @Test("One malformed listing doesn't empty the page")
    func failableIsolatesDamage() {
        #expect(Self.decoded().count == 2)
    }

    @Test("A `_links` value of the wrong shape doesn't take its listing down")
    func lenientLinks() {
        let sold = Self.decoded()[0]
        #expect(sold.thumbnailURL?.absoluteString == "https://img/1")
    }

    @Test("Thumbnail falls back to the listing's own photo link")
    func thumbnailFallback() {
        #expect(Self.decoded()[1].thumbnailURL?.absoluteString == "https://img/2")
    }

    @Test("Sold listings 404 without show_sold; live ones are left alone")
    func webURL() {
        let listings = Self.decoded()
        #expect(listings[0].webURL?.absoluteString == "https://reverb.com/item/1?show_sold=true")
        #expect(listings[1].webURL?.absoluteString == "https://reverb.com/item/2?foo=bar")
    }

    @Test("Discount is how far under the ask it cleared, and only for sold listings")
    func discount() {
        let listings = Self.decoded()
        #expect(listings[0].discountPercent == 10)
        #expect(listings[1].discountPercent == nil)
    }

    @Test("A sale above the ask isn't a negative discount")
    func discountNeverNegative() {
        let overAsk = makeListing("""
            {"id": 1, "title": "x",
             "price": {"amount_cents": 1200}, "original_price": {"amount_cents": 1000}}
            """)
        #expect(overAsk.discountPercent == nil)
    }

    @Test("Subtitle joins only what Reverb sent")
    func subtitle() {
        #expect(Self.decoded()[0].subtitle == "1963 · Excellent · Shop A")
        #expect(Self.decoded()[1].subtitle == "")
    }

    @Test("Both ISO-8601 flavours Reverb sends parse; garbage reads as undated")
    func dateParsing() {
        let plain = makeListing(published: "2023-10-01T00:00:00Z")
        let fractional = makeListing(published: "2023-10-01T00:00:00.123Z")
        #expect(plain.monthsAgo(now: referenceNow) != nil)
        #expect(fractional.monthsAgo(now: referenceNow) != nil)
        #expect(makeListing(published: "last tuesday").monthsAgo(now: referenceNow) == nil)
        #expect(makeListing().monthsAgo(now: referenceNow) == nil)
    }

    @Test("created_at stands in when published_at is missing")
    func createdAtFallback() {
        let draft = makeListing("""
            {"id": 1, "title": "x", "created_at": "2023-10-01T00:00:00Z"}
            """)
        #expect(draft.monthsAgo(now: referenceNow) != nil)
    }
}

@Suite("Price stats")
struct StatsTests {
    private func stats(_ cents: [Int]) -> PriceStats? {
        PriceStats(cents.enumerated().map { makeListing(id: $0.offset, cents: $0.element) })
    }

    @Test("Nothing priced means no stats block at all")
    func empty() {
        #expect(PriceStats([]) == nil)
        #expect(stats([]) == nil)
        // A listing with no price, or a zero price, is not a data point.
        #expect(PriceStats([makeListing()]) == nil)
        #expect(stats([0]) == nil)
    }

    @Test("A single listing is its own min, median, and max")
    func single() throws {
        let s = try #require(stats([12345]))
        #expect(s.count == 1 && s.min == 123.45 && s.median == 123.45 && s.max == 123.45)
    }

    @Test("Odd counts take the middle; even counts average the two")
    func median() throws {
        let odd = try #require(stats([300_00, 100_00, 200_00]))
        #expect(odd.median == 200 && odd.min == 100 && odd.max == 300)
        let even = try #require(stats([100_00, 200_00, 300_00, 500_00]))
        #expect(even.median == 250)
    }

    @Test("Unpriced listings are excluded from the count, not counted as zero")
    func mixedPricing() throws {
        let s = try #require(PriceStats([makeListing(cents: 100_00), makeListing(id: 2)]))
        #expect(s.count == 1 && s.min == 100 && s.max == 100)
    }

    @Test("Currency comes from the listings; the fallback is USD")
    func currency() throws {
        let euro = makeListing("""
            {"id": 1, "title": "x", "price": {"amount_cents": 10000, "currency": "EUR"}}
            """)
        #expect(try #require(PriceStats([euro])).currency == "EUR")
        let noCurrency = makeListing("""
            {"id": 1, "title": "x", "price": {"amount_cents": 10000}}
            """)
        #expect(try #require(PriceStats([noCurrency])).currency == "USD")
    }

    @Test("Formatting is whole units in the listings' own currency")
    func formatting() throws {
        let s = try #require(stats([123_45]))
        #expect(s.format(s.median) == "$123")
    }
}
