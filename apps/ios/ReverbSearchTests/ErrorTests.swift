import Foundation
import Testing

@testable import ReverbSearch

/// The App Review rejection was a raw "API error 500: Unknown Error" on screen.
/// These pin the user-facing text: never a status code, always a next step.
@Suite("Error messages")
struct ErrorTests {
    @Test("Server faults read as advice, not as a status code",
          arguments: [500, 502, 503, 504])
    func serverFaults(_ code: Int) {
        let message = RevError.message(for: RevError.api(code, "Unknown Error"))
        #expect(!message.contains("\(code)"))
        #expect(!message.lowercased().contains("unknown error"))
        #expect(message.contains("temporarily unavailable"))
    }

    @Test("Auth failures point at the API key the user can actually change")
    func authFailures() {
        for code in [401, 403] {
            #expect(RevError.message(for: RevError.api(code, "")).contains("API key"))
        }
    }

    @Test("Rate limiting and bad requests each say what to do next")
    func clientFaults() {
        #expect(RevError.message(for: RevError.api(429, "")).contains("Wait a moment"))
        #expect(RevError.message(for: RevError.api(400, "")).contains("fewer filters"))
        #expect(RevError.message(for: RevError.api(422, "")).contains("fewer filters"))
        #expect(RevError.message(for: RevError.api(404, "")).contains("different search"))
    }

    @Test("Connectivity failures name the connection, not the framework")
    func urlErrors() {
        #expect(RevError.message(for: URLError(.notConnectedToInternet)).contains("No internet"))
        #expect(RevError.message(for: URLError(.networkConnectionLost)).contains("No internet"))
        #expect(RevError.message(for: URLError(.timedOut)).contains("timed out"))
        #expect(RevError.message(for: URLError(.cannotFindHost)).contains("Couldn't reach Reverb"))
    }

    @Test("Validation errors keep their own wording — the user typed the problem")
    func validation() {
        #expect(RevError.message(for: RevError.validation("Minimum price is above the maximum price."))
            == "Minimum price is above the maximum price.")
    }

    @Test("An unrecognised error still gets a sentence, never a Swift dump")
    func unknown() {
        struct Nameless: Error {}
        let message = RevError.message(for: Nameless())
        #expect(message == "The search couldn't be completed. Try again.")
    }

    @Test("Every message is a plain sentence a user can act on")
    func shapeOfEveryMessage() {
        let errors: [Error] = [
            RevError.api(500, "Unknown Error"), RevError.api(429, ""), RevError.api(401, ""),
            RevError.api(418, ""), RevError.other("Reverb sent back something odd."),
            URLError(.timedOut), URLError(.unknown),
        ]
        for error in errors {
            let message = RevError.message(for: error)
            #expect(!message.isEmpty)
            #expect(!message.contains("Error Domain"))
            #expect(!message.lowercased().contains("nsurlerror"))
            #expect(message.hasSuffix(".") || message.hasSuffix("!"))
        }
    }
}
