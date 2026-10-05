import Foundation

/// Where every part of the open notch header goes, computed from the real
/// notch geometry so nothing ever sits under the camera cutout.
///
/// The header is one row: the tabs on the left of the notch, and the tab's
/// title, the Settings gear and the header shortcuts (the pet's paw) on the
/// right of it. Each side gets the room between the open shape's inset and a
/// safe margin from the cutout. When the tabs don't fit at full size they
/// first tighten (narrower buttons, then no gaps, never below `minTabWidth`),
/// and only then the last ones move behind a "more" button. On the right the
/// title truncates, and is dropped before it could collide with anything.
///
/// Frames are in the open canvas's coordinates: x from its left edge, y from
/// its top edge, the same space as `cutout`.
public struct NotchHeaderLayout: Equatable, Sendable {
    /// Sizes the header is built from. The defaults match the notch's design.
    public struct Metrics: Equatable, Sendable {
        /// Distance from the canvas edge to the first and last control: the
        /// open shape's top corner plus the content inset.
        public var outerInset: CGFloat = 32
        /// Clear room kept between any control and the camera cutout.
        public var cutoutMargin: CGFloat = 8
        /// Gap between the two sides on a display without a notch.
        public var notchlessGap: CGFloat = 24
        public var controlHeight: CGFloat = 24
        public var tabWidth: CGFloat = 28
        /// The smallest hit target a tab shrinks to before tabs overflow.
        public var minTabWidth: CGFloat = 24
        public var tabSpacing: CGFloat = 2
        public var moreWidth: CGFloat = 24
        public var gearSize: CGFloat = 22
        public var shortcutWidth: CGFloat = 28
        public var shortcutSpacing: CGFloat = 2
        /// Gap between the title, the gear and the shortcuts.
        public var trailingSpacing: CGFloat = 8
        /// A title squeezed narrower than this is dropped instead of shown as
        /// a lone ellipsis.
        public var minTitleWidth: CGFloat = 40

        public init() {}
    }

    /// The camera cutout, or nil on a display without a notch.
    public let cutout: CGRect?
    /// The room the tabs (and the "more" button) may use, left of the notch.
    public let leadingZone: CGRect
    /// The room the title, gear and shortcuts may use, right of the notch.
    public let trailingZone: CGRect
    /// Width of each tab button, between `Metrics.minTabWidth` and `Metrics.tabWidth`.
    public let tabWidth: CGFloat
    /// Gap between neighboring tabs (and before the "more" button).
    public let tabSpacing: CGFloat
    /// One frame per tab that shows in the row, in order; the rest overflow.
    public let tabFrames: [CGRect]
    /// The "more" button that reveals the tabs that didn't fit, or nil when all fit.
    public let moreFrame: CGRect?
    /// The tab title, nil when it was dropped to make room.
    public let titleFrame: CGRect?
    public let gearFrame: CGRect
    /// One frame per header shortcut, the last at the far right.
    public let shortcutFrames: [CGRect]

    /// How many tabs show in the row; tabs from this index on overflow.
    public var visibleTabCount: Int { tabFrames.count }
    public var hasOverflow: Bool { moreFrame != nil }

    /// Every control's frame, for checking that none meets the cutout.
    public var controlFrames: [CGRect] {
        tabFrames + [moreFrame, titleFrame, gearFrame].compactMap { $0 } + shortcutFrames
    }

    /// - Parameters:
    ///   - canvasWidth: width of the open notch.
    ///   - notchSize: size of the hardware notch, or nil on a display without one.
    ///   - headerHeight: height of the header row the controls center in.
    ///   - tabCount: tabs in the row before any overflow.
    ///   - shortcutCount: header shortcuts at the far right (the pet's paw).
    ///   - titleWidth: the title's natural width, as the app measures it.
    public init(canvasWidth: CGFloat, notchSize: CGSize?, headerHeight: CGFloat, tabCount: Int,
                shortcutCount: Int, titleWidth: CGFloat, metrics: Metrics = Metrics()) {
        let center = canvasWidth / 2
        let halfGap = notchSize.map { $0.width / 2 + metrics.cutoutMargin } ?? metrics.notchlessGap / 2
        cutout = notchSize.map { CGRect(x: center - $0.width / 2, y: 0, width: $0.width, height: $0.height) }
        let zoneWidth = max(center - halfGap - metrics.outerInset, 0)
        leadingZone = CGRect(x: metrics.outerInset, y: 0, width: zoneWidth, height: headerHeight)
        trailingZone = CGRect(x: center + halfGap, y: 0, width: zoneWidth, height: headerHeight)

        func row(_ x: CGFloat, _ width: CGFloat, height: CGFloat = metrics.controlHeight) -> CGRect {
            CGRect(x: x, y: ((headerHeight - height) / 2).rounded(), width: width, height: height)
        }

        // Tabs: full size, then narrower, then without gaps, then overflow.
        let tabs = max(tabCount, 0)
        let fit = Self.fitTabs(tabs, in: zoneWidth, metrics: metrics)
        tabWidth = fit.width
        tabSpacing = fit.spacing
        var x = leadingZone.minX
        var tabFrames: [CGRect] = []
        for _ in 0..<fit.visible {
            tabFrames.append(row(x, fit.width))
            x += fit.width + fit.spacing
        }
        self.tabFrames = tabFrames
        moreFrame = fit.visible < tabs ? row(x, metrics.moreWidth) : nil

        // Trailing side, laid out from the far right: shortcuts, gear, title.
        var right = trailingZone.maxX
        var shortcutFrames: [CGRect] = []
        for _ in 0..<max(shortcutCount, 0) {
            right -= metrics.shortcutWidth
            shortcutFrames.insert(row(right, metrics.shortcutWidth), at: 0)
            right -= metrics.shortcutSpacing
        }
        if !shortcutFrames.isEmpty { right += metrics.shortcutSpacing - metrics.trailingSpacing }
        right -= metrics.gearSize
        gearFrame = row(right, metrics.gearSize, height: metrics.gearSize)
        self.shortcutFrames = shortcutFrames
        let titleRoom = right - metrics.trailingSpacing - trailingZone.minX
        let shownTitle = min(titleWidth.rounded(.up), titleRoom)
        titleFrame = titleWidth > 0 && shownTitle >= min(metrics.minTitleWidth, titleWidth.rounded(.up))
            ? row(right - metrics.trailingSpacing - shownTitle, shownTitle) : nil
    }

    private static func fitTabs(_ count: Int, in room: CGFloat,
                                metrics: Metrics) -> (width: CGFloat, spacing: CGFloat, visible: Int) {
        guard count > 0 else { return (metrics.tabWidth, metrics.tabSpacing, 0) }
        for spacing in [metrics.tabSpacing, 0] {
            let width = min(metrics.tabWidth, ((room - CGFloat(count - 1) * spacing) / CGFloat(count)).rounded(.down))
            if width >= metrics.minTabWidth { return (width, spacing, count) }
        }
        // Overflow: smallest tabs without gaps, and the "more" button last.
        let visible = Int(((room - metrics.moreWidth) / metrics.minTabWidth).rounded(.down))
        return (metrics.minTabWidth, 0, min(max(visible, 0), count - 1))
    }
}
