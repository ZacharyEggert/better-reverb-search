import Foundation

/// Free tier: five searches a day. Pagination and filter tweaks on an already
/// loaded result are free — only a new search spends.
///
/// ponytail: UserDefaults, so deleting the app resets the count. There is no
/// server to ask, and the honest fix is a backend. Move the counter to the
/// Keychain (see `APIKeyStore`, which survives reinstall) if freeloading ever
/// shows up in the numbers.
enum QueryQuota {
    static let dailyLimit = 5
    private static let key = "quota"

    static var used: Int {
        let stored = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        guard stored["day"] as? Int == today else { return 0 }
        return stored["count"] as? Int ?? 0
    }

    static var remaining: Int { max(0, dailyLimit - used) }

    static func consume() {
        UserDefaults.standard.set(["day": today, "count": used + 1], forKey: key)
    }

    /// Day number in the user's own calendar — the reset lands at their midnight,
    /// and a timezone change can only ever hand out an extra day, never revoke one.
    private static var today: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
    }
}
