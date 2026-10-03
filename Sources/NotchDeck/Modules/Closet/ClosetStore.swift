import Combine
import Foundation
import SwiftUI
import NotchKitCore
import NotchKit

/// The study pet's look and points, persisted as one `PetSave`, plus the
/// animated preview the Closet tab shows. `AppServices` owns it so the pet
/// in the notch and the coach can share the same pet.
///
/// With `NOTCHDECK_DEMO=1` it starts from `PetCloset.demo` and never writes,
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
    private var lastFocus: FocusTimer?
    private let saveURL: URL?
    /// Set when the save on disk could not be read: the closet then runs on
    /// a fresh pet but never overwrites the file, so nothing is lost.
    private let saveIsUnreadable: Bool

    init(edition: Edition = .current) {
        let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
        let url = isDemo ? nil : ClosetStore.saveURL(for: edition)
        var unreadable = false
        var closet = PetCloset.demo
        if !isDemo {
            do {
                let save = try url.flatMap { try PetSave.load(from: $0) }
                closet = PetCloset(save: save ?? PetSave(profile: .starter(.cat)))
            } catch {
                unreadable = true
                closet = PetCloset(save: PetSave(profile: .starter(.cat)))
            }
        }
        self.closet = closet
        saveURL = url
        saveIsUnreadable = unreadable
        preview = PetPlayer(profile: closet.profile)
        presence = PetPresence(profile: closet.profile, lastActive: .now)
    }

    /// Follows the shared focus timer, so the notch pet stays awake through
    /// sessions and dozes off a while after the last one, and finished
    /// sessions earn points (`PetCloset.credit`).
    func follow(focus: AnyPublisher<FocusTimer?, Never>) {
        focusSubscription = focus
            .removeDuplicates()
            .sink { [weak self] timer in
                MainActor.assumeIsolated { self?.focusChanged(timer) }
            }
    }

    private func focusChanged(_ timer: FocusTimer?) {
        let now = Date()
        presence.observe(timer, at: now)
        let old = lastFocus
        lastFocus = timer
        let before = closet.save
        let award = closet.credit(from: old, to: timer, at: now)
        if closet.save != before { persist() }
        guard let award else { return }
        preview.send(.celebrate)
        awards.send(award)
    }

    /// `~/Library/Application Support/<edition>/Pet/pet.json`.
    static func saveURL(for edition: Edition) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(edition.name)/Pet/pet.json")
    }

    var profile: PetProfile { closet.profile }

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

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? closet.save.write(to: saveURL)
    }
}
