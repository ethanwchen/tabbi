import Combine
import Foundation
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Surprise gifts: now and then a finished focus session brings a small
/// gift from the cat (`SurpriseGiftState` decides when and what). The coach
/// rolls once per award it celebrates and names the gift in its bubble.
///
/// Gifts are earned only: nothing is sold or spent to roll. The state lives
/// in `<edition>/Pet/gifts.json` and is written before the gift is handed
/// over, so a restart can never roll the same session twice. Demo and
/// snapshot runs never roll or write; a demo starts with two rare furs found
/// so the Closet shows them, and the gift moments are coach snapshots.
///
/// The pet's adventure is wired in here: the keeper follows the Closet's
/// `adventureReturns`, and a gift rolled for the session the pet just came
/// home from is what it carried back. Its delivery names that adventure,
/// the coach's bubble says "Found: ...", and the journal line keeps the
/// gift. Anything else can follow `delivered`, or read `latest`; the gift
/// is already applied by then.
@MainActor
final class SurpriseGiftKeeper: ObservableObject {
    @Published private(set) var state: SurpriseGiftState
    /// Each gift as the cat hands it over.
    let delivered = PassthroughSubject<SurpriseGiftDelivery, Never>()
    /// The last gift handed over since launch.
    private(set) var latest: SurpriseGiftDelivery?

    /// How soon after the pet comes home a gift still counts as brought
    /// back: the coach rolls on the next turn of the main loop, so this
    /// only has to outlast a busy moment, never another session.
    static let adventureWindow: TimeInterval = 60

    private let closet: ClosetStore
    /// The adventure the pet just came home from, and when, until the
    /// session's roll takes it.
    private var adventureReturn: (entry: PetJournal.Entry, at: Date)?
    private var adventureSubscription: AnyCancellable?
    private let saveURL: URL?
    /// Set when the file on disk could not be read: no gifts then, since a
    /// fresh state would forget the caps and could be farmed.
    private let saveIsUnreadable: Bool

    init(storage: EditionStorage, runMode: RunMode, closet: ClosetStore) {
        self.closet = closet
        let url = runMode.isDemo || runMode.isSnapshot ? nil : Self.saveURL(in: storage)
        var state = runMode.isDemo ? SurpriseGiftState.demo : SurpriseGiftState()
        var unreadable = false
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do {
                state = try SurpriseGiftState.decode(Data(contentsOf: url))
            } catch {
                unreadable = true
            }
        }
        self.state = state
        saveURL = url
        saveIsUnreadable = unreadable
        adventureSubscription = closet.adventureReturns.sink { [weak self] entry in
            MainActor.assumeIsolated { self?.adventureReturn = (entry, Date()) }
        }
    }

    /// `~/Library/Application Support/<edition>/Pet/gifts.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("gifts.json", in: "Pet")
    }

    /// The rare furs found so far, which the Closet's Look offers.
    var rareFurs: [RareFur] { state.rareFurs }

    /// Rolls for the focus session behind `award`, saves the outcome,
    /// applies a gift (bonus points go to the pet's balance; a rare fur
    /// joins the Closet's Look) and publishes it. When the pet just came
    /// home from an adventure, the gift is what it brought back and goes on
    /// that journal line. Nil when there is none.
    func roll(after award: PetStudyAward, at date: Date = .now) -> SurpriseGiftDelivery? {
        let adventure = takeAdventureReturn(at: date)
        guard saveURL != nil, !saveIsUnreadable else { return nil }
        var random = SystemRandomNumberGenerator()
        let gift = state.roll(after: award, at: date, using: &random)
        persist()
        guard let gift else { return nil }
        if case .bonusPoints(let points) = gift { closet.receiveGift(points: points) }
        let delivery = SurpriseGiftDelivery(gift: gift, date: date,
                                            adventure: adventure.flatMap { closet.recordGift(gift, broughtBackFrom: $0) })
        latest = delivery
        delivered.send(delivery)
        return delivery
    }

    /// The adventure the pet came home from within `adventureWindow` of
    /// `date`, if any. Each one is taken once, by the roll right after it.
    private func takeAdventureReturn(at date: Date) -> PetJournal.Entry? {
        defer { adventureReturn = nil }
        guard let adventureReturn, abs(date.timeIntervalSince(adventureReturn.at)) <= Self.adventureWindow else {
            return nil
        }
        return adventureReturn.entry
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? state.encoded().write(to: saveURL, options: .atomic)
    }
}

extension ModuleContext {
    /// The one surprise gift keeper, beside the pet it gives to. Follow its
    /// `delivered` to show the pet coming back with a gift.
    var surpriseGifts: SurpriseGiftKeeper {
        shared.resolve { SurpriseGiftKeeper(storage: storage, runMode: runMode, closet: studyPet) }
    }
}

/// The rare furs found, for the Closet's Look (empty until one is found).
struct RareFursKey: EnvironmentKey {
    static let defaultValue: [RareFur] = []
}

extension EnvironmentValues {
    var rareFurs: [RareFur] {
        get { self[RareFursKey.self] }
        set { self[RareFursKey.self] = newValue }
    }
}

/// Hands the found rare furs to the views below, following new finds.
struct RareFursProvider<Content: View>: View {
    @ObservedObject var gifts: SurpriseGiftKeeper
    let content: Content

    var body: some View {
        content.environment(\.rareFurs, gifts.rareFurs)
    }
}
