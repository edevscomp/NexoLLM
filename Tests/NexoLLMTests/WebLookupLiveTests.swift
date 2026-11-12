import XCTest
@testable import NexoLLM

/// Real network checks for Web Lookup. Skipped unless `NEXO_LIVE=1` (never part of the normal suite).
final class WebLookupLiveTests: XCTestCase {
    private func run(_ q: String, answer: ((String, @escaping (String?) -> Void) -> Void)? = nil) -> Result<WebLookup.ResultCard, Error>? {
        var out: Result<WebLookup.ResultCard, Error>?
        let done = expectation(description: q)
        WebLookup.search(rawQuery: q, answerWith: answer) { r in out = r; done.fulfill() }
        wait(for: [done], timeout: 40)
        return out
    }

    private func dump(_ q: String, _ r: Result<WebLookup.ResultCard, Error>?) {
        switch r {
        case .success(let c)?:
            print("LIVE[\(q)] OK summary=\(c.summary)\n  bullets=\(c.bullets)\n  sources=\(c.sources.map { $0.url.absoluteString })")
        case .failure(let e)?: print("LIVE[\(q)] FAIL \(e)")
        case nil: print("LIVE[\(q)] TIMEOUT")
        }
    }

    func testLiveQueries() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NEXO_LIVE"] == "1")
        for q in ["avere il coltello dalla parte del manico", "coaa sta succednedo in palestina?", "avere il coltello fra i denti"] {
            let r = run(q)
            dump(q, r)
            if case .success = r {} else { XCTFail("no card for \(q)") }
        }
    }
}
