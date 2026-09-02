import Foundation
import Testing

@testable import ReverbSearch

/// Listings built from JSON rather than initialisers: `Listing` is Decodable-only,
/// and decoding is the path the app actually takes.
func makeListing(_ json: String) -> Listing {
    try! JSONDecoder().decode(Listing.self, from: Data(json.utf8))
}

func makeListing(
    id: Int = 1, title: String = "Fender Stratocaster", cents: Int? = nil,
    published: String? = nil
) -> Listing {
    var fields = ["\"id\": \(id)", "\"title\": \"\(title)\""]
    if let cents { fields.append("\"price\": {\"amount_cents\": \(cents), \"currency\": \"USD\"}") }
    if let published { fields.append("\"published_at\": \"\(published)\"") }
    return makeListing("{\(fields.joined(separator: ", "))}")
}

func params(_ query: SearchQuery) -> [String: String] {
    Dictionary(uniqueKeysWithValues: try! query.queryItems().map { ($0.name, $0.value ?? "") })
}

/// Fixed clock for the recency tests — "months ago" against `.now` would rot.
let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14

/// UserDefaults is the real app's, since tests run in the app host. Anything a
/// test writes gets put back, so a run doesn't spend the tester's own quota or
/// drop their promo code. `BypassCode.verified` is process state, restored too.
struct DefaultsSandbox {
    /// Suites run in parallel, but the quota, the promo flag, and the keychain
    /// are one per process — a sandboxed test holds this for its whole body.
    private static let lock = NSLock()

    private let saved: [String: Any?]
    private let wasVerified: Bool

    init(_ keys: String...) {
        Self.lock.lock()
        wasVerified = BypassCode.verified
        saved = Dictionary(
            uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        BypassCode.verified = false
    }

    func restore() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        BypassCode.verified = wasVerified
        Self.lock.unlock()
    }
}

/// Live tests talk to api.reverb.com, so they only run when asked for — the
/// Live test plan sets this, the Offline plan doesn't.
var liveTestsEnabled: Bool { ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" }

/// Suites that spend the shared quota can't run alongside the live suites — the
/// live plan runs the whole target, and Swift Testing runs suites in parallel.
var quotaSuiteReason: Comment { "quota state collides with the live suites" }

/// Reverb rate-limits; the live suite is serialized and every request waits.
func paceLiveRequest() async throws {
    try await Task.sleep(for: .milliseconds(500))
}
