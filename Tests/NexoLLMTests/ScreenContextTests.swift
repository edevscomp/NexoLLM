import XCTest
@testable import NexoLLM

final class ScreenContextTests: XCTestCase {
    private let caret = CGRect(x: 300, y: 800, width: 0, height: 16)

    func testChatInputBoxIsExcludedAndNearestLinesKept() {
        let field = CGRect(x: 250, y: 790, width: 600, height: 40)    // chat input
        let lines: [(String, CGRect)] = [
            ("Marco: ci vediamo domani alle 10?", CGRect(x: 260, y: 700, width: 300, height: 18)),
            ("Ieri: buon compleanno!", CGRect(x: 260, y: 200, width: 300, height: 18)),
            ("Scrivi un messaggio", CGRect(x: 260, y: 800, width: 200, height: 18)),   // inside input box
        ]
        let out = ScreenContext.select(lines, fieldAX: field, caretAX: caret, budget: 40)
        XCTAssertEqual(out, "Marco: ci vediamo domani alle 10?")
    }

    func testReadingOrderPreserved() {
        let lines: [(String, CGRect)] = [
            ("seconda riga", CGRect(x: 0, y: 600, width: 100, height: 18)),
            ("prima riga", CGRect(x: 0, y: 500, width: 100, height: 18)),
        ]
        let out = ScreenContext.select(lines, fieldAX: nil, caretAX: caret)
        XCTAssertEqual(out, "prima riga\nseconda riga")
    }

    func testCaretLineSkippedInLargeEditor() {
        let editor = CGRect(x: 0, y: 0, width: 900, height: 1000)
        let lines: [(String, CGRect)] = [
            ("titolo della nota", CGRect(x: 0, y: 100, width: 200, height: 18)),
            ("bozza che sto scrivendo", CGRect(x: 0, y: 799, width: 200, height: 18)),
        ]
        XCTAssertEqual(ScreenContext.select(lines, fieldAX: editor, caretAX: caret), "titolo della nota")
    }
}
