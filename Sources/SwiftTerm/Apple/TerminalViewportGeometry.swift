#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics

/// The rows and sub-row translation needed to draw a continuous terminal
/// viewport while the terminal model remains anchored to whole rows.
struct TerminalViewportGeometry: Equatable, Sendable {
    let firstRow: Int
    let lastRow: Int
    let offsetFromFirstRow: CGFloat

    var visibleRows: ClosedRange<Int> {
        firstRow...lastRow
    }

    func offsetFromAnchorRow(_ anchorRow: Int, cellHeight: CGFloat) -> CGFloat {
        CGFloat(firstRow - anchorRow) * cellHeight + offsetFromFirstRow
    }

    static func make(
        lineCount: Int,
        cellHeight: CGFloat,
        viewportHeight: CGFloat,
        scrollOffsetY: CGFloat
    ) -> TerminalViewportGeometry? {
        guard lineCount > 0, cellHeight > 0, viewportHeight > 0 else {
            return nil
        }

        let contentHeight = CGFloat(lineCount) * cellHeight
        let visibleStart = max(0, scrollOffsetY)
        let visibleEnd = min(contentHeight, scrollOffsetY + viewportHeight)
        guard visibleStart < visibleEnd else {
            return nil
        }

        let firstRow = min(lineCount - 1, max(0, Int(floor(visibleStart / cellHeight))))
        let lastExclusive = Int(ceil(visibleEnd / cellHeight))
        let lastRow = min(lineCount - 1, max(firstRow, lastExclusive - 1))

        return TerminalViewportGeometry(
            firstRow: firstRow,
            lastRow: lastRow,
            offsetFromFirstRow: scrollOffsetY - CGFloat(firstRow) * cellHeight
        )
    }
}
#endif
