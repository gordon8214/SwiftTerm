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
