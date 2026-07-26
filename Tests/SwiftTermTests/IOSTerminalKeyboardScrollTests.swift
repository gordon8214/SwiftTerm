#if canImport(UIKit) && !os(watchOS)
import XCTest
import UIKit
@testable import SwiftTerm

final class IOSTerminalKeyboardScrollTests: XCTestCase {
    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.layoutIfNeeded()
        view.updateScroller()
        return view
    }

    func testKeyboardInsetDoesNotScrollAnAlreadyVisibleTopPromptIntoBlankRows() {
        let view = makeView()
        view.terminal.feed(text: "Resume this session with:\r\ncommand\r\nprompt> ")
        view.updateScroller()
        let originalOffset = view.contentOffset.y

        view.contentInset.bottom = 350
        view.ensureCaretIsVisible()

        XCTAssertEqual(view.contentOffset.y, originalOffset, accuracy: 0.001)
        assertCaretIsVisible(in: view)
    }

    func testKeyboardInsetScrollsOnlyFarEnoughToRevealCoveredCaret() {
        let view = makeView()
        view.terminal.feed(text: String(repeating: "line\r\n", count: 24))
        view.updateScroller()

        view.contentInset.bottom = 350
        let caretBottom = CGFloat(
            view.terminal.displayBuffer.yBase + view.terminal.displayBuffer.y + 1
        ) * view.cellDimension.height
        let expectedOffset = max(
            0,
            caretBottom - view.bounds.height + view.adjustedContentInset.bottom
        )
        view.ensureCaretIsVisible()

        XCTAssertEqual(view.contentOffset.y, expectedOffset, accuracy: 0.001)
        assertCaretIsVisible(in: view)
    }

    func testKeyboardInsetStillFollowsStreamingOutputAtTheBufferBottom() {
        let view = makeView()
        view.terminal.feed(text: String(repeating: "line\r\n", count: view.terminal.rows * 2))
        view.updateScroller()

        view.contentInset.bottom = 350
        view.ensureCaretIsVisible()

        let expectedBottom = max(
            0,
            view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
        )
        XCTAssertEqual(view.contentOffset.y, expectedBottom, accuracy: 0.001)
        assertCaretIsVisible(in: view)

        let previousBottom = view.contentOffset.y
        view.terminal.feed(text: "next line\r\n")
        view.updateScroller()

        let advancedBottom = max(
            0,
            view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
        )
        XCTAssertGreaterThan(advancedBottom, previousBottom)
        XCTAssertEqual(view.contentOffset.y, advancedBottom, accuracy: 0.001)
        assertCaretIsVisible(in: view)
    }

    /// A full-screen TUI parks the cursor on its input line and paints a status
    /// area underneath it. Following the caret alone stops short of the real
    /// bottom by exactly the rows below the cursor, so output painted there
    /// never scrolls into view.
    func testFollowingRevealsPaintedRowsBelowTheCaret() {
        let view = makeView()
        let rows = view.terminal.rows
        view.terminal.feed(text: String(repeating: "history\r\n", count: rows * 2))
        view.updateScroller()

        // Paint the last two grid rows, then park the caret two rows above the
        // bottom — CUP rows are 1-based, so `rows` addresses the final row.
        view.terminal.feed(text: "\u{1b}[\(rows - 1);1Hstatus\u{1b}[\(rows);1Hfooter")
        view.terminal.feed(text: "\u{1b}[\(rows - 2);1H")

        view.contentInset.bottom = 350
        view.ensureCaretIsVisible()

        let expectedBottom = max(
            0,
            view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
        )
        XCTAssertEqual(view.contentOffset.y, expectedBottom, accuracy: 0.001)
    }

    /// The blank tail of a grid whose prompt is still near the top must stay
    /// excluded from the anchor, otherwise the prompt scrolls out of view.
    func testFollowingIgnoresTheBlankTailBelowAShortPrompt() {
        let view = makeView()
        view.terminal.feed(text: "history\r\nprompt> ")
        view.updateScroller()
        let originalOffset = view.contentOffset.y

        view.contentInset.bottom = 350
        view.ensureCaretIsVisible()

        XCTAssertEqual(view.contentOffset.y, originalOffset, accuracy: 0.001)
        assertCaretIsVisible(in: view)
    }

    func testEraseScrollbackShrinksTheScrollViewAndReturnsItToTheViewport() {
        let view = makeView()
        let rows = view.terminal.rows
        view.feed(text: String(repeating: "history\r\n", count: rows * 2))
        view.updateScroller()

        XCTAssertGreaterThan(view.terminal.displayBuffer.lines.count, rows)
        XCTAssertGreaterThan(view.contentOffset.y, 0)

        view.feed(text: "\u{1b}[3J")

        XCTAssertEqual(view.terminal.displayBuffer.lines.count, rows)
        XCTAssertEqual(
            view.contentSize.height,
            CGFloat(rows) * view.cellDimension.height,
            accuracy: 0.001
        )
        XCTAssertEqual(view.contentOffset.y, 0, accuracy: 0.001)
    }

    private func assertCaretIsVisible(
        in view: TerminalView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let caretTop = CGFloat(
            view.terminal.displayBuffer.yBase + view.terminal.displayBuffer.y
        ) * view.cellDimension.height
        let caretBottom = caretTop + view.cellDimension.height
        let visibleTop = view.contentOffset.y + view.adjustedContentInset.top
        let visibleBottom =
            view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom

        XCTAssertGreaterThanOrEqual(caretTop, visibleTop, file: file, line: line)
        XCTAssertLessThanOrEqual(caretBottom, visibleBottom, file: file, line: line)
    }
}
#endif
