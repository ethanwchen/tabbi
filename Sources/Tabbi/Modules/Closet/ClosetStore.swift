import AppKit
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
    @Published private(set) var closet: PetCloset {
        // Points and unlocks change the closed notch's near-unlock hint.
        didSet {
            let unlock = UnlockProgress(closet: closet)
            if presence.nextUnlock != unlock { presence.nextUnlock = unlock }
        }
    }
    /// An item the pointer rests on, shown on the big preview ("try it on")
    /// without changing the save.
    @Published private(set) var tryingOn: PetItem?
    /// The Closet tab's open section, kept while the notch closes.
    @Published var section: ClosetSection = .activity
    /// The large preview in the Closet tab.
    let preview: PetPlayer
    /// A snapshot run draws the study chart already filled in, since a
    /// still image can't play its entrance.
    let isSnapshot: Bool
    /// The saved pet plus when a study session last ran, which the closed
    /// notch uses to show the pet awake or asleep.
    @Published private(set) var presence: PetPresence

    /// When the user last changed the pet's look on this Mac, so Sign in
    /// with Apple sync can tell the newest look across Macs. Nil until an
    /// edit since launch.
    private(set) var lookChangedAt: Date?

    /// Progress toward the limited edition milestones, from the whole
    /// activity log (`follow(activity:history:)`).
    @Published private(set) var milestones: PetMilestoneProgress {
        didSet { bondMayHaveGrown() }
    }

    /// Focus logged during each seasonal event run, which earns that
    /// event's limited items (`follow(activity:history:)`).
    @Published private(set) var seasons = SeasonalEventTally()

    /// The moment the Closet reads seasonal events at: now, or in a demo a
    /// pinned moment inside the featured event (`SeasonalEventDemo`), so a
    /// demo always shows an event going on.
    var seasonNow: Date { pinnedSeasonMoment ?? .now }
    private let pinnedSeasonMoment: Date?

    /// Points earned from study sessions, as they are credited, so the
    /// coach can send the pet out to celebrate.
    let awards = PassthroughSubject<PetStudyAward, Never>()

    /// The pet's adventure journal ("Mochi explored the bookshelf"), a line
    /// for each focus block it went off exploring in (`PetAdventure`).
    @Published private(set) var journal: PetJournal

    /// Gift integration point: one value each time the pet comes back from
    /// an adventure as a focus block ends, with the journal line it brought
    /// back. The end-of-session moment can follow it to hand over a gift
    /// the pet found; the Closet itself only writes the journal.
    let adventureReturns = PassthroughSubject<PetJournal.Entry, Never>()

    /// Whether Reduce Motion is on, which keeps the pet home (and so out of
    /// the journal). Read when a block ends; tests replace it.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var focusSubscription: AnyCancellable?
    private var activitySubscription: AnyCancellable?
    private var kitSubscription: AnyCancellable?
    private var notchSubscription: AnyCancellable?
    private var lastFocus: ProvidedFocus?
    private let saveURL: URL?
    private let journalURL: URL?
    /// Set when the journal on disk could not be read, so it is never
    /// overwritten.
    private let journalIsUnreadable: Bool
    /// Plays a sparkle milestone over the panel when an item is bought or
    /// study points make a new one affordable (a level up).
    private let celebrations: CelebrationCenter?
    /// Set when the save on disk could not be read: the closet then runs on
    /// a fresh pet but never overwrites the file, so nothing is lost.
    private let saveIsUnreadable: Bool

    /// False until the pet is saved (a rename, a new outfit, the first
    /// points). Until then the pet is the kit's starter and follows kit
    /// switches, so the kit picked on first run decides the first pet.
    private var hasSave: Bool

    /// - Parameters:
    ///   - starter: the pet to start someone with no saved pet on, usually
    ///     the kit's (`PetProfile.starter(kit:)`).
    ///   - celebrations: plays a sparkle milestone on a purchase or a level up;
    ///     nil in tests.
    init(storage: EditionStorage, runMode: RunMode, starter: PetProfile = .starter(.cat),
         celebrations: CelebrationCenter? = nil) {
        let isDemo = runMode.isDemo
        isSnapshot = runMode.isSnapshot
        // A snapshot run neither reads nor writes the save on this Mac, so
        // it shows a fresh install's starter pet wherever it runs.
        let url = isDemo || runMode.isSnapshot ? nil : ClosetStore.saveURL(in: storage)
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
        let journalURL = url.map { _ in ClosetStore.journalURL(in: storage) }
        var journalUnreadable = false
        var journal = isDemo ? PetJournal.demo(now: .now) : PetJournal(seed: .random(in: .min ... .max))
        if let journalURL {
            do {
                if let saved = try PetJournal.load(from: journalURL) { journal = saved }
            } catch {
                journalUnreadable = true
            }
        }
        self.journal = journal
        self.journalURL = journalURL
        journalIsUnreadable = journalUnreadable
        self.celebrations = celebrations
        saveIsUnreadable = unreadable
        hasSave = saved
        let progress = isDemo ? PetMilestoneProgress.demo(today: .now) : PetMilestoneProgress()
        milestones = progress
        let demoSeason = isDemo ? SeasonalEventDemo(today: .now) : nil
        pinnedSeasonMoment = demoSeason?.moment
        if let demoSeason { seasons = demoSeason.tally }
        var grown = closet.profile
        grown.bondLook = PetBond(progress: progress).look
        preview = PetPlayer(profile: grown)
        // A snapshot renders the same pet whatever the hour, so only real
        // and demo runs doze at night.
        presence = PetPresence(profile: grown, lastActive: .now, nextUnlock: UnlockProgress(closet: closet),
                               night: runMode.isSnapshot ? nil : .standard)
    }

    /// Follows the notch opening and closing (one value each time), which
    /// wakes a pet dozing late at night (`PetPresence.wake(at:)`). Closing
    /// counts too: the dozing pet only shows on the closed notch, so a wake
    /// spell that started when the notch opened could run out unseen.
    func follow(notchToggled: AnyPublisher<Void, Never>) {
        notchSubscription = notchToggled
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.presence.wake(at: .now) }
            }
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

    /// Follows new activity records, so focus time cut short (Stop, Skip,
    /// or the Mac sleeping or Tabbi quitting mid-session) earns points
    /// (`PetCloset.credit(_:)`), once per record, and study milestones and
    /// focus during seasonal events unlock their limited edition items.
    /// `history` is the log so far, which counts toward both without paying
    /// points again; a goal it already reached unlocks quietly.
    func follow(activity: AnyPublisher<ActivityRecord, Never>, history: [ActivityRecord] = []) {
        for record in history {
            milestones.add(record)
            seasons.add(record)
        }
        if !unlockLimited().isEmpty { persist() }
        activitySubscription = activity
            .sink { [weak self] record in
                MainActor.assumeIsolated { self?.recorded(record) }
            }
    }

    private func recorded(_ record: ActivityRecord) {
        milestones.add(record)
        seasons.add(record)
        let award = closet.credit(record)
        let unlocked = unlockLimited()
        guard award != nil || !unlocked.isEmpty else { return }
        persist()
        if let award { celebrate(award) }
        if !unlocked.isEmpty { celebrateLimited() }
    }

    /// Grants the limited items the milestones and seasonal events have
    /// earned and returns the new ones.
    private func unlockLimited() -> [PetItem] {
        closet.unlockMilestones(milestones) + closet.unlockSeasonal(seasons)
    }

    /// A limited edition item just became the user's: the pet celebrates
    /// and the panel sparkles, like a purchase.
    private func celebrateLimited() {
        preview.send(.celebrate)
        celebrateUnlock(hasOwnSound: false)
    }

    /// Takes the limited edition items the Tabbi server granted (event items
    /// such as the launch week cap, by item id) and celebrates new ones.
    /// Returns the items that are new.
    @discardableResult
    func applyGrants(_ ids: some Sequence<String>) -> [PetItem] {
        let granted = closet.applyGrants(ids)
        guard !granted.isEmpty else { return [] }
        persist()
        celebrateLimited()
        return granted
    }

    private func focusChanged(_ timer: ProvidedFocus?) {
        let now = Date()
        presence.observe(timer, at: now)
        let old = lastFocus
        lastFocus = timer
        if let adventure = PetAdventure.finished(from: old, to: timer, at: now, reduceMotion: reduceMotion()) {
            adventureEnded(adventure)
        }
        let before = closet.save
        let award = closet.credit(from: old, to: timer, at: now)
        // A starter pet that only saw an idle clock stays unsaved, so it
        // keeps following kit switches (the first-run kit pick comes after
        // the first timer the pet sees). Once a clock runs, the pet and its
        // baseline are saved, so a session that ends while Tabbi is closed
        // is still paid on the next launch.
        if hasSave ? closet.save != before : award != nil || timer?.isActive == true { persist() }
        guard let award else { return }
        celebrate(award)
    }

    /// The pet is back from its adventure: a line goes into the journal and
    /// out to `adventureReturns`.
    private func adventureEnded(_ adventure: PetAdventure) {
        let entry = journal.record(at: adventure.endsAt)
        if let journalURL, !journalIsUnreadable { try? journal.write(to: journalURL) }
        adventureReturns.send(entry)
    }

    /// The newest journal line with the pet's name ("Mochi explored the
    /// bookshelf"), or nil before its first adventure.
    var latestAdventure: String? {
        journal.latest?.text(petName: profile.name)
    }

    private func celebrate(_ award: PetStudyAward) {
        preview.send(.celebrate)
        if award.isLevelUp { celebrateUnlock(hasOwnSound: award.completedSessions > 0) }
        awards.send(award)
    }

    /// Pays a Party shared session that ran to its end with the user in it
    /// and makes the pet celebrate. Party shows the award in its own
    /// celebration, so the coach is not told. Nil when nothing was earned.
    @discardableResult
    func credit(_ session: PartySessionCompletion) -> PetStudyAward? {
        guard let award = closet.credit(session) else { return nil }
        persist()
        preview.send(.celebrate)
        return award
    }

    /// Credits a surprise gift's bonus points (`SurpriseGiftKeeper`).
    func receiveGift(points: Int) {
        closet.receiveGift(points: points)
        persist()
    }

    /// `~/Library/Application Support/<edition>/Pet/pet.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("pet.json", in: "Pet")
    }

    /// `~/Library/Application Support/<edition>/Pet/journal.json`, beside
    /// the save but its own file, so it never syncs.
    static func journalURL(in storage: EditionStorage) -> URL {
        storage.file("journal.json", in: "Pet")
    }

    /// The pet as shown everywhere: the saved look plus what it has grown
    /// into with the bond (`PetBondLook`), which is never saved.
    var profile: PetProfile { grown(closet.profile) }

    private func grown(_ profile: PetProfile) -> PetProfile {
        var copy = profile
        copy.bondLook = bond.look
        return copy
    }

    /// Puts on a collar or sparkle the bond just unlocked, on the Closet
    /// preview and the closed notch's pet.
    private func bondMayHaveGrown() {
        guard presence.profile.bondLook != bond.look else { return }
        presence.profile = profile
        refreshPreview()
    }

    /// How close the pet and the user have grown (`PetBond`), from the same
    /// focused minutes and study days as the milestones, so it follows new
    /// study without tracking anything of its own.
    var bond: PetBond { PetBond(progress: milestones) }

    /// The pet's look now and on every change, for modules that show it.
    var profiles: AnyPublisher<PetProfile, Never> {
        $closet.combineLatest($milestones)
            .map { closet, milestones in
                var profile = closet.profile
                profile.bondLook = PetBond(progress: milestones).look
                return profile
            }
            .removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: Streak

    /// The study streak today, with its freezes (`StudyStreak`). Computed on
    /// read, so it follows new study, purchases and a new day without a
    /// timer of its own.
    var streak: StudyStreak { closet.streak(milestones, today: .now) }

    /// Buys an extra streak freeze with points and saves it. The button
    /// that calls this is disabled when the purchase can't go through.
    @discardableResult
    func buyStreakFreeze() -> Bool {
        do {
            try closet.buyStreakFreeze(milestones, at: .now)
        } catch {
            return false
        }
        persist()
        preview.send(.celebrate)
        return true
    }

    // MARK: Editing

    /// Wears, takes off, or buys `item`. A purchase makes the pet celebrate
    /// and sparkles over the panel.
    @discardableResult
    func tap(_ item: PetItem) -> PetClosetTapResult {
        let result = edit { $0.tap(item) }
        if result == .boughtAndWore {
            preview.send(.celebrate)
            celebrateUnlock(hasOwnSound: false)
        }
        return result
    }

    private func celebrateUnlock(hasOwnSound: Bool) {
        celebrations?.celebrate(.milestone, style: .sparkles, accent: ClosetModule.descriptor.accentColor,
                                from: ClosetModule.descriptor.id, hasOwnSound: hasOwnSound)
    }

    func rename(_ name: String) { edit { $0.rename(name) } }
    func setSpecies(_ species: PetSpecies) { edit { $0.setSpecies(species) } }
    func cycleBreed(by offset: Int) { edit { $0.cycleBreed(by: offset) } }
    func setBreed(_ breed: PetBreed) { edit { $0.setBreed(breed) } }
    func tintFur(_ color: PetColor?) { edit { $0.tintFur(color) } }

    /// Starts or ends a hover preview of `item` on the big pet.
    func tryOn(_ item: PetItem?) {
        guard tryingOn != item else { return }
        tryingOn = item
        refreshPreview()
    }

    private func edit<Result>(_ change: (inout PetCloset) -> Result) -> Result {
        let before = closet.profile
        let result = change(&closet)
        if closet.profile != before { lookChangedAt = .now }
        if presence.profile != profile { presence.profile = profile }
        refreshPreview()
        persist()
        return result
    }

    private func refreshPreview() {
        let shown = tryingOn.map { PetCloset.wearing($0, on: profile) } ?? profile
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
        presence.profile = profile
        refreshPreview()
    }

    /// The save on every change, for Sign in with Apple sync.
    var saves: AnyPublisher<PetSave, Never> {
        $closet.map(\.save).removeDuplicates().eraseToAnyPublisher()
    }

    /// Takes on the save a sync merged (the account's look, points and
    /// unlocks) and keeps it, like any edit.
    func adoptSynced(_ save: PetSave) {
        guard save != closet.save else { return }
        closet = PetCloset(save: save)
        if presence.profile != profile { presence.profile = profile }
        refreshPreview()
        persist()
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        if (try? closet.save.write(to: saveURL)) != nil { hasSave = true }
    }
}
