#if DEBUG
import SwiftUI
import TabbiKitCore

/// Debug builds only (long-press "CAM 1" on the home screen): the read as
/// data, so playtests can compare variants. Edits apply to the frozen frame
/// at once, the strike chances update live, and a simulation plays
/// scripted players through the real game loop.
struct TuningPanel: View {
    @Environment(PetCamStore.self) private var cam
    @Environment(StudyStore.self) private var study
    @Environment(\.dismiss) private var dismiss
    @State private var tuning = PetCamTuning.standard
    @State private var rates: [String: Double] = [:]
    @State private var simulating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Stare") { Text(verbatim: PetCamCaptions.name(of: cam.game.setup.stare)) }
                    LabeledContent("Exception") {
                        Text(verbatim: cam.game.setup.tell.map { "\($0.exception.rawValue) at \(PetCamCaptions.name(of: $0.spot))" }
                            ?? "none showing")
                    }
                    LabeledContent("Next strike") {
                        Text(verbatim: PetCamCaptions.name(of: cam.game.setup.strike))
                            .accessibilityIdentifier("debug.strike")
                    }
                    ForEach(PetCamSpot.allCases, id: \.self) { spot in
                        LabeledContent(PetCamCaptions.name(of: spot)) {
                            Text(verbatim: percent(cam.game.setup.strikeChances[spot] ?? 0)).monospacedDigit()
                        }
                    }
                } header: { Text(verbatim: "This frozen frame") }

                Section {
                    slider("Stare weight", value: $tuning.stareWeight, range: 0...PetCamTuning.maximumWeight)
                    slider("Other spot weight", value: $tuning.otherWeight, range: 0...PetCamTuning.maximumWeight)
                    Picker(selection: $tuning.exception) {
                        ForEach(PetCamTuning.Exception.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                    } label: { Text(verbatim: "Exception") }
                    slider("Exception chance", value: $tuning.exceptionChance, range: 0...1, step: 0.05)
                    slider("Exception weight", value: $tuning.exceptionWeight, range: 0...PetCamTuning.maximumWeight)
                    Button { tuning = .standard } label: { Text(verbatim: "Back to the default read") }
                } header: { Text(verbatim: "The read") } footer: {
                    Text(verbatim: summary)
                }

                Section {
                    ForEach(["follow", "random", "expert"], id: \.self) { player in
                        LabeledContent(label(player)) {
                            Text(verbatim: rates[player].map(percent) ?? "-").monospacedDigit()
                        }
                    }
                    Button { simulate() } label: {
                        Text(verbatim: simulating ? "Playing 2000 blocks..." : "Play 2000 blocks per player")
                    }
                    .disabled(simulating)
                } header: { Text(verbatim: "Scripted players") }

                Section {
                    Toggle(isOn: Binding(get: { cam.game.rules == .quickTest }, set: { cam.setQuickBlocks($0) })) {
                        Text(verbatim: "One-minute blocks arm the camera")
                    }
                    Button { study.useDemoPet() } label: { Text(verbatim: "Demo pet (Cozy Hoodie and Beanie)") }
                    if let last = cam.game.log.tapes.last {
                        Button {
                            dismiss()
                            cam.replay(last)
                        } label: { Text(verbatim: "Replay the last tape") }
                    }
                    Button(role: .destructive) { cam.resetGame() } label: { Text(verbatim: "New room and history") }
                } header: { Text(verbatim: "Testing") }
            }
            .navigationTitle(Text(verbatim: "Pet Cam tuning"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .tabbi) }
                }
            }
            .onAppear { tuning = cam.game.tuning }
            .onChange(of: tuning) { _, new in cam.setTuning(new) }
        }
    }

    private var summary: String {
        let plain = tuning.strikeChances(stare: .counter, exception: nil)
        let apart = tuning.strikeChances(stare: .counter, exception: .table)
        let together = tuning.strikeChances(stare: .counter, exception: .counter)
        return "No exception: \(percent(plain[.counter] ?? 0)) on the stare. Exception elsewhere: "
            + "\(percent(apart[.counter] ?? 0)) stare, \(percent(apart[.table] ?? 0)) exception. "
            + "Exception on the stare: \(percent(together[.counter] ?? 0))."
    }

    private func label(_ player: String) -> String {
        switch player {
        case "follow": "Always follows the stare"
        case "random": "Picks a random spot"
        default: "Reads the exception too"
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.5)
        -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) { Text(verbatim: String(format: "%.2f", value.wrappedValue)).monospacedDigit() }
            Slider(value: value, in: range, step: step) { Text(verbatim: title) }
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    private func simulate() {
        simulating = true
        let tuning = tuning
        Task.detached {
            let result = Simulation.rates(tuning: tuning)
            await MainActor.run {
                rates = result
                simulating = false
            }
        }
    }
}

/// Scripted players through the real game loop, as in `PetCamReadTests`.
private enum Simulation {
    static func rates(tuning: PetCamTuning, blocks: Int = 2000) -> [String: Double] {
        var result: [String: Double] = [:]
        let pet = PetProfile(name: "", breed: .britishShorthair)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for player in ["follow", "random", "expert"] {
            var game = PetCamGame(seed: 0x51A7, tuning: tuning, at: start)
            var roll = PetCamRandom(seed: 0x51A7, stream: player)
            var caught = 0
            for index in 0..<blocks {
                let at = start.addingTimeInterval(Double(index) * 2400)
                let pick: PetCamSpot? = switch player {
                case "follow": nil
                case "random": PetCamSpot.allCases[Int(roll.next() % 3)]
                default: game.setup.tell?.spot ?? game.setup.stare
                }
                game.start(id: "s\(index)", pick: pick, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: at)
                if game.finish(endedAt: at.addingTimeInterval(1500), worked: 1500)?.outcome == .caught { caught += 1 }
            }
            result[player] = Double(caught) / Double(blocks)
        }
        return result
    }
}
#endif
