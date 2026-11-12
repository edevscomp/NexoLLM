import XCTest
@testable import NexoLLM

final class MemoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func hours(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    private func memoryWithCut() -> Memory {
        let m = Memory(url: nil)
        m.forgetAfter = 3 * 86_400
        m.ingest([.init(app: "net.whatsapp.WhatsApp", appName: "WhatsApp",
                        text: "Ciao Marco! Oggi mi sono tagliato il dito con una lattina, fa malissimo. Va be, ci sentiamo.",
                        screen: "Marco: come stai? tutto ok col dito tagliato?\nOnline")],
                 now: t0, sync: true)
        return m
    }

    func testStemsCollapseInflections() {
        XCTAssertEqual(Memory.stems("tagliato tagliata taglio"), ["tagli"])
        XCTAssertEqual(Memory.stems("dito dita"), ["dit"])
        XCTAssertTrue(Memory.stems("questo perché però oggi").isEmpty)   // stop/time words aren't topics
    }

    func testRemembersThePersonalSentenceWithItsContext() {
        let m = memoryWithCut()
        XCTAssertEqual(m.count, 1)
        let e = m.episodes[0]
        XCTAssertTrue(e.text.contains("tagliato il dito"))
        XCTAssertEqual(e.context, "Marco: come stai? tutto ok col dito tagliato?")
    }

    func testIgnoresSmallTalkAndTechnicalText() {
        XCTAssertTrue(Memory.extract("Ciao, come va? Tutto bene grazie.", screen: nil).isEmpty)
        XCTAssertTrue(Memory.extract("let url = \"https://example.com/api\" { return value }", screen: nil).isEmpty)
    }

    func testRecallsTheTopicTheNextDay() {
        let m = memoryWithCut()
        let r = m.recall(query: "Ehi Marco, il dito fa ancora", draft: "Ehi Marco, il dito fa ancora",
                         app: "net.whatsapp.WhatsApp", now: hours(20))
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.block.contains("tagliato il dito"))
        XCTAssertTrue(r!.block.contains("hours ago"))
    }

    func testDoesNotLeakIntoUnrelatedWorkEmail() {
        let m = memoryWithCut()
        XCTAssertNil(m.recall(query: "Gentile Dottor Rossi, le invio il preventivo aggiornato per il progetto",
                              draft: "", app: "com.apple.mail", now: hours(2)))
        // A single generic word in another app isn't enough either.
        XCTAssertNil(m.recall(query: "mi fa male il dito", draft: "", app: "com.apple.mail", now: hours(2)))
    }

    func testNoEchoOfTheTextBeingWritten() {
        let m = memoryWithCut()
        let draft = "Oggi mi sono tagliato il dito con una lattina, fa malissimo."
        XCTAssertNil(m.recall(query: draft, draft: draft, app: "net.whatsapp.WhatsApp", now: hours(0.1)))
    }

    func testFadesAwayWhenNotMentioned() {
        let m = memoryWithCut()
        m.prune(now: hours(24 * 2))
        XCTAssertEqual(m.count, 1)
        m.prune(now: hours(24 * 3.2))
        XCTAssertEqual(m.count, 0)
    }

    func testMentioningAgainReinforcesInsteadOfDuplicating() {
        let m = memoryWithCut()
        m.ingest([.init(app: "com.apple.MobileSMS", appName: "Messages",
                        text: "Mamma, il dito tagliato con la lattina va un po' meglio oggi.", screen: nil)],
                 now: hours(30), sync: true)
        XCTAssertEqual(m.count, 1)
        XCTAssertGreaterThan(m.episodes[0].strength, 1)
        m.prune(now: hours(30 + 24 * 3))   // would have been forgotten without the second mention
        XCTAssertEqual(m.count, 1)
    }

    func testNewTextStartsAtWordBoundary() {
        XCTAssertEqual(CompletionController.newText(base: "Nota vecchia. ", last: "Nota vecchia. Mi sono tagliato il dito"),
                       "Mi sono tagliato il dito")
        XCTAssertEqual(CompletionController.newText(base: "Nota vecchia. Mi", last: "Nota vecchia. Mi sono tagliato il dito"),
                       "Mi sono tagliato il dito")
        XCTAssertNil(CompletionController.newText(base: "abc", last: "abc def"))
    }
}
