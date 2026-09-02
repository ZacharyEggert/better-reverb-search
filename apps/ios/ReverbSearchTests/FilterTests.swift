import Foundation
import Testing

@testable import ReverbSearch

@Suite("Client-side filters")
struct FilterTests {
    // ~1.5 months, ~23 months, and undated, against `referenceNow`.
    let recent = makeListing(title: "Fender Stratocaster", published: "2023-10-01T00:00:00Z")
    let old = makeListing(title: "Fender Telecaster Relic", published: "2022-01-01T00:00:00Z")
    let undated = makeListing(title: "Gibson Les Paul")

    @Test("Default filters keep everything and read as inactive")
    func inactiveByDefault() {
        let f = ListingFilters()
        #expect(!f.isActive)
        #expect([recent, old, undated].allSatisfy { f.matches($0, now: referenceNow) })
    }

    @Test("Newest bound drops anything more recent than it")
    func newestBound() {
        let f = ListingFilters(newestMonths: 6)
        #expect(!f.matches(recent, now: referenceNow))
        #expect(f.matches(old, now: referenceNow))
    }

    @Test("Oldest bound is exclusive")
    func oldestBound() {
        let f = ListingFilters(oldestMonths: 12)
        #expect(f.matches(recent, now: referenceNow))
        #expect(!f.matches(old, now: referenceNow))
    }

    @Test("An undated listing passes the date cut rather than vanishing silently")
    func undatedSurvives() {
        #expect(ListingFilters(newestMonths: 6, oldestMonths: 12).matches(undated, now: referenceNow))
    }

    @Test("Blacklist drops matching titles, case-insensitively")
    func blacklist() {
        let f = ListingFilters(blacklist: "relic, mini")
        #expect(f.matches(recent, now: referenceNow))
        #expect(!f.matches(old, now: referenceNow))
    }

    @Test("A non-empty whitelist keeps only what matches it")
    func whitelist() {
        let f = ListingFilters(whitelist: "strat(ocaster)?")
        #expect(f.matches(recent, now: referenceNow))
        #expect(!f.matches(old, now: referenceNow))
    }

    @Test("Blacklist wins over whitelist")
    func blacklistWins() {
        #expect(!ListingFilters(blacklist: "fender", whitelist: "strat")
            .matches(recent, now: referenceNow))
    }

    @Test("A half-typed regex is dropped, not thrown — and surfaced, not silent")
    func invalidRegex() {
        #expect(ListingFilters(blacklist: "(fender").matches(recent, now: referenceNow))
        #expect(ListingFilters.invalidTerms("(fender, relic") == ["(fender"])
        #expect(ListingFilters.invalidTerms("relic, mini").isEmpty)
        // Blank terms between commas are not terms.
        #expect(ListingFilters.regexes("relic, , mini").count == 2)
        #expect(ListingFilters.regexes("   ").isEmpty)
    }
}

@Suite("Recency histogram")
struct RecencyTests {
    let recent = makeListing(published: "2023-10-01T00:00:00Z")
    let old = makeListing(published: "2022-01-01T00:00:00Z")  // ~22.6 months
    let undated = makeListing()

    @Test("Three-month buckets, the oldest listing setting the last index")
    func buckets() {
        let counts = Recency.buckets([recent, recent, old, undated], now: referenceNow)
        #expect(counts.count == 8)
        #expect(counts[0] == 2)
        #expect(counts[7] == 1)
        // Undated listings aren't plotted.
        #expect(counts.reduce(0, +) == 3)
    }

    @Test("An empty result still has a bucket to drag over, not a zero-width track")
    func emptyStillHasSpan() {
        #expect(Recency.buckets([], now: referenceNow) == [0])
        #expect(Recency.span(bucketCount: 1) == 3)
        #expect(Recency.span(bucketCount: 0) == 3)
        #expect(Recency.span(bucketCount: 8) == 24)
    }
}
