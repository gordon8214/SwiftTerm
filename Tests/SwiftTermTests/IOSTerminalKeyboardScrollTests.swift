#if canImport(UIKit) && !os(watchOS)
import XCTest
import UIKit
@testable import SwiftTerm

/// `isTracking` is the signal SwiftTerm uses to tell a real finger apart from a
/// layout- or terminal-driven `contentOffset` change, and UIKit only sets it from
/// live touch delivery. Overriding it lets a test drive the finger-down path.
private final class TrackingTerminalView: TerminalView {
    var trackingOverride = false
    override var isTracking: Bool { trackingOverride }

    func withFingerDown(_ body: () -> Void) {
        trackingOverride = true
        body()
        trackingOverride = false
    }
}

final class IOSTerminalKeyboardScrollTests: XCTestCase {
    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.layoutIfNeeded()
        view.updateScroller()
        return view
    }

    private func makeTrackingView() -> TrackingTerminalView {
        let view = TrackingTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), font: nil)
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

    /// A full-screen renderer can leave the cursor parked at the top of the grid
    /// between frames. Capping the follow pin so that caret stayed on screen
    /// pinned the viewport a whole keyboard's worth of rows above the live
    /// output, and because the pin was derived from wherever the view already
    /// sat, every later frame re-derived the same cap — the view never came back
    /// down.
    func testKeyboardWithTheCaretParkedAtTheTopOfTheGridStillFollowsTheTail() {
        let view = makeView()
        let rows = view.terminal.rows
        view.terminal.feed(text: String(repeating: "history\r\n", count: rows * 3))
        view.terminal.feed(text: "\u{1b}[1;1H")
        view.updateScroller()

        view.contentInset.bottom = 350
        view.ensureCaretIsVisible()
        assertPaintedTailIsVisible(in: view)

        // Streaming output with the cursor still parked high must keep tracking
        // the tail rather than settle above it.
        for _ in 0..<5 {
            view.terminal.feed(text: "streamed\r\n\u{1b}[1;1H")
            view.updateScroller()
            assertPaintedTailIsVisible(in: view)
        }
    }

    /// Follow mode rests against the *painted* tail, which sits above the scroll
    /// view's maximum whenever the buffer's last rows are blank. "Am I at the
    /// bottom" has to be measured against that resting position: measuring
    /// against the maximum classified a perfectly-followed viewport as scrolled
    /// away, so the first finger contact that nudged `contentOffset` froze
    /// history there and live output ran off the bottom.
    func testFingerContactAtTheFollowRestingPositionDoesNotFreezeHistory() {
        let view = makeTrackingView()
        let rows = view.terminal.rows
        view.terminal.feed(text: String(repeating: "history\r\n", count: rows * 3))
        // Park the caret five rows above the grid bottom and erase below it, so
        // the painted tail — and with it the follow position — sits above the
        // scroll view's maximum.
        view.terminal.feed(text: "\u{1b}[\(rows - 4);1H\u{1b}[J")
        view.updateScroller()
        XCTAssertLessThan(
            view.contentOffset.y,
            view.contentSize.height - view.bounds.height - view.cellDimension.height
        )

        view.withFingerDown {
            view.contentOffset.y -= 1
        }

        XCTAssertFalse(view.userScrolling)
        XCTAssertFalse(view.terminal.userScrolling)

        view.terminal.feed(text: String(repeating: "streamed\r\n", count: 20))
        view.updateScroller()
        assertPaintedTailIsVisible(in: view)
    }

    /// A deliberate scroll into history must still freeze the viewport while
    /// output streams, and reaching the follow position again must release it.
    func testDeliberateScrollFreezesHistoryAndReturningReleasesIt() {
        let view = makeTrackingView()
        view.terminal.feed(text: String(repeating: "history\r\n", count: view.terminal.rows * 3))
        view.updateScroller()

        let frozenOffset = view.contentOffset.y - 10 * view.cellDimension.height
        view.withFingerDown {
            view.contentOffset.y = frozenOffset
        }
        XCTAssertTrue(view.userScrolling)

        view.terminal.feed(text: String(repeating: "streamed\r\n", count: 10))
        view.updateScroller()
        XCTAssertEqual(view.contentOffset.y, frozenOffset, accuracy: 0.001)

        view.withFingerDown {
            view.contentOffset.y = view.contentSize.height
        }
        XCTAssertFalse(view.userScrolling)

        view.terminal.feed(text: "streamed\r\n")
        view.updateScroller()
        assertPaintedTailIsVisible(in: view)
    }

    /// Repainting rows below the caret scrolls nothing, so it emits no scroll
    /// notification and nothing revisits the follow position. The per-frame
    /// display update has to be the backstop.
    func testDisplayUpdateFollowsARepaintThatDoesNotScroll() {
        let view = makeView()
        let rows = view.terminal.rows
        view.terminal.feed(text: String(repeating: "history\r\n", count: rows * 3))
        // Erase the last four grid rows: the follow position rises with the
        // painted tail.
        view.terminal.feed(text: "\u{1b}[\(rows - 3);1H\u{1b}[J")
        view.updateScroller()
        let erasedOffset = view.contentOffset.y

        // Repaint those rows in place. Absolute addressing scrolls nothing.
        view.terminal.feed(text: "\u{1b}[\(rows);1Hfooter")
        XCTAssertEqual(view.contentOffset.y, erasedOffset, accuracy: 0.001)

        view.updateDisplay()

        assertPaintedTailIsVisible(in: view)
        XCTAssertGreaterThan(view.contentOffset.y, erasedOffset)
    }

    /// The guarantee follow mode owes the user: the bottom-most row with
    /// anything on it sits inside the unobscured region — neither stranded below
    /// the viewport where live output would never be seen, nor scrolled off the
    /// top to make room for blank rows.
    private func assertPaintedTailIsVisible(
        in view: TerminalView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let buffer = view.terminal.displayBuffer
        let caretRow = buffer.yBase + buffer.y
        var tailRow = buffer.lines.count - 1
        while tailRow > caretRow, buffer.lines[tailRow].getTrimmedLength() == 0 {
            tailRow -= 1
        }
        let tailTop = CGFloat(tailRow) * view.cellDimension.height
        let tailBottom = tailTop + view.cellDimension.height
        let visibleTop = view.contentOffset.y + view.adjustedContentInset.top
        let visibleBottom =
            view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom

        XCTAssertLessThanOrEqual(tailBottom, visibleBottom + 0.001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(tailTop, visibleTop - 0.001, file: file, line: line)
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
