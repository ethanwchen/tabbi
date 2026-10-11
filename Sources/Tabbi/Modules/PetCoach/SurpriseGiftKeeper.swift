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
/// Hook for whatever shows the pet away and back (an adventure while the
/// user focuses): follow `delivered`, or read `latest`, to have the pet
/// come back carrying the gift. The gift is already applied by then.
@MainActor
final class SurpriseGiftKeeper: ObservableObject {
    @Published private(set) var state: SurpriseGiftState
    /// Each gift as the cat hands it over.
    let delivered = PassthroughSubject<SurpriseGiftDelivery, Never>()
    /// The last gift handed over since launch.
    private(set) var latest: SurpriseGiftDelivery?

    private let closet: ClosetStore
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
    }

    /// `~/Library/Application Support/<edition>/Pet/gifts.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("gifts.json", in: "Pet")
    }

    /// The rare furs found so far, which the Closet's Look offers.
    var rareFurs: [RareFur] { state.rareFurs }

    /// Rolls for the focus session behind `award`, saves the outcome,
    /// applies a gift (bonus points go to the pet's balance; a rare fur
    /// joins the Closet's Look) and publishes it. Nil when there is none.
    func roll(after award: PetStudyAward, at date: Date = .now) -> SurpriseGift? {
        guard saveURL != nil, !saveIsUnreadable else { return nil }
        var random = SystemRandomNumberGenerator()
        let gift = state.roll(after: award, at: date, using: &random)
        persist()
        guard let gift else { return nil }
        if case .bonusPoints(let points) = gift { closet.receiveGift(points: points) }
        let delivery = SurpriseGiftDelivery(gift: gift, date: date)
        latest = delivery
        delivered.send(delivery)
        return gift
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
