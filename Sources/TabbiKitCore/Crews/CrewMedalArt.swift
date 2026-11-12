import CoreGraphics
import Foundation

/// The small pixel medal of the Hall of Fame's tallies and a crew's history:
/// a ribbon in ink over an outlined disc with one highlight and one shade, in
/// the crest's rank metals (the Crews UI spec). 9 by 10 sprite pixels, drawn
/// at whole-pixel scales like every Tabbi sprite; the Windows port draws the
/// same grid (`shared/fixtures/crews/crews.json` pins it).
public enum CrewMedalArt {
    public static let width = 9
    public static let height = 10

    public static let grid = [
        "...OO....", "..OQqO...", "..OQqO...", ".OOOOOO..", "OMHHMMMO.",
        "OMHMMMmO.", "OMMMMMmO.", "OMMMmmmO.", ".OMmmmO..", "..OOOO...",
    ]

    /// The colors of every character for a metal.
    public static func palette(_ metal: CrewLaurel) -> [Character: String] {
        var palette: [Character: String] = ["O": "#2A1A14", "Q": "#3F4A78", "q": "#2C3456"]
        switch metal {
        case .gold: palette.merge(["M": "#F2C14E", "H": "#FFE9A6", "m": "#C98A2A"]) { $1 }
        case .silver: palette.merge(["M": "#C7D1DE", "H": "#FFFFFF", "m": "#8E9BAB"]) { $1 }
        case .bronze: palette.merge(["M": "#D9945C", "H": "#F3C1A0", "m": "#A8683A"]) { $1 }
        }
        return palette
    }

    /// The medal's pixels as colors, row-major, nil for clear.
    public static func colors(_ metal: CrewLaurel) -> [PetColor?] {
        let palette = palette(metal)
        return grid.flatMap { row in row.map { $0 == "." ? nil : palette[$0].flatMap(PetColor.init(hex:)) } }
    }

    public static func image(_ metal: CrewLaurel, scale: Int) -> CGImage? {
        PixelImage.render(colors(metal), width: width, height: height, scale: max(1, scale))
    }
}
