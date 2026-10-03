import SwiftUI
import NotchKitCore

/// The study pet in the closed notch's leading wing: alive while the user
/// studies or just did, curled up asleep once no session has run for a
/// while (`PetPresence.sleepAfter`).
///
/// Owns its own `PetPlayer`, kept for as long as the pet stays on screen,
/// so mood changes play the real fall-asleep and stretch-awake clips
/// instead of cutting between them.
struct NotchPetWing: View {
    let pet: TickerPet

    /// Points per sprite pixel: whole device pixels on 2x displays keep the
    /// art crisp, and the sitting pet (about 25 sprite pixels tall) fits the
    /// 32 pt notch.
    static let pixelSize: CGFloat = 1
    static var side: CGFloat { CGFloat(PetComposer.frameSize) * pixelSize }

    @StateObject private var player: PetPlayer

    init(pet: TickerPet) {
        self.pet = pet
        _player = StateObject(wrappedValue: PetPlayer(profile: pet.profile, asleep: pet.mood == .asleep))
    }

    var body: some View {
        PetView(player: player, pixelSize: Self.pixelSize)
            // The frame's paws sit on its bottom row and its sides are a few
            // pixels empty, so lift the pet off the notch's bottom edge and
            // line its fur up with the inset the trailing text keeps.
            .offset(x: -3, y: -3)
            .onChange(of: pet.profile) { _, profile in player.update(profile: profile) }
            .onChange(of: pet.mood == .asleep) { _, asleep in player.send(asleep ? .sleep : .wake) }
    }
}
