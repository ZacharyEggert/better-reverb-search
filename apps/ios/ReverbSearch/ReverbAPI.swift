import Foundation

/// Port of `error.ts` — the arms that survive without a CLI (no auth/schema
/// paths are reachable here: search answers unauthenticated and the only
/// endpoint used is `GET /api/listings`).
enum RevError: LocalizedError {
    case api(Int, String)
    case validation(String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case let .api(code, message): "API error \(code): \(message)"
        case let .validation(message): "Validation error: \(message)"
        case let .other(message): message
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
                .flatMap { ($0?["message"] ?? $0?["Error"]) as? String } ?? "unknown error"
            throw RevError.api(status, message)
        }

        do {
            return try JSONDecoder().decode(Page.self, from: data).asResult
        } catch {
            throw RevError.other("failed to parse response: \(error.localizedDescription)")
        }
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
        throw RevError.api(429, "rate limit exceeded after retries")
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

/// One malformed listing shouldn't empty the whole page of results.
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
