import SwiftUI

/// What the session is doing, as the one color the screen and the Live
/// Activity give it. Color here is information: amber is focus (the Study
/// tab's accent on the Mac), teal is rest, and a quiet neutral is idle. The
/// state is always written out too, never shown by color alone.
enum StudyTone: Equatable {
    case idle
    case focus
    case rest

    init(isBreak: Bool, isIdle: Bool) {
        self = isIdle ? .idle : isBreak ? .rest : .focus
    }

    /// The tone's hue, a shade deeper in light mode so text in it keeps
    /// its contrast on the pale canvas.
    func hue(_ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .idle: return dark ? Color(red: 0.92, green: 0.80, blue: 0.62) : Color(red: 0.55, green: 0.40, blue: 0.24)
        case .focus: return dark ? Color(red: 1.00, green: 0.62, blue: 0.26) : Color(red: 0.78, green: 0.38, blue: 0.05)
        case .rest: return dark ? Color(red: 0.42, green: 0.84, blue: 0.78) : Color(red: 0.07, green: 0.50, blue: 0.46)
        }
    }

    /// The tinted neutral the scene is painted on: warm paper in light
    /// mode, a near-black room in dark mode.
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.063, green: 0.059, blue: 0.071) : Color(red: 0.969, green: 0.953, blue: 0.925)
    }
}
