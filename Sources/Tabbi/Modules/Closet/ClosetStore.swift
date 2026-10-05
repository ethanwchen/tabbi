import Combine
import Foundation
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The study pet's look and points, persisted as one `PetSave`, plus the
/// animated preview the Closet tab shows. It is the only reader and writer
/// of the pet's save: modules share it as `context.studyPet` and follow
/// `profiles`, so the Closet, the coach, Study's corner pet and Party all
/// show the same pet.
///
/// With `TABBI_DEMO=1` it starts from `PetCloset.demo` and never writes,
/// so demos and snapshots can't touch a real save.
@MainActor
final class ClosetStore: ObservableObject {
    @Published private(set) var closet: PetCloset
    /// An item the pointer rests on, shown on the big preview ("try it on")
    /// without changing the save.
    @Published private(set) var tryingOn: PetItem?
    /// The Closet tab's open section, kept while the notch closes.
    @Published var section: ClosetSection = .wardrobe
    /// The large preview in the Closet tab.
    let preview: PetPlayer
    /// The saved pet plus when a study session last ran, which the closed
    /// notch uses to show the pet awake or asleep.
    @Published private(set) var presence: PetPresence

    /// Points earned from study sessions, as they are credited, so the
    /// coach can send the pet out to celebrate.
    let awards = PassthroughSubject<PetStudyAward, Never>()

    private var focusSubscription: AnyCancellable?
    private var kitSubscription: AnyCancellable?
    private var lastFocus: ProvidedFocus?
    private let saveURL: URL?
    /// Set when the save on disk could not be read: the closet then runs on
    /// a fresh pet but never overwrites the file, so nothing is lost.
    private let saveIsUnreadable: Bool

    /// False until the pet is saved (a rename, a new outfit, the first
    /// points). Until then the pet is the kit's starter and follows kit
    /// switches, so the kit picked on first run decides the first pet.
    private var hasSave: Bool

    /// - Parameter starter: the pet to start someone with no saved pet on,
    ///   usually the kit's (`PetProfile.starter(kit:)`).
    init(storage: EditionStorage, runMode: RunMode, starter: PetProfile = .starter(.cat)) {
        let isDemo = runMode.isDemo
        let url = isDemo ? nil : ClosetStore.saveURL(in: storage)
        var unreadable = false
        var saved = true
        var closet = PetCloset.demo
        if !isDemo {
            do {
                let save = try url.flatMap { try PetSave.load(from: $0) }
                saved = save != nil
                closet = PetCloset(save: save ?? PetSave(profile: starter))
            } catch {
                unreadable = true
                closet = PetCloset(save: PetSave(profile: starter))
            }
        }
        self.closet = closet
        saveURL = url
        saveIsUnreadable = unreadable
        hasSave = saved
        preview = PetPlayer(profile: closet.profile)
        presence = PetPresence(profile: closet.profile, lastActive: .now)
    }

    /// Follows the shared focus timer, so the notch pet stays awake through
    /// sessions and dozes off a while after the last one, and finished
    /// sessions earn points (`PetCloset.credit`).
    func follow(focus: AnyPublisher<ProvidedFocus?, Never>) {
        focusSubscription = focus
            .removeDuplicates()
            .sink { [weak self] timer in
                MainActor.assumeIsolated { self?.focusChanged(timer) }
            }
    }

    private func focusChanged(_ timer: ProvidedFocus?) {
        let now = Date()
        presence.observe(timer, at: now)
        let old = lastFocus
        lastFocus = timer
        let before = closet.save
        let award = closet.credit(from: old, to: timer, at: now)
        // A starter pet that only saw an idle clock stays unsaved, so it
        // keeps following kit switches (the first-run kit pick comes after
        // the first timer the pet sees). Once a clock runs, the pet and its
        // baseline are saved, so a session that ends while Tabbi is closed
        // is still paid on the next launch.
        if hasSave ? closet.save != before : award != nil || timer?.isActive == true { persist() }
        guard let award else { return }
        preview.send(.celebrate)
        awards.send(award)
    }

    /// `~/Library/Application Support/<edition>/Pet/pet.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("pet.json", in: "Pet")
    }

    var profile: PetProfile { closet.profile }

    /// The pet's look now and on every change, for modules that show it.
    var profiles: AnyPublisher<PetProfile, Never> {
        $closet.map(\.profile).removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: Editing

    /// Wears, takes off, or buys `item`. A purchase makes the pet celebrate.
    @discardableResult
    func tap(_ item: PetItem) -> PetClosetTapResult {
        let result = edit { $0.tap(item) }
        if result == .boughtAndWore { preview.send(.celebrate) }
        return result
    }

    func rename(_ name: String) { edit { $0.rename(name) } }
    func setSpecies(_ species: PetSpecies) { edit { $0.setSpecies(species) } }
    func cycleBreed(by offset: Int) { edit { $0.cycleBreed(by: offset) } }
    func tintFur(_ color: PetColor?) { edit { $0.tintFur(color) } }

    /// Starts or ends a hover preview of `item` on the big pet.
    func tryOn(_ item: PetItem?) {
        guard tryingOn != item else { return }
        tryingOn = item
        refreshPreview()
    }

    private func edit<Result>(_ change: (inout PetCloset) -> Result) -> Result {
        let result = change(&closet)
        if presence.profile != closet.profile { presence.profile = closet.profile }
        refreshPreview()
        persist()
        return result
    }

    private func refreshPreview() {
        let shown = tryingOn.map { PetCloset.wearing($0, on: closet.profile) } ?? closet.profile
        preview.update(profile: shown)
    }

    /// Until the pet is saved, it is the active kit's starter pet.
    func follow(kits: AnyPublisher<SettingsStore.KitApplication, Never>) {
        kitSubscription = kits.sink { [weak self] in self?.useStarter(.starter(kit: $0.kit.defaults)) }
    }

    /// Swaps a pet that was never saved for a new kit's starter.
    func useStarter(_ starter: PetProfile) {
        guard !hasSave, !saveIsUnreadable, closet.profile != starter else { return }
        var save = PetSave(profile: starter)
        save.creditedFocusCount = closet.save.creditedFocusCount
        save.creditedFocusSource = closet.save.creditedFocusSource
        closet = PetCloset(save: save)
        presence.profile = starter
        refreshPreview()
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        if (try? closet.save.write(to: saveURL)) != nil { hasSave = true }
    }
}
