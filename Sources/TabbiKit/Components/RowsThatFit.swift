import SwiftUI

/// A short top-down list that shows as many of its leading rows as fit the
/// height it's offered, so a card designed for the Regular panel drops its
/// last rows on a shorter one (Compact) instead of being clipped at the
/// panel's edges. With room for every row it is a plain `VStack`.
public struct RowsThatFit<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    let spacing: CGFloat
    let row: (Data.Element) -> Row

    public init(_ data: Data, spacing: CGFloat = 0, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.spacing = spacing
        self.row = row
    }

    public var body: some View {
        // ViewThatFits picks the first count whose rows fit; the last one
        // (a single row) shows even when nothing fits.
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: data.count, through: 1, by: -1)), id: \.self) { count in
                VStack(spacing: spacing) {
                    ForEach(data.prefix(count)) { row($0) }
                }
            }
        }
    }
}
