import Foundation

// Port of packages/reverb-api/src/search.ts — the typed layer over Reverb's
// listings API. Typed rather than a param bag for the reason the TS port gives:
// Reverb silently ignores unknown params (`condition=bogus` returns the
// *unfiltered* set) and misroutes others, so a typo looks like a real result.

enum Condition: String, CaseIterable, Identifiable {
    // Coarse buckets — a different axis from the seven grades below rather than
    // more members of it: `used` and `new` split the whole result set, while
    // `excellent` is a slice of `used`. Valid as a search filter only; a
    // listing's own `condition.slug` is always a grade.
    case used, new
    case bStock = "b-stock"
    case mint, excellent
    case veryGood = "very-good"
    case good, fair, poor
    case nonFunctioning = "non-functioning"
    var id: String { rawValue }
    var label: String { rawValue.replacingOccurrences(of: "-", with: " ") }

    static let buckets: [Condition] = [.used, .new, .bStock]
    static let grades: [Condition] = [
        .mint, .excellent, .veryGood, .good, .fair, .poor, .nonFunctioning,
    ]
}

enum ProductType: String, CaseIterable, Identifiable {
    case electricGuitars = "electric-guitars"
    case effectsAndPedals = "effects-and-pedals"
    case acousticGuitars = "acoustic-guitars"
    case bassGuitars = "bass-guitars"
    case proAudio = "pro-audio"
    case amps
    var id: String { rawValue }
    var label: String { rawValue.replacingOccurrences(of: "-", with: " ") }
}

enum Sort: String, CaseIterable, Identifiable {
    case priceAsc = "price|asc"
    case priceDesc = "price|desc"
    case newest = "published_at|desc"
    case oldest = "published_at|asc"
    var id: String { rawValue }
    var label: String { rawValue.replacingOccurrences(of: "|", with: " ") }
}

struct SearchQuery: Equatable {
    var query = ""
    var make = ""
    var model = ""
    var productType: ProductType?
    var condition: Condition?
    var sort: Sort?
    var priceMin: Int?
    var priceMax: Int?
    var yearMin: Int?
    var yearMax: Int?
    var showOnlySold = false
    var page = 1
    var perPage = 24

    /// snake_case wire params. Mirrors `toParams` in search.ts, including its
    /// default sort and the priceMin/priceMax ordering check.
    func queryItems() throws -> [URLQueryItem] {
        for s in [query, make, model] { try checkSafeString(s) }
        if let lo = priceMin, let hi = priceMax, lo > hi {
            throw RevError.validation("priceMin cannot exceed priceMax")
        }

        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            items.append(URLQueryItem(name: name, value: value))
        }
        add("query", query)
        add("make", make)
        add("model", model)
        add("product_type", productType?.rawValue)
        add("condition", condition?.rawValue)
        add("price_min", priceMin.map(String.init))
        add("price_max", priceMax.map(String.init))
        add("year_min", yearMin.map(String.init))
        add("year_max", yearMax.map(String.init))
        // Sold comps are `show_only_sold` — `show_sold`/`state=sold` do nothing.
        if showOnlySold { add("show_only_sold", "true") }
        add("sort", (sort ?? .newest).rawValue)
        add("page", String(page))
        add("per_page", String(perPage))
        return items
    }

    /// True once anything beyond the paging defaults is set — used to decide
    /// whether there is a search worth running at all.
    var isEmpty: Bool {
        self == SearchQuery(page: page, perPage: perPage)
    }
}

// MARK: - Wire types

struct Money: Decodable, Hashable {
    var amount: String?
    var amountCents: Int?
    var currency: String?
    var display: String?

    enum CodingKeys: String, CodingKey {
        case amount, currency, display
        case amountCents = "amount_cents"
    }
}

