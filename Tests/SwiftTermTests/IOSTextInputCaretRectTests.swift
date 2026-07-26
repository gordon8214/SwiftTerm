#if canImport(UIKit) && !os(watchOS)
import XCTest
import UIKit
@testable import SwiftTerm

/// `firstRect(for:)` / `caretRect(for:)` / `selectionRects(for:)` used to return
/// the whole `bounds`, which made UIKit anchor IME candidate popovers, dictation
/// UI, and caret-driven scroll-into-view to the terminal rather than the cursor.
/// These cover the cursor-cell anchoring that replaced it.
final class IOSTextInputCaretRectTests: XCTestCase {
    private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
    }

    func testCaretRectIsOneCellNotTheWholeBounds() {
        let view = makeView()
        let rect = view.caretRect(for: TextPosition(offset: 0))

        XCTAssertEqual(rect.width, view.cellDimension.width, accuracy: 0.001)
        XCTAssertEqual(rect.height, view.cellDimension.height, accuracy: 0.001)
        XCTAssertNotEqual(rect, view.bounds)
    }

    func testCaretRectTracksCursorColumn() {
        let view = makeView()
        let atOrigin = view.caretRect(for: TextPosition(offset: 0))

        view.terminal.feed(text: "abcd")
        let afterFourColumns = view.caretRect(for: TextPosition(offset: 0))

        XCTAssertEqual(view.terminal.buffer.x, 4)
        XCTAssertEqual(
            afterFourColumns.minX - atOrigin.minX,
            view.cellDimension.width * 4,
            accuracy: 0.001
        )
        XCTAssertEqual(afterFourColumns.minY, atOrigin.minY, accuracy: 0.001)
    }

    func testCaretRectTracksCursorRow() {
        let view = makeView()
        let firstRow = view.caretRect(for: TextPosition(offset: 0))

        view.terminal.feed(text: "one\r\ntwo\r\n")
        let thirdRow = view.caretRect(for: TextPosition(offset: 0))

        XCTAssertEqual(view.terminal.buffer.y, 2)
        XCTAssertEqual(
            thirdRow.minY - firstRow.minY,
            view.cellDimension.height * 2,
            accuracy: 0.001
        )
    }

    func testCaretRectStaysWithinVisibleBounds() {
        let view = makeView()
        // Push the cursor far past the bottom of the viewport; the anchor has to
        // clamp into the visible region or UIKit places its popovers offscreen.
        view.terminal.feed(text: String(repeating: "line\r\n", count: 200))
        let rect = view.caretRect(for: TextPosition(offset: 0))

        XCTAssertTrue(
            view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect),
            "caret anchor \(rect) escaped visible bounds \(view.bounds)"
        )
    }

    func testFirstRectAndSelectionRectsShareTheCaretAnchor() {
        let view = makeView()
        view.terminal.feed(text: "hello")

        let anchor = view.textInputCursorAnchorRect()
        let range = TextRange(from: TextPosition(offset: 0), to: TextPosition(offset: 0))

        XCTAssertEqual(view.firstRect(for: range), anchor)
        XCTAssertEqual(view.selectionRects(for: range).first?.rect, anchor)
    }
}
#endif
