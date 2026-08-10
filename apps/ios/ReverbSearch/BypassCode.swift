import Foundation

/// Promo code that raises the free daily limit. The server owns the answer —
/// the app only caches the code and the last verdict.
///
/// ponytail: UserDefaults, not the Keychain. A promo code is a coupon, not a
/// bearer token, and the endpoint re-checks it every launch anyway.
enum BypassCode {
    static let endpoint = URL(string: "https://reverb-search.diablo.guitars/api/bypass-limit")!
    static let raisedLimit = 1000

    private static let key = "bypassCode"

    /// The raised limit is live only once the server has confirmed the code
    /// this launch — an unreachable server means the default limit, not a free
    /// pass. Not persisted, so every launch has to earn it again.
    nonisolated(unsafe) static var verified = false

    static var isActive: Bool { verified }

    /// A code is stored, whether or not it's been confirmed yet.
    static var hasCode: Bool { UserDefaults.standard.string(forKey: key) != nil }

    enum Check { case noCode, valid, invalid, unreachable }

    /// Re-checks the stored code. Rejection drops it; an unreachable server
    /// keeps it but leaves the limit at the default.
    @discardableResult
    static func refresh() async -> Check {
        guard let code = UserDefaults.standard.string(forKey: key) else { return .noCode }
        guard let valid = await verify(code) else { return .unreachable }
        verified = valid
        if !valid { UserDefaults.standard.removeObject(forKey: key) }
        return valid ? .valid : .invalid
    }

    /// Stores the code if the server accepts it. Returns whether it did;
    /// throws when the endpoint couldn't be reached.
    @discardableResult
    static func submit(_ code: String) async throws -> Bool {
        guard let valid = await verify(code) else {
            throw RevError.other("Couldn't reach the server — try again.")
        }
        if valid {
            UserDefaults.standard.set(code, forKey: key)
            verified = true
        }
        return valid
    }

    static func remove() {
        UserDefaults.standard.removeObject(forKey: key)
        verified = false
    }

    /// nil means "couldn't tell" — never treat that as a rejection.
    private static func verify(_ code: String) async -> Bool? {
        var request = URLRequest(url: endpoint, timeoutInterval: ReverbAPI.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ReverbAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode(["key": code])

        struct Verdict: Decodable { let valid: Bool }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let verdict = try? JSONDecoder().decode(Verdict.self, from: data)
        else { return nil }
        return verdict.valid
    }
}
