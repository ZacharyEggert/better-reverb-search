import Foundation
import Testing

@testable import ReverbSearch

/// These write the real app's UserDefaults (tests run in the app host), so each
/// one sandboxes the keys it touches. Serialized: the quota is global state.
@Suite("Free-tier quota", .serialized, .disabled(if: liveTestsEnabled, quotaSuiteReason))
struct QuotaTests {
    private let today = Calendar.current.ordinality(of: .day, in: .era, for: .now)!

    @Test("Counts down from the daily limit and clamps at zero")
    func countdown() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        #expect(QueryQuota.remaining == QueryQuota.dailyLimit)
        for _ in 0..<QueryQuota.dailyLimit { QueryQuota.consume() }
        #expect(QueryQuota.used == QueryQuota.dailyLimit)
        #expect(QueryQuota.remaining == 0)
        // Spending past empty can't push `remaining` negative.
        QueryQuota.consume()
        #expect(QueryQuota.remaining == 0)
    }

    @Test("A stale day starts over")
    func dailyReset() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        UserDefaults.standard.set(["day": today - 1, "count": 99], forKey: "quota")
        #expect(QueryQuota.used == 0)
        #expect(QueryQuota.remaining == QueryQuota.dailyLimit)
    }

    @Test("A stored code alone doesn't raise the limit — only a confirmed one")
    func codeMustBeVerified() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        #expect(!BypassCode.hasCode && QueryQuota.dailyLimit == 5)

        UserDefaults.standard.set("code", forKey: "bypassCode")
        // Stored but unconfirmed: an unreachable server leaves the default limit.
        #expect(BypassCode.hasCode)
        #expect(!BypassCode.isActive)
        #expect(QueryQuota.dailyLimit == 5)

        BypassCode.verified = true
        #expect(QueryQuota.dailyLimit == BypassCode.raisedLimit)

        BypassCode.remove()
        #expect(!BypassCode.hasCode && !BypassCode.isActive && QueryQuota.dailyLimit == 5)
    }

    @Test("A code buys a quiet app: no upgrade pitch until half the quota is spent")
    func upgradePitch() {
        let sandbox = DefaultsSandbox("quota", "bypassCode")
        defer { sandbox.restore() }
        // Without a code the pitch is always available.
        #expect(QueryQuota.offerUpgrade)

        UserDefaults.standard.set("code", forKey: "bypassCode")
        BypassCode.verified = true
        #expect(!QueryQuota.offerUpgrade)
        UserDefaults.standard.set(
            ["day": today, "count": BypassCode.raisedLimit / 2], forKey: "quota")
        #expect(QueryQuota.offerUpgrade)
    }
}

@Suite("API key storage", .serialized)
struct APIKeyStoreTests {
    /// The key lives in the host app's keychain — on a simulator that's the
    /// test install, not a real user's — but restore it anyway so a local run
    /// against a device build can't cost anyone their token.
    private func withSavedKey(_ body: () -> Void) {
        let existing = APIKeyStore.load()
        body()
        if let existing { APIKeyStore.save(existing) } else { APIKeyStore.remove() }
    }

    @Test("Round-trips through the keychain")
    func roundTrip() {
        withSavedKey {
            APIKeyStore.save("test-token-abc123")
            #expect(APIKeyStore.load() == "test-token-abc123")
        }
    }

    @Test("Saving twice replaces rather than duplicating")
    func replace() {
        withSavedKey {
            APIKeyStore.save("first")
            APIKeyStore.save("second")
            #expect(APIKeyStore.load() == "second")
        }
    }

    @Test("Removal is complete, and removing nothing is harmless")
    func remove() {
        withSavedKey {
            APIKeyStore.save("gone-soon")
            APIKeyStore.remove()
            #expect(APIKeyStore.load() == nil)
            APIKeyStore.remove()
            #expect(APIKeyStore.load() == nil)
        }
    }

    @Test("Unicode survives the round trip — the token is stored as UTF-8 bytes")
    func unicode() {
        withSavedKey {
            APIKeyStore.save("tøken-✓-123")
            #expect(APIKeyStore.load() == "tøken-✓-123")
        }
    }
}
