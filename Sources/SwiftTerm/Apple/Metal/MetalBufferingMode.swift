#if os(macOS) || os(iOS) || os(visionOS)
/// Controls how the Metal renderer builds and caches GPU buffers each frame.
///
/// The buffering mode affects the trade-off between memory usage and redraw
/// performance. You can change this at any time via
/// ``TerminalView/metalBufferingMode``.
public enum MetalBufferingMode {
    /// Each terminal row's vertex data is cached independently and reused across
    /// frames. Only rows marked dirty are rebuilt, making this the best choice
    /// for typical interactive use where only a few rows change per frame.
    case perRowPersistent

    /// All visible rows are aggregated into a small set of full-frame buffers.
    /// Content changes rebuild the aggregate, while viewport-only frames reuse
    /// it. This avoids per-row draw calls and may be preferable for workloads
    /// that redraw most of the screen (for example, full-screen TUI
    /// applications).
    case perFrameAggregated
}
#endif
