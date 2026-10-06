import SwiftUI

extension View {
    /// Fades the content out over `length` at one edge, so a list cut off
    /// by its frame reads as "more this way" instead of a hard clip. Pair
    /// it with a matching content margin so the last row can scroll clear.
    public func edgeFade(_ edge: VerticalEdge, length: CGFloat = Theme.Spacing.m) -> some View {
        mask {
            VStack(spacing: 0) {
                if edge == .top {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: length)
                }
                Color.black
                if edge == .bottom {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: length)
                }
            }
        }
    }
}
