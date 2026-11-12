import XCTest
@testable import NexoLLM

final class StyleProfileTests: XCTestCase {
    private let chat = [
        "ciao come stai? tutto bene ahahah",
        "si dai ci sentiamo dopo cmq",
        "ahahah troppo forte 😂",
        "ok va bene ci sentiamo stasera",
        "cmq domani non ci sono ci sentiamo lunedì",
        "ahahah no dai 😂 va bene",
        "ciao tutto bene, ci sentiamo dopo",
        "va bene allora ci sentiamo domani",
        "nn so se riesco cmq ti scrivo",
        "ciao! ci sentiamo dopo 😂",
        "va bene perfetto ci sentiamo",
        "ahahah ok ci sentiamo dopo",
    ]

    func testLearnsChatHabits() throws {
        let p = try XCTUnwrap(StyleProfile.analyze(chat))
        XCTAssertTrue(p.traits.contains { $0.contains("Italian") }, "\(p.traits)")
        XCTAssertTrue(p.traits.contains { $0.contains("lowercase") }, "\(p.traits)")
        XCTAssertTrue(p.traits.contains { $0.contains("ahahah") }, "\(p.traits)")
        XCTAssertTrue(p.traits.contains { $0.contains("cmq") }, "\(p.traits)")
        XCTAssertTrue(p.traits.contains { $0.contains("😂") }, "\(p.traits)")
        XCTAssertTrue(p.phrases.contains { $0.contains("ci sentiamo") }, "\(p.phrases)")
        XCTAssertTrue(p.block.hasPrefix("[How the author writes]"))
        XCTAssertLessThan(p.block.count, 600)
    }

    func testLearnsEmailOpeningsAndClosings() throws {
        let emails = (0..<10).map { i in
            "Buongiorno Paolo,\nle scrivo in merito alla pratica numero \(i).\nResto a disposizione per chiarimenti.\nCordiali saluti\nMarco Rossi"
        }
        let p = try XCTUnwrap(StyleProfile.analyze(emails))
        XCTAssertTrue(p.openings.contains("Buongiorno Paolo"), "\(p.openings)")
        XCTAssertTrue(p.closings.contains("Marco Rossi") || p.closings.contains("Cordiali saluti"), "\(p.closings)")
        XCTAssertTrue(p.traits.contains { $0.contains("formal") }, "\(p.traits)")
    }

    func testNeedsEnoughSamples() {
        XCTAssertNil(StyleProfile.analyze(["ciao come stai oggi?", "tutto bene grazie mille"]))
    }

    func testLaughDetection() {
        XCTAssertTrue(StyleProfile.isLaugh("ahahah"))
        XCTAssertTrue(StyleProfile.isLaugh("hahaha"))
        XCTAssertFalse(StyleProfile.isLaugh("ahia"))
        XCTAssertFalse(StyleProfile.isLaugh("hhhh"))
    }
}
