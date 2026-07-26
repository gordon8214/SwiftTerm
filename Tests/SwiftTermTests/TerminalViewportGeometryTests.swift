#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import Testing

@testable import SwiftTerm

struct TerminalViewportGeometryTests {
    @Test func alignedViewportUsesWholeRows() throws {
        let geometry = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 20
            )
        )

        #expect(geometry.visibleRows == 2...5)
        #expect(geometry.offsetFromFirstRow == 0)
    }

    @Test func fractionalViewportIncludesBothBoundaryRows() throws {
        let geometry = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 25
            )
        )

        #expect(geometry.visibleRows == 2...6)
        #expect(geometry.offsetFromFirstRow == 5)
    }

    @Test func rowCrossingsAndReverseMotionPreserveRemainder() throws {
        let beforeCrossing = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 29.75
            )
        )
        let afterCrossing = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 30.25
            )
        )
        let reversed = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 19.75
            )
        )

        #expect(beforeCrossing.firstRow == 2)
        #expect(beforeCrossing.offsetFromFirstRow == 9.75)
        #expect(afterCrossing.firstRow == 3)
        #expect(afterCrossing.offsetFromFirstRow == 0.25)
        #expect(reversed.firstRow == 1)
        #expect(reversed.offsetFromFirstRow == 9.75)
    }

    @Test func anchoredTranslationStaysContinuousAcrossRowBoundaries() throws {
        let beforeCrossing = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 29.75
            )
        )
        let afterCrossing = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 30.25
            )
        )

        #expect(beforeCrossing.offsetFromAnchorRow(2, cellHeight: 10) == 9.75)
        #expect(afterCrossing.offsetFromAnchorRow(2, cellHeight: 10) == 10.25)
    }

    @Test func topBounceRetainsSignedVisualOffset() throws {
        let geometry = try #require(
            TerminalViewportGeometry.make(
                lineCount: 100,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: -4
            )
        )

        #expect(geometry.visibleRows == 0...3)
        #expect(geometry.offsetFromFirstRow == -4)
    }

    @Test func bottomInsetLeavesBlankSpaceWithoutReadingPastBuffer() throws {
        let geometry = try #require(
            TerminalViewportGeometry.make(
                lineCount: 10,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 64
            )
        )

        #expect(geometry.visibleRows == 6...9)
        #expect(geometry.offsetFromFirstRow == 4)
    }

    @Test func viewportOutsideContentAndInvalidDimensionsHaveNoRows() {
        #expect(
            TerminalViewportGeometry.make(
                lineCount: 10,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 100
            ) == nil
        )
        #expect(
            TerminalViewportGeometry.make(
                lineCount: 0,
                cellHeight: 10,
                viewportHeight: 40,
                scrollOffsetY: 0
            ) == nil
        )
        #expect(
            TerminalViewportGeometry.make(
                lineCount: 10,
                cellHeight: 0,
                viewportHeight: 40,
                scrollOffsetY: 0
            ) == nil
        )
    }
}

#if os(macOS)
import AppKit
import MetalKit

@MainActor
struct MacTerminalViewportTests {
    private func makeScrollableView() -> TerminalView {
        let view = TerminalView(
            frame: CGRect(origin: .zero, size: CGSize(width: 400, height: 160))
        )
        for line in 0..<80 {
            view.terminal.feed(text: "line \(line)\r\n")
        }
        return view
    }

    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    @Test func preciseScrollPreservesFractionsAcrossRowsAndReverseMotion() throws {
        let view = makeScrollableView()
        let cellHeight = view.cellDimension.height
        let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
        let startingRow = bottomRow - 4
        view.scrollTo(row: startingRow)

        #expect(view.scrollNormalBuffer(byPreciseDelta: -cellHeight * 0.25))
        #expect(view.terminal.displayBuffer.yDisp == startingRow)
        #expect(approximatelyEqual(view.manualScrollOffsetWithinRow, cellHeight * 0.25))

        let fractionalGeometry = try #require(view.terminalViewportGeometry())
        #expect(fractionalGeometry.firstRow == startingRow)
        #expect(fractionalGeometry.lastRow == startingRow + view.terminal.rows)

        #expect(view.scrollNormalBuffer(byPreciseDelta: -cellHeight))
        #expect(view.terminal.displayBuffer.yDisp == startingRow + 1)
        #expect(approximatelyEqual(view.manualScrollOffsetWithinRow, cellHeight * 0.25))

        #expect(view.scrollNormalBuffer(byPreciseDelta: cellHeight * 0.5))
        #expect(view.terminal.displayBuffer.yDisp == startingRow)
        #expect(approximatelyEqual(view.manualScrollOffsetWithinRow, cellHeight * 0.75))
    }

    @Test func preciseScrollClampsAtTopAndBottom() {
        let view = makeScrollableView()
        let cellHeight = view.cellDimension.height
        let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows

        view.scrollTo(row: 0)
        #expect(!view.scrollNormalBuffer(byPreciseDelta: cellHeight))
        #expect(view.terminal.displayBuffer.yDisp == 0)
        #expect(view.manualScrollOffsetWithinRow == 0)

        view.scrollTo(row: bottomRow - 1)
        #expect(view.scrollNormalBuffer(byPreciseDelta: -cellHeight * 3))
        #expect(view.terminal.displayBuffer.yDisp == bottomRow)
        #expect(view.manualScrollOffsetWithinRow == 0)
        #expect(!view.terminal.userScrolling)
    }

