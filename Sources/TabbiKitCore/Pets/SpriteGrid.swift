import Foundation

/// A breed-dependent region inside shared body art, written as a lowercase
/// letter in sprite grids. Body and head art is drawn once per body type;
/// each breed's `PetPattern` decides which palette role every zone becomes.
/// That is how a tuxedo gets white paws and a Siamese gets dark points from
/// the very same cat art.
public enum PetPatternZone: String, CaseIterable, Codable, Sendable {
    /// Lower face around nose and mouth.
    case muzzle
    /// Chest and front of the neck.
    case chest
    /// Paws and lower legs.
    case paws
    /// The last pixels of the tail.
    case tailTip
    /// Outer ears.
    case ears
    /// Mask around the eyes (Siamese points, beagle face).
    case mask
    /// Stripe marks (tabby "M", back stripes).
    case stripes
    /// First patch (calico orange, beagle saddle, French bulldog spot).
    case patchA
    /// Second patch (calico black).
    case patchB

    public var symbol: Character {
        switch self {
        case .muzzle: "m"
        case .chest: "c"
        case .paws: "p"
        case .tailTip: "t"
        case .ears: "e"
        case .mask: "f"
        case .stripes: "s"
        case .patchA: "a"
        case .patchB: "b"
        }
    }

    public init?(symbol: Character) {
        guard let zone = Self.allCases.first(where: { $0.symbol == symbol }) else { return nil }
        self = zone
    }

    /// What a zone looks like when a breed says nothing about it: plain fur,
    /// with a lighter muzzle and chest.
    public var defaultRole: PetPaletteRole {
        switch self {
        case .muzzle, .chest: .belly
        default: .furBase
        }
    }
}

/// One cell of a sprite grid.
public enum SpriteCell: Hashable, Sendable {
    /// Transparent; lower layers show through. Written `.` or space.
    case empty
    /// Clears whatever lower layers painted here (e.g. a cap hiding ear
    /// tips). Written `x`.
    case erase
    case role(PetPaletteRole)
    case zone(PetPatternZone)

    public init?(symbol: Character) {
        switch symbol {
        case ".", " ": self = .empty
        case "x": self = .erase
        default:
            if let role = PetPaletteRole(symbol: symbol) {
                self = .role(role)
            } else if let zone = PetPatternZone(symbol: symbol) {
                self = .zone(zone)
            } else {
                return nil
            }
        }
    }

    public var symbol: Character {
        switch self {
        case .empty: "."
        case .erase: "x"
        case .role(let role): role.symbol
        case .zone(let zone): zone.symbol
        }
    }
}

/// A rectangular text-drawn sprite layer.
///
/// Art is plain text, one row per line, so contributors can edit it in any
/// text editor and review it in a diff. The built-in art lives as arrays of
/// rows in the `pets.v1` JSON files (`PetArt`); tests build grids inline:
///
/// ```
/// let ear = try SpriteGrid("""
///     .OO.
///     OBBO
///     OPBO
///     """)
/// ```
///
/// Leading/trailing blank lines are ignored, and the common indentation of a
/// multi-line literal is already removed by Swift. Rows must all be the same
/// width so a typo can never silently shift the art.
public struct SpriteGrid: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [SpriteCell]

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case raggedRow(row: Int, expected: Int, found: Int)
        case unknownSymbol(Character, row: Int, column: Int)

        public var description: String {
            switch self {
            case .empty: "Sprite grid has no rows"
            case let .raggedRow(row, expected, found):
                "Row \(row) is \(found) wide; expected \(expected)"
            case let .unknownSymbol(symbol, row, column):
                "Unknown symbol '\(symbol)' at row \(row), column \(column)"
            }
        }
    }

    public init(width: Int, height: Int, fill: SpriteCell = .empty) {
        self.width = width
        self.height = height
        cells = Array(repeating: fill, count: width * height)
    }

    /// Parses a text grid. Row and column numbers in errors are 1-based.
    public init(_ text: String) throws {
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let first = rows.first, first.allSatisfy(\.isWhitespace) { rows.removeFirst() }
        while let last = rows.last, last.allSatisfy(\.isWhitespace) { rows.removeLast() }
        guard let first = rows.first else { throw ParseError.empty }
        let width = first.count
        var cells: [SpriteCell] = []
        cells.reserveCapacity(width * rows.count)
        for (rowIndex, row) in rows.enumerated() {
            guard row.count == width else {
                throw ParseError.raggedRow(row: rowIndex + 1, expected: width, found: row.count)
            }
            for (columnIndex, symbol) in row.enumerated() {
                guard let cell = SpriteCell(symbol: symbol) else {
                    throw ParseError.unknownSymbol(symbol, row: rowIndex + 1, column: columnIndex + 1)
                }
                cells.append(cell)
            }
        }
        self.width = width
        height = rows.count
        self.cells = cells
    }

    /// For built-in art that is covered by tests; crashes with the parse
    /// error so a broken literal is caught immediately in development.
    public init(art: String) {
        do {
            try self.init(art)
        } catch {
            preconditionFailure("Invalid sprite art: \(error)")
        }
    }

    public subscript(x: Int, y: Int) -> SpriteCell {
        get { cells[y * width + x] }
        set { cells[y * width + x] = newValue }
    }

    /// Left-right mirror, for facing the other way.
    public func mirrored() -> SpriteGrid {
        var copy = self
        for y in 0..<height {
            for x in 0..<width { copy[x, y] = self[width - 1 - x, y] }
        }
        return copy
    }

    /// The grid written back out as text, one row per line.
    public var text: String {
        (0..<height).map { y in String((0..<width).map { self[$0, y].symbol }) }.joined(separator: "\n")
    }
}
