import Foundation
import Testing
@testable import TabbiKitCore

/// Demo mode feeds the App Store screenshots and preview, which may show no
/// third-party trademarks or real songs (App Review Guideline 5.2.1).
struct DemoDataTests {
    private static let brands = ["UWorld", "First Aid", "M83", "Midnight City", "Hurry Up",
                                 "AnKing", "Sketchy", "Pathoma", "Boards and Beyond"]

    private var demoText: [String] {
        let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let today = PlannerDayKey(date: now)
        var text: [String] = []
        for kind in PlannerSampleDay.allCases {
            for viewed in [PlannerViewedDay.yesterday, .today, .tomorrow] {
                text += PlannerDay.sample(viewed, today: today, kind: kind).items.map(\.title)
                text += UpcomingEvent.samples(viewed, now: now, kind: kind).map(\.title)
            }
            text.append(DayReview.sample(on: today, kind: kind).summary ?? "")
        }
        text += DayPlanner.sampleProposal(now: now).map(\.title)
        let track = SpotifyPlayback.demo.track
        text += [track?.title, track?.artist, track?.album].compactMap { $0 }
        text += AnkiSummary.demo(now: now).decks.map(\.name)
        return text
    }

    @Test func demoDataNamesNoBrandsOrRealSongs() {
        for line in demoText {
            for brand in Self.brands {
                #expect(!line.contains(brand), "\"\(line)\" names \(brand)")
            }
        }
    }
}