    @Test func rowNavigationFontChangeBufferSwitchAndLiveFollowResetFraction() {
        let view = makeScrollableView()
        let cellHeight = view.cellDimension.height
        let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
        let startingRow = bottomRow - 4

        view.scrollTo(row: startingRow)
        _ = view.scrollNormalBuffer(byPreciseDelta: -cellHeight * 0.5)
        view.scrollTo(row: startingRow)
        #expect(view.manualScrollOffsetWithinRow == 0)

        _ = view.scrollNormalBuffer(byPreciseDelta: -cellHeight * 0.5)
        view.resetFont()
        #expect(view.manualScrollOffsetWithinRow == 0)

        _ = view.scrollNormalBuffer(byPreciseDelta: -view.cellDimension.height * 0.5)
        view.terminal.feed(text: "\u{001B}[?1049h")
        #expect(view.terminal.isDisplayBufferAlternate)
        #expect(view.manualScrollOffsetWithinRow == 0)
        view.terminal.feed(text: "\u{001B}[?1049l")

        let refreshedBottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
        view.scrollTo(row: refreshedBottomRow - 2)
        _ = view.scrollNormalBuffer(byPreciseDelta: -view.cellDimension.height * 0.5)
        view.userScrolling = false
        view.terminal.userScrolling = false
        view.terminal.feed(text: "live output\r\n")
        #expect(view.manualScrollOffsetWithinRow == 0)
    }

    @Test func fractionalMouseHitUsesTranslatedViewport() {
        let view = makeScrollableView()
        let cellHeight = view.cellDimension.height
        let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
        let startingRow = bottomRow - 4
        view.scrollTo(row: startingRow)
        _ = view.scrollNormalBuffer(byPreciseDelta: -cellHeight * 0.5)

        let upperHit = view.calculateMouseHit(
            at: CGPoint(x: 0, y: view.bounds.height - cellHeight * 0.49)
        )
        let lowerHit = view.calculateMouseHit(
            at: CGPoint(x: 0, y: view.bounds.height - cellHeight * 0.51)
        )

        #expect(upperHit.grid.row == startingRow)
        #expect(lowerHit.grid.row == startingRow + 1)
    }

    @Test func caretAppearsWhenFractionExposesItsBoundaryRow() {
        let view = makeScrollableView()
        let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
        view.scrollTo(row: bottomRow - 1)
        view.updateCursorPosition()
        #expect(view.caretView.superview == nil)

        _ = view.scrollNormalBuffer(byPreciseDelta: -view.cellDimension.height * 0.5)

        #expect(view.caretView.superview === view)
        #expect(view.caretView.frame.maxY > view.terminalViewportBottomMarginHeight)
        let visibleCaretFrame = view.caretView.frame.intersection(view.terminalViewportClipRect)
        let expectedClipRect = visibleCaretFrame.offsetBy(
            dx: -view.caretView.frame.minX,
            dy: -view.caretView.frame.minY
        )
        #expect(view.caretView.viewportClipRect == expectedClipRect)
        #expect(view.caretView.viewportClipRect?.minY == view.cellDimension.height * 0.5)
    }

    @Test func metalDirtyRangesAreMergedUntilTheRendererConsumesThem() {
        let view = makeScrollableView()
        view.metalDirtyRange = 12...14

        view.markMetalDirty(8...9)
        view.markMetalDirty(18...20)

        #expect(view.metalDirtyRange == 8...20)
    }

    @Test func metalViewUsesTheCurrentScreensMaximumRefreshRate() throws {
        let view = makeScrollableView()
        let window = NSWindow(
            contentRect: view.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        let metalView = MTKView(frame: view.bounds, device: nil)
        view.updateMetalPreferredFramesPerSecond(for: metalView)

        let expectedFramesPerSecond: Int
        if #available(macOS 12.0, *) {
            expectedFramesPerSecond = window.screen?.maximumFramesPerSecond ?? 120
        } else {
            expectedFramesPerSecond = 120
        }
        #expect(metalView.preferredFramesPerSecond == expectedFramesPerSecond)
    }

    @Test func metalBufferingModeChangesPreserveFractionalGeometry() throws {
        for bufferingMode in [MetalBufferingMode.perRowPersistent, .perFrameAggregated] {
            let view = makeScrollableView()
            let bottomRow = view.terminal.displayBuffer.lines.count - view.terminal.rows
            view.scrollTo(row: bottomRow - 4)
            _ = view.scrollNormalBuffer(byPreciseDelta: -view.cellDimension.height * 0.5)
            let expectedOffset = view.manualScrollOffsetWithinRow

            view.metalBufferingMode = bufferingMode
            let geometry = try #require(view.terminalViewportGeometry())

            #expect(geometry.visibleRows.count == view.terminal.rows + 1)
            #expect(approximatelyEqual(view.manualScrollOffsetWithinRow, expectedOffset))
        }
    }
}
#endif
#endif
