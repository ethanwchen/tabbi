import Foundation

/// How the pet looks while it models each break move: which clip it plays.
///
/// Today every pet uses `standard`, the plain clips (`BreakMove.animation`).
/// This is the seam for cosmetic break props later on (a yoga mat for the
/// stretch, a water bottle for the sip): a set of props swaps the clip per
/// move, and every view that draws a break moment asks the props, so a new
/// set needs no view changes.
public struct BreakProps: Hashable, Sendable {
    /// A stable id for the set, so a future pick can be saved.
    public let id: String
    private let clips: [BreakMove: PetAnimation]

    public init(id: String, clips: [BreakMove: PetAnimation] = [:]) {
        self.id = id
        self.clips = clips
    }

    /// The plain look every pet has.
    public static let standard = BreakProps(id: "standard")

    /// The clip the pet loops while it models `move`.
    public func animation(for move: BreakMove) -> PetAnimation {
        clips[move] ?? move.animation
    }
}