struct Listing: Decodable, Identifiable, Hashable {
    struct Named: Decodable, Hashable {
        var slug: String?
        var displayName: String?
        enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
        }
    }

    struct Photo: Decodable, Hashable {
        var links: HALLinks?
        enum CodingKeys: String, CodingKey { case links = "_links" }
    }

    let id: Int
    var title: String = ""
    var make: String?
    var model: String?
    var year: String?
    var condition: Named?
    var price: Money?
    /// Present on sold listings — the pre-discount ask.
    var originalPrice: Money?
    var state: Named?
    var shopName: String?
    var photos: [Photo]?
    var links: HALLinks?
    /// When the listing went live; `createdAt` is the fallback for drafts
    /// Reverb never published.
    var publishedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, make, model, year, condition, price, state, photos
        case originalPrice = "original_price"
        case shopName = "shop_name"
        case links = "_links"
        case publishedAt = "published_at"
        case createdAt = "created_at"
    }

    var thumbnailURL: URL? {
        let href = photos?.first?.links?["thumbnail"] ?? links?["photo"]
        return href.flatMap(URL.init(string:))
    }

    /// Public reverb.com URL. Sold listings 404 on their bare URL — reverb only
    /// renders a completed sale with `?show_sold=true` — so it is appended for
    /// anything whose own state is sold, not based on the current view mode.
    var webURL: URL? {
        guard let href = links?["web"], var c = URLComponents(string: href) else { return nil }
        if state?.slug == "sold" {
            var items = c.queryItems ?? []
            if !items.contains(where: { $0.name == "show_sold" }) {
                items.append(URLQueryItem(name: "show_sold", value: "true"))
            }
            c.queryItems = items
        }
        return c.url
    }

    /// How far below the ask a sold listing actually cleared.
    var discountPercent: Int? {
        guard let ask = originalPrice?.amountCents, let sold = price?.amountCents,
              ask > 0, sold <= ask else { return nil }
        return Int((Double(ask - sold) / Double(ask) * 100).rounded())
    }

    /// Months since the listing went live — the recency a shopper cares about.
    /// nil when Reverb omitted or garbled both timestamps.
    func monthsAgo(now: Date = .now) -> Double? {
        guard let raw = publishedAt ?? createdAt, let date = Self.parseDate(raw) else { return nil }
        return max(0, now.timeIntervalSince(date) / Listing.secondsPerMonth)
    }

    /// Average month. The month ladder is a coarse cut — calendar-exact edges buy nothing.
    private static let secondsPerMonth = 30.44 * 24 * 60 * 60

    // Configured once and only ever read; Foundation's date formatters are
    // documented thread-safe for parsing, which is all this does.
    nonisolated(unsafe) private static let formatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    private static func parseDate(_ raw: String) -> Date? {
        formatters.lazy.compactMap { $0.date(from: raw) }.first
    }

    var subtitle: String {
        [year, condition?.displayName, shopName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// HAL `_links`: a bag of `{ rel: { href } }`. Decoded leniently — an unexpected
/// shape under one rel must not take down the whole listing.
struct HALLinks: Decodable, Hashable {
    private var hrefs: [String: String] = [:]

    subscript(rel: String) -> String? { hrefs[rel] }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Href: Decodable { var href: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for key in c.allKeys {
            if let href = try? c.decode(Href.self, forKey: key).href {
                hrefs[key.stringValue] = href
            }
        }
    }
}

struct SearchResult {
    var total = 0
    var currentPage = 1
    var totalPages = 0
    /// Reverb's own echo of how it parsed the filters — the cheapest check that
    /// a filter did something.
    var humanizedParams = ""
    var listings: [Listing] = []
}

// MARK: - Client-side filters

/// Cuts applied to the listings already loaded, not to the query. Port of the
/// web app's recency + blacklist/whitelist filters.
struct ListingFilters: Equatable {
    /// Bounds in months ago, both multiples of `Recency.bucketMonths`. A nil
    /// `oldestMonths` means "no older bound", so it keeps tracking the span as
    /// older pages are appended rather than clipping them out.
    var newestMonths = 0
    var oldestMonths: Int?
    /// Comma-separated regexes. Titles matching any blacklist term are dropped;
    /// a non-empty whitelist drops titles matching none of its terms.
    var blacklist = ""
    var whitelist = ""

    var isActive: Bool { self != ListingFilters() }

    /// Undated listings pass the date cut: dropping one because Reverb omitted a
    /// timestamp would be a silent data loss the user can't see or undo.
    func matches(_ listing: Listing, now: Date = .now) -> Bool {
        if let months = listing.monthsAgo(now: now) {
            if months < Double(newestMonths) { return false }
            if let oldest = oldestMonths, months >= Double(oldest) { return false }
        }
        let title = listing.title
        // Blacklist wins over whitelist: an explicitly excluded title stays excluded.
        if Self.regexes(blacklist).contains(where: { $0.matches(title) }) { return false }
        let white = Self.regexes(whitelist)
        return white.isEmpty || white.contains { $0.matches(title) }
    }

    /// Split on commas, trim, drop blanks. A term that doesn't compile is dropped
    /// rather than thrown — the user is typing, and a half-written `(fender`
    /// shouldn't blank the results.
    static func regexes(_ input: String) -> [NSRegularExpression] {
        terms(input).compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }

    /// Terms that were typed but don't compile — surfaced so a typo isn't silent.
    static func invalidTerms(_ input: String) -> [String] {
        terms(input).filter { (try? NSRegularExpression(pattern: $0)) == nil }
    }

    private static func terms(_ input: String) -> [String] {
        input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The date histogram behind the range slider. Port of `recency-filter.tsx`.
enum Recency {
    /// Bucket width, in months. The slider steps in the same unit.
    static let bucketMonths = 3

    /// Counts per bucket, oldest listing setting the last index. The final
    /// bucket is open-ended, so nothing falls off the end of the chart.
    static func buckets(_ listings: [Listing], now: Date = .now) -> [Int] {
        let indices = listings.compactMap { $0.monthsAgo(now: now) }
            .map { Int($0) / bucketMonths }
        var counts = [Int](repeating: 0, count: (indices.max() ?? 0) + 1)
        for i in indices { counts[i] += 1 }
        return counts
    }

    /// Full span covering every bucket — the "no filter" range.
    static func span(bucketCount: Int) -> Int { max(bucketCount, 1) * bucketMonths }
}

extension NSRegularExpression {
    fileprivate func matches(_ s: String) -> Bool {
        firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

// MARK: - Stats

struct PriceStats {
    var count: Int
    var min: Double
    var median: Double
    var max: Double
    var currency: String

    /// Only ever describes the listings actually loaded — the API caps at 50 pages.
    init?(_ listings: [Listing]) {
        let cents = listings.compactMap { $0.price?.amountCents }.filter { $0 > 0 }.sorted()
        guard !cents.isEmpty else { return nil }
        let mid = cents.count / 2
        let median = cents.count.isMultiple(of: 2)
            ? Double(cents[mid - 1] + cents[mid]) / 2
            : Double(cents[mid])
        count = cents.count
        min = Double(cents[0]) / 100
        self.median = median / 100
        max = Double(cents[cents.count - 1]) / 100
        currency = listings.compactMap { $0.price?.currency }.first ?? "USD"
    }

    func format(_ value: Double) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

// MARK: - Validation

/// Port of `validate.ts` / `validate.rs`: reject control, bidi-override, and
/// zero-width characters in user input before it reaches a URL.
func checkSafeString(_ s: String) throws {
    for scalar in s.unicodeScalars {
        let cp = scalar.value
        let bad: String? = switch cp {
        case 0..<0x20, 0x7f...0x9f: "control"
        case 0x202a...0x202e, 0x2066...0x2069, 0x200e, 0x200f: "bidirectional override"
        case 0x200b, 0xfeff: "zero-width"
        default: nil
        }
        if let bad {
            throw RevError.validation(
                String(format: "input contains %@ character U+%04X", bad, cp))
        }
    }
}
