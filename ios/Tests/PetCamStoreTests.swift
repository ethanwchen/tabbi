import AVFoundation
import Foundation
import Testing
import TabbiKitCore
@testable import TabbiPhone

/// The Pet Cam on the iPhone: the camera arms with the study session's
/// own start, resolves when that block's focus ends (in the app, or after a
/// relaunch), saves its game, words the end notification and the Live
/// Activity, keeps the tape's secret until it is watched, and exports a
/// tape as a vertical video with its own sound.
@Suite @MainActor struct PetCamStoreTests {
    nonisolated static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// A study store and a camera sharing a fresh folder.
    @MainActor struct Rig {
        let folder: URL
        let cam: PetCamStore
        let study: StudyStore

        init(folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
             at now: Date = PetCamStoreTests.t0, seed: UInt64 = 0x51DE) {
            self.folder = folder
            cam = PetCamStore(persistence: PetCamPersistence(url: folder.appendingPathComponent("petcam.json")), now: now,
                              seed: seed)
            study = StudyStore(persistence: StudyPersistence(folder: folder), live: false, now: now, observer: cam)
        }

        /// The Timer at `minutes`, ready to start.
        func timer(_ minutes: Int, at now: Date = PetCamStoreTests.t0) {
            study.choose(.timer, at: now)
            study.setTimer(StudyTimerLength(minutes: minutes), at: now)
        }
    }

