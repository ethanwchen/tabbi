import SwiftUI
import NotchKitCore

/// The Study tab: a study timer with research-backed methods. Shows a
/// preview until the timer lands.
struct StudyPanel: View {
    var body: some View {
        ModulePreview(
            module: .study,
            pitch: "A study timer built around the method that suits you.",
            features: [
                .init(symbol: "timer", title: "Study methods",
                      detail: "Pomodoro, 52/17, Flowtime, question blocks"),
                .init(symbol: "cup.and.saucer.fill", title: "Breaks that fit",
                      detail: "Long breaks and Flowtime-sized rests"),
                .init(symbol: "waveform", title: "Focus sounds",
                      detail: "Brown noise, rain and café mixes"),
            ]
        )
    }
}
