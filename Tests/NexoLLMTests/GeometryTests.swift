import XCTest
@testable import NexoLLM

final class GeometryTests: XCTestCase {
    private let field = CGRect(x: 100, y: 200, width: 600, height: 300)

    // MARK: Caret

    func testCollapsedAndPreviousAgreeKeepsCollapsed() {
        let c = CaretGeometry.choose(collapsed: CGRect(x: 301, y: 240, width: 0, height: 18),
                                     previous: CGRect(x: 292, y: 240, width: 8, height: 18),
                                     previousIsSpace: false, field: field)
        XCTAssertEqual(c?.minX, 301)
    }

    func testBogusCollapsedAtFieldOriginLosesToPreviousCharacter() {
        let c = CaretGeometry.choose(collapsed: CGRect(x: 100, y: 200, width: 0, height: 18),
                                     previous: CGRect(x: 412, y: 330, width: 8, height: 18),
                                     previousIsSpace: false, field: field)
        XCTAssertEqual(c, CGRect(x: 420, y: 330, width: 0, height: 18))
    }

    func testZeroOriginPlaceholderIsRejected() {
        XCTAssertFalse(CaretGeometry.plausible(CGRect(x: 0, y: 0, width: 0, height: 18), field: nil))
        let c = CaretGeometry.choose(collapsed: CGRect(x: 0, y: 0, width: 0, height: 18), previous: nil,
                                     previousIsSpace: false, field: nil)
        XCTAssertNil(c)
    }

    func testParagraphTallBoxIsRejected() {
        XCTAssertFalse(CaretGeometry.plausible(CGRect(x: 120, y: 210, width: 0, height: 290), field: field))
    }

    func testCaretOutsideFieldIsRejected() {
        XCTAssertFalse(CaretGeometry.plausible(CGRect(x: 1400, y: 900, width: 0, height: 18), field: field))
        XCTAssertTrue(CaretGeometry.plausible(CGRect(x: 1400, y: 900, width: 0, height: 18), field: nil))
    }

    func testSoftWrapAfterSpaceKeepsCaretOnNextLine() {
        // The space ending the wrapped line is at the far right; the caret starts the next line.
        let c = CaretGeometry.choose(collapsed: CGRect(x: 104, y: 262, width: 0, height: 18),
                                     previous: CGRect(x: 690, y: 240, width: 4, height: 18),
                                     previousIsSpace: true, field: field)
        XCTAssertEqual(c?.minX, 104)
    }
}
