import Foundation
import Testing

@testable import ReverbSearch

@Suite("Search query serialization")
struct QueryTests {
    @Test("Defaults: sort applied, empty strings omitted")
    func defaults() {
        let p = params(SearchQuery())
        #expect(p["sort"] == "published_at|desc")
        #expect(p["make"] == nil)
        #expect(p["show_only_sold"] == nil)
        #expect(p["page"] == "1")
        #expect(p["per_page"] == "24")
    }

    @Test("Reverb's own param names — a wrong one silently returns the unfiltered set")
    func wireNames() {
        let p = params(
            SearchQuery(
                query: "strat", make: "Fender", model: "Stratocaster",
                productType: .electricGuitars, condition: .veryGood, sort: .priceAsc,
                priceMin: 500, priceMax: 900, yearMin: 1960, yearMax: 1969, showOnlySold: true))
        #expect(p["query"] == "strat")
        #expect(p["make"] == "Fender")
        #expect(p["model"] == "Stratocaster")
        #expect(p["product_type"] == "electric-guitars")
        #expect(p["condition"] == "very-good")
        #expect(p["sort"] == "price|asc")
        #expect(p["price_min"] == "500")
        #expect(p["price_max"] == "900")
        #expect(p["year_min"] == "1960")
        #expect(p["year_max"] == "1969")
        // Sold comps are show_only_sold — show_sold/state=sold do nothing.
        #expect(p["show_only_sold"] == "true")
    }

    @Test("Condition buckets are search filters alongside the seven grades")
    func conditions() {
        #expect(Condition.buckets.map(\.rawValue) == ["used", "new", "b-stock"])
        #expect(Condition.allCases.count == Condition.buckets.count + Condition.grades.count)
        #expect(params(SearchQuery(condition: .bStock))["condition"] == "b-stock")
    }

    @Test("An inverted price range is refused rather than quietly returning nothing")
    func invertedPriceRange() {
        #expect(throws: RevError.self) {
            try SearchQuery(priceMin: 900, priceMax: 100).queryItems()
        }
    }

    @Test("Control, bidi, and zero-width characters never reach the URL",
          arguments: ["a\u{0007}b", "a\u{202E}b", "a\u{200B}b", "a\u{FEFF}b"])
    func unsafeInput(_ input: String) {
        #expect(throws: RevError.self) { try checkSafeString(input) }
    }

    @Test("Ordinary search text passes, accents and em dashes included")
    func safeInput() throws {
        try checkSafeString("1963 Stratocaster — sunburst, Léo's")
    }

    @Test("Empty: nothing to search on, so nothing is sent")
    func isEmpty() {
        #expect(SearchQuery().isEmpty)
        // The sold/active toggle isn't input — flipping it leaves an empty search.
        #expect(SearchQuery(showOnlySold: true).isEmpty)
        // Nor is paging.
        #expect(SearchQuery(page: 3, perPage: 50).isEmpty)
    }

    @Test("Any real input makes it a search")
    func notEmpty() {
        #expect(!SearchQuery(query: "strat").isEmpty)
        #expect(!SearchQuery(make: "Fender").isEmpty)
        #expect(!SearchQuery(model: "Telecaster").isEmpty)
        #expect(!SearchQuery(productType: .amps).isEmpty)
        #expect(!SearchQuery(condition: .mint).isEmpty)
        #expect(!SearchQuery(sort: .priceAsc).isEmpty)
        #expect(!SearchQuery(priceMin: 100).isEmpty)
        #expect(!SearchQuery(yearMax: 1969).isEmpty)
    }
}
