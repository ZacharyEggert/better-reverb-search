import Foundation

/// Port of `error.ts` — the arms that survive without a CLI (no auth/schema
/// paths are reachable here: search answers unauthenticated and the only
/// endpoint used is `GET /api/listings`).
enum RevError: LocalizedError {
    case api(Int, String)
    case validation(String)
    case other(String)

    /// What the user sees. Reverb's own status codes and body messages are
    /// operator detail — a raw "API error 500" tells nobody what to do next.
    var errorDescription: String? {
        switch self {
        case let .api(code, message):
            switch code {
            case 401, 403: "Reverb rejected the request. Check or remove your API key in the ••• menu."
            case 404: "Reverb had nothing for that. Try a different search."
            case 429: "Too many searches in a row. Wait a moment, then try again."
            case 400, 422: "Reverb couldn't read that search. Try simpler terms or fewer filters."
            case 500...599: "Reverb's search is temporarily unavailable. Try again in a moment."
            default: message.isEmpty ? "The search couldn't be completed. Try again." : message
            }
        case let .validation(message): message
        case let .other(message): message
        }
    }

    /// Every failure path the UI can hit, in words a user can act on.
    static func message(for error: Error) -> String {
        switch error {
        case let error as RevError: error.localizedDescription
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                "No internet connection. Reconnect and try again."
            case .timedOut: "The search timed out. Try again."
            default: "Couldn't reach Reverb. Check your connection and try again."
            }
        default: "The search couldn't be completed. Try again."
        }
    }
}

enum ReverbAPI {
    static let baseURL = URL(string: "https://api.reverb.com/api/listings")!
    static let userAgent = "revcli-ios/0.1.0"
    static let requestTimeout: TimeInterval = 30

    static func search(_ query: SearchQuery, apiKey: String? = nil) async throws -> SearchResult {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = try query.queryItems()

        var request = URLRequest(url: components.url!, timeoutInterval: requestTimeout)
        request.setValue("application/hal+json", forHTTPHeaderField: "Accept")
        request.setValue("3.0", forHTTPHeaderField: "Accept-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await sendWithRetry(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["message"] ?? $0?["Error"]) as? String } ?? ""
            throw RevError.api(status, message)
        }

        var result: SearchResult
        do {
            result = try JSONDecoder().decode(Page.self, from: data).asResult
        } catch {
            throw RevError.other("Reverb sent back something this app couldn't read. Try again.")
        }
        await SoldPrices.apply(to: &result.listings)
        return result
    }

    /// Exponential backoff on 429, honouring `retry-after`. 5 attempts, 60s cap —
    /// same policy as `client.ts`.
    private static func sendWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var delay: Double = 1
        for attempt in 1...5 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            guard http?.statusCode == 429, attempt < 5 else { return (data, response) }

            let header = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            try await Task.sleep(for: .seconds(header.map { Swift.max(0, $0) } ?? delay))
            delay = Swift.min(delay * 2, 60)
        }
        throw RevError.api(429, "")
    }

    private struct Page: Decodable {
        var total: Int?
        var currentPage: Int?
        var totalPages: Int?
        var humanizedParams: String?
        var listings: [Failable<Listing>]?

        enum CodingKeys: String, CodingKey {
            case total, listings
            case currentPage = "current_page"
            case totalPages = "total_pages"
            case humanizedParams = "humanized_params"
        }

        var asResult: SearchResult {
            SearchResult(
                total: total ?? 0,
                currentPage: currentPage ?? 1,
                totalPages: totalPages ?? 0,
                humanizedParams: humanizedParams ?? "",
                listings: (listings ?? []).compactMap(\.value))
        }
    }
}

/// Port of `applySoldPrices` in `search.ts`. The REST API reports a sold
/// listing's last *ask* as `price` — an accepted offer's amount never appears
/// there. The real sale lives in Reverb's undocumented GraphQL
/// `priceRecordsSearch`; one aliased query per 50 listings, newest record wins
/// (a listing can sell twice). Best effort: any failure keeps the REST ask.
enum SoldPrices {
    static let url = URL(string: "https://gql.reverb.com/graphql")!

    struct Record: Decodable {
        struct Timestamp: Decodable { var seconds: Int? }
        /// camelCase on this wire, unlike REST's `Money`.
        struct Amount: Decodable { var amountCents: Int?; var currency: String?; var display: String? }
        var createdAt: Timestamp?
        var amountProduct: Amount?
    }
    struct Records: Decodable { var priceRecords: [Record]? }
    private struct Response: Decodable { var data: [String: Records?]? }

    static func apply(to listings: inout [Listing]) async {
        let ids = listings.filter { $0.state?.slug == "sold" }.map(\.id)
        guard !ids.isEmpty else { return }
        let chunks = stride(from: 0, to: ids.count, by: 50).map { Array(ids[$0..<min($0 + 50, ids.count)]) }
        let found = await withTaskGroup(of: [String: Records?].self) { group in
            for chunk in chunks { group.addTask { (try? await fetch(chunk)) ?? [:] } }
            return await group.reduce(into: [:]) { $0.merge($1) { a, _ in a } }
        }
        merge(found, into: &listings)
    }

    static func merge(_ found: [String: Records?], into listings: inout [Listing]) {
        for i in listings.indices {
            let newest = (found["l\(listings[i].id)"] ?? nil)?.priceRecords?
                .max { ($0.createdAt?.seconds ?? 0) < ($1.createdAt?.seconds ?? 0) }?.amountProduct
            guard let cents = newest?.amountCents, cents > 0, let display = newest?.display else { continue }
            if listings[i].originalPrice == nil { listings[i].originalPrice = listings[i].price }
            listings[i].price = Money(
                amount: String(format: "%.2f", Double(cents) / 100), amountCents: cents,
                currency: newest?.currency ?? listings[i].price?.currency, display: display)
        }
    }

    private static func fetch(_ ids: [Int]) async throws -> [String: Records?] {
        let fields = ids.map {
            "l\($0): priceRecordsSearch(input: {listingId: \"\($0)\"}) { priceRecords { createdAt { seconds } amountProduct { amountCents currency display } } }"
        }.joined(separator: " ")
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The gateway rejects anonymous operations with GW-001.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": "SoldPrices", "query": "query SoldPrices { \(fields) }",
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data).data ?? [:]
    }
}

/// One malformed listing shouldn't empty the whole page of results.
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