    @Test func aLongEnoughBlockArmsTheCameraWithThePickAndTheDodge() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        rig.cam.pick = .shelf
        rig.cam.dodge = "my tax return"
        rig.cam.start(study: rig.study, now: Self.t0)
        #expect(rig.study.session.isRunning)
        let block = try #require(rig.cam.game.active)
        #expect(block.camera == .shelf)
        #expect(block.picked)
        #expect(block.dodge == "my tax return")
        #expect(block.plannedLength == 600)
        #expect(rig.cam.isFilming)
        #expect(rig.cam.pick == nil, "the tap is used up")
        #expect(rig.cam.dodge.isEmpty)
    }

    @Test func aShortBlockRunsWithoutTheCamera() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(3)
        rig.cam.start(study: rig.study, now: Self.t0)
        #expect(rig.study.session.isRunning, "the timer still runs")
        #expect(rig.cam.game.active == nil)
    }

    @Test func theEndOfTheBlockResolvesItOnceAndShowsTheTape() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        let strike = rig.cam.game.setup.strike
        rig.cam.pick = strike
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(601))
        #expect(rig.cam.game.active == nil)
        let record = try #require(rig.cam.reveal)
        #expect(record.outcome == .caught)
        #expect(record.endedAt == Self.t0.addingTimeInterval(600), "stamped with the real end, not when it was noticed")
        // Points paid exactly as in the foundation: 10 minutes, no bonus.
        #expect(rig.study.balance == PetCloset(save: PetSave(profile: .starter(.cat))).balance + 10)
        rig.cam.watched(record)
        #expect(rig.cam.reveal == nil)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(700))
        #expect(rig.cam.game.log.blocks.count == 1, "credited once")
    }

    @Test func theHomeScreenKeepsTheTapesSecretUntilItIsWatched() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        let before = rig.cam.frozenShot
        let room = rig.cam.game.room
        rig.cam.pick = rig.cam.game.setup.strike
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(601))
        let record = try #require(rig.cam.reveal)
        #expect(record.outcome == .caught)
        // The game has moved on: the wreck is down and a new object is out.
        #expect(rig.cam.game.room != room)
        // But the home screen still shows the room, the stare and the wall
        // from before the block, so a glance at it gives nothing away.
        #expect(rig.cam.frozenShot == before)
        #expect(rig.cam.shownRoom == room)
        #expect(rig.cam.mugshots.isEmpty)
        #expect(rig.cam.cases.isEmpty)
        // Once watched, everything catches up at once.
        rig.cam.watched(record)
        #expect(rig.cam.shownRoom == rig.cam.game.room)
        #expect(rig.cam.frozenShot == PetCamShot.frozenFrame(room: rig.cam.game.room, setup: rig.cam.game.setup))
        #expect(rig.cam.mugshots.map(\.id) == [record.id])
        #expect(rig.cam.cases.map(\.id) == [record.id])
        #expect(rig.cam.caseNumber(of: record) == 1)
        #expect(rig.cam.caughtKinds == [try #require(record.struck?.kind)])
    }

    @Test func aMissIsFiledAsAColdCaseWithNoCaseNumber() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        let strike = rig.cam.game.setup.strike
        rig.cam.pick = PetCamSpot.allCases.first { $0 != strike }
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(601))
        let record = try #require(rig.cam.reveal)
        #expect(record.outcome == .missed)
        rig.cam.watched(record)
        #expect(rig.cam.cases.map(\.id) == [record.id])
        #expect(rig.cam.mugshots.isEmpty, "the wall's count is catches only")
        #expect(rig.cam.caseNumber(of: record) == nil)
        #expect(rig.cam.caughtKinds.isEmpty)
    }

    @Test func stoppingEarlyGivesTheFrozenStillAndKeepsTheFrame() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(25)
        let setup = rig.cam.game.setup
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.study.stop(at: Self.t0.addingTimeInterval(400))
        let record = try #require(rig.cam.reveal)
        #expect(record.outcome == .stopped)
        #expect(record.worked == 400)
        #expect(rig.cam.game.setup == setup)
        #expect(PetCamTape(record: record)?.stills.count == 1)
    }

    @Test func aBlockThatEndedWhileTheAppWasClosedResolvesOnLaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let rig = Rig(folder: folder)
            rig.timer(10)
            rig.cam.start(study: rig.study, now: Self.t0)
        }
        // Killed; opened an hour later.
        let later = Rig(folder: folder, at: Self.t0.addingTimeInterval(3600))
        #expect(later.cam.game.active == nil)
        let record = try #require(later.cam.reveal)
        #expect(record.outcome.hasTape)
        #expect(record.endedAt == Self.t0.addingTimeInterval(600))
        // And opened again: nothing is credited twice.
        let again = Rig(folder: folder, at: Self.t0.addingTimeInterval(7200))
        #expect(again.cam.game.log.blocks.count == 1)
        #expect(again.cam.game.room == later.cam.game.room)
    }

    @Test func aTapeWaitsUntilTheAppIsOnScreen() throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.cam.setActive(false)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(601))
        #expect(rig.cam.reveal == nil)
        #expect(rig.cam.hasTapeWaiting, "the app comes back to static, not the home screen")
        rig.cam.setActive(true)
        let record = try #require(rig.cam.reveal)
        rig.cam.watched(record)
        #expect(!rig.cam.hasTapeWaiting)
    }

    @Test func anUnreadableGameIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("petcam.json")
        let garbage = Data("{\"schemaVersion\": 1, \"room\": 42}".utf8)
        try garbage.write(to: url)
        let rig = Rig(folder: folder)
        rig.timer(10)
        rig.cam.start(study: rig.study, now: Self.t0)
        #expect(try Data(contentsOf: url) == garbage)
    }

    @Test func theEndNotificationOfAFilmedBlockSaysTheTapeIsReady() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: Self.t0)
        let filmed = PhaseAlert.upcoming(for: session, filming: true)
        #expect(filmed.first?.title == "Block done")
        #expect(filmed.first?.body == "The tape is ready.")
        #expect(filmed.dropFirst().first?.title == PhaseAlert.upcoming(for: session).dropFirst().first?.title,
                "the break's end is worded as before")
        let plain = PhaseAlert.upcoming(for: session)
        #expect(plain.first?.title != "Block done")
        for alert in filmed + plain {
            for word in ["mug", "plant", "fishbowl", "counter", "shelf"] {
                #expect(!alert.body.lowercased().contains(word), "the notification says nothing about the room")
            }
        }
    }

    @Test func theLiveActivityShowsTheCameraOnlyForAFilmedFocusBlock() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: Self.t0)
        let filmed = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0, camera: 3))
        #expect(filmed.filming)
        #expect(filmed.camera == 3, "the hidden camera's number")
        #expect(filmed.doneLine == "Tape ready")
        let plain = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0))
        #expect(!plain.filming)
        _ = session.advance(to: Self.t0.addingTimeInterval(1500))
        let onBreak = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0.addingTimeInterval(1501),
                                                                        camera: 3))
        #expect(!onBreak.filming, "a break is never filmed")
        #expect(onBreak.camera == nil)
    }

    @Test func everyFramingDrawsAtAWholeMultipleOfTheWideShot() {
        for width: CGFloat in [233, 300, 342, 366, 370, 400, 402, 1000] {
            for displayScale: CGFloat in [1, 2, 3] {
                let wide = FeedView.devicePixels(spriteWidth: 100, width: width, displayScale: displayScale)
                #expect(FeedView.devicePixels(spriteWidth: 50, width: width, displayScale: displayScale) == wide * 2)
                // So a cut between cameras never changes the picture's size.
                let sizes = [PetCamShot.Framing.wide, .spot(.table), .closeUp(.strike(.table)),
                             .wreck(.counter, hidden: false)].map {
                    FeedView.pictureSize($0, width: width, displayScale: displayScale)
                }
                #expect(Set(sizes.map(\.width)).count == 1 && Set(sizes.map(\.height)).count == 1)
            }
        }
    }

    @Test func theHomeFeedCropsTheFloorRatherThanShrinking() {
        // Room for all of it: all of it.
        #expect(HomeScreen.feedHeight(picture: 586, room: 700) == 586)
        // Less room (the Timer's stepper): the bottom is cropped.
        #expect(HomeScreen.feedHeight(picture: 586, room: 520) == 516)
        // Never past the rug; the page scrolls instead.
        #expect(HomeScreen.feedHeight(picture: 586, room: 200) == (586 * 0.74).rounded(.down))
    }

    @Test func everyCueHasASoundAndTheBedIsQuiet() {
        let cues: [PetCamTape.Cue] = [.motion, .stamp] + PetCamObjectKind.allCases.flatMap {
            [PetCamTape.Cue.strike($0), .offCamera($0)]
        }
        for cue in cues {
            let samples = TapeSound.samples(cue)
            #expect(samples.count > 1000, "\(cue) is a real sound")
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(samples.map(abs).max() ?? 0 > 0.05, "\(cue) is audible: \(samples.map(abs).max() ?? 0)")
            #expect(TapeSound.samples(cue) == samples, "the same every time")
        }
        for kind in PetCamObjectKind.allCases {
            let loud = TapeSound.samples(.strike(kind)).map(abs).max() ?? 0
            let muffled = TapeSound.samples(.offCamera(kind)).map(abs).max() ?? 0
            #expect(muffled < loud, "off camera is quieter: \(kind)")
        }
        #expect(TapeSound.hiss(seconds: 1).map(abs).max() ?? 1 < 0.1, "the hiss sits under everything")
    }

    @Test func aTapeExportsAsAVerticalVideoWithSoundUnderTwentySeconds() async throws {
        let rig = Rig()
        defer { try? FileManager.default.removeItem(at: rig.folder) }
        rig.timer(10)
        rig.cam.pick = rig.cam.game.setup.strike
        rig.cam.dodge = "the dishes"
        rig.cam.start(study: rig.study, now: Self.t0)
        rig.study.catchUp(at: Self.t0.addingTimeInterval(601))
        let record = try #require(rig.cam.reveal)
        let url = try await TapeExporter.export(record, caseNumber: 1, includeDodge: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tape = try #require(PetCamTape(record: record))
        // OWNER AWAY, the tape with its cuts, and the TABBI CAM slate.
        let cards = Double(TapeExporter.openerFrames + TapeExporter.slateFrames) / Double(TapeExporter.framesPerSecond)
        #expect(abs(duration - tape.duration - cards) < 1, "\(duration) s for a \(tape.duration) s tape")
        #expect(duration < PetCamTape.maximumDuration)
        #expect(PetCamTape.durationRange.contains(tape.duration))
        let sound = try #require(try await asset.loadTracks(withMediaType: .audio).first, "the tape's own sound")
        #expect(abs(try await sound.load(.timeRange).duration.seconds - duration) < 0.5)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(size == CGSize(width: 1080, height: 1920))
    }
}
