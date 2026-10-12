import SwiftUI
import TabbiKitCore

/// One line of text that shows whole when it fits and, when it does not,
/// scrolls gently to reveal the rest: it rests at the start, eases across
/// until the end is in view, rests there, then fades back to the start
/// (`MarqueeMotion`). Font and color come from the environment, like a plain
/// `Text`, and a line that fits takes only the width it needs, so it centers
/// or aligns like one.
///
/// A line cut off at an edge fades out there instead of ending hard. The
/// pointer resting on it pauses the scroll so it can be read, its tooltip
/// and VoiceOver label carry the full text, and under Reduce Motion it stays
/// still, truncated with an ellipsis, with the tooltip. Right-to-left text
/// scrolls the other way. A line that fits runs no timer or animation, and
/// one that overflows only while it is on screen.
public struct MarqueeText: View {
    private let text: String
    private let help: String?

    /// - Parameter help: a tooltip to show at all times, in place of the
    ///   full text, which a line shows as its tooltip only while it doesn't fit.
    public init(_ text: String, help: String? = nil) {
        self.text = text
        self.help = help
    }

    public var body: some View {
        Marquee(text, help: help) { Text(verbatim: text) }
    }
}

/// `MarqueeText` for a line built from several pieces (a name in one color
/// and its detail in another, say), which scroll together as one line.
/// `text` is the whole line as plain text, for the tooltip and VoiceOver.
public struct Marquee<Content: View>: View {
    private let text: String
    private let help: String?
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rendersToImage) private var rendersToImage
    @Environment(\.marqueeScrolled) private var stillScrolled

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// When the current scroll started, so its pose is a function of time.
    @State private var startDate = Date()
    /// How far into its cycle the scroll was when the pointer came to rest
    /// on it; nil while it runs.
    @State private var pausedAt: TimeInterval?

    public init(_ text: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.text = text
        self.help = help
        self.content = content()
    }

    private var overflow: Double {
        MarqueeMotion.overflow(contentWidth: contentWidth, containerWidth: containerWidth)
    }

    /// A still image (a snapshot) can't play the scroll, so it shows the
    /// line at rest, or as far along as `marqueeScrolled` asks.
    private var scrolls: Bool {
        MarqueeMotion.scrolls(overflow: overflow, reduceMotion: reduceMotion && stillScrolled == nil)
    }

    public var body: some View {
        content
            .lineLimit(1)
            .truncationMode(.tail)
            // Kept in the layout while the scrolling copy shows, so the line
            // takes the same room either way.
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
            .background(alignment: .leading) {
                // Measures the whole line without taking part in the layout.
                content
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls { scrolling }
            }
            // An empty tooltip would hide one set around the line, so a
            // caller with a tooltip of its own passes it in as `help`.
            .help(help ?? (overflow > 0 ? text : ""))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .onHover { hovering in
                if hovering {
                    pausedAt = Date().timeIntervalSince(startDate)
                } else if let pausedAt {
                    startDate = Date().addingTimeInterval(-pausedAt)
                    self.pausedAt = nil
                }
            }
            // A new line, or one that starts to overflow, starts from its beginning.
            .onChange(of: scrolls) { _, scrolls in
                if scrolls { startDate = .now }
            }
            .onChange(of: text) {
                startDate = .now
                if pausedAt != nil { pausedAt = 0 }
            }
    }

    @ViewBuilder private var scrolling: some View {
        if let stillScrolled {
            line(MarqueeMotion.pose(scrolled: stillScrolled, overflow: overflow))
        } else if rendersToImage {
            line(.rest)
        } else {
            TimelineView(.animation(minimumInterval: 1 / MarqueeMotion.frameRate, paused: pausedAt != nil)) { context in
                line(MarqueeMotion.pose(elapsed: pausedAt ?? context.date.timeIntervalSince(startDate),
                                        overflow: overflow))
            }
        }
    }

    /// The whole line shifted by `pose`, clipped to the room it has. The
    /// layout mirrors for right-to-left text, so the shift toward the
    /// leading edge and the fades follow the reading direction.
    private func line(_ pose: MarqueeMotion.Pose) -> some View {
        let width = max(containerWidth, 1)
        let fade = MarqueeMotion.edgeFade
        // Each edge fades only while text is cut off there, so the first
        // letter is crisp at rest and the last once the end is in view.
        let leading = min(pose.offset, fade) / width
        let trailing = min(overflow - pose.offset, fade) / width
        return content
            .lineLimit(1)
            .fixedSize()
            .offset(x: -pose.offset)
            .opacity(pose.opacity)
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: leading),
                    .init(color: .black, location: 1 - trailing),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
            .accessibilityHidden(true)
    }
}

public extension EnvironmentValues {
    /// For still renders (snapshots): draws every `MarqueeText` that
    /// overflows this fraction of the way through its scroll, 0 at the start
    /// and 1 at the end. Nil, the default, plays the scroll.
    @Entry var marqueeScrolled: Double? = nil
}
