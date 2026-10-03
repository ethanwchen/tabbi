import XCTest
@testable import TabbiKitCore

final class KitChangePreviewTests: XCTestCase {
    private func kit(_ json: String) throws -> KitManifest {
        try KitManifest.decode(from: Data(json.utf8))
    }

    func testListsTabsThatTurnOnAndOffWithTheirNewPermissions() throws {
        let current = AppSettings(modules: ModuleLayout(order: [.system, .focus, .planner], disabled: []))
        let study = try kit(#"""
        {"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner", "spotify", "claudeAsk"],
         "starterTasks": ["Plan the week", "  "]}
        """#)
        let preview = KitChangePreview(applying: study, to: current, catalog: .builtIn)
        XCTAssertEqual(preview.tabs, [.planner, .spotify, .claudeAsk])
        XCTAssertEqual(preview.turnsOn, [.spotify, .claudeAsk])
        XCTAssertEqual(preview.turnsOff, [.system, .focus])
        // Today already needs notifications and calendars; the new tabs add
        // Automation (Now Playing) and the Claude CLI (Ask Claude).
        XCTAssertEqual(preview.newPermissions, [.automation, .claudeCLI])
        XCTAssertEqual(preview.newNetworkAccess.map(\.host), ["i.scdn.co"])
        XCTAssertEqual(preview.starterTasks, ["Plan the week"])
        XCTAssertFalse(preview.changesNotchPreviews, "the kit lists no previews")
        XCTAssertFalse(preview.isEmpty)
    }

    func testFollowsTheOnboardingAnswers() throws {
        let current = AppSettings(modules: ModuleLayout(order: [.planner], disabled: []))
        let manifest = try kit(#"""
        {"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner"],
         "onboarding": [{"id": "music", "prompt": "Music?", "options": [
            {"id": "yes", "label": "Yes", "enables": ["spotify"], "tasks": ["Pick a playlist"]}]}]}
        """#)
        let plain = KitChangePreview(applying: manifest, to: current, catalog: .builtIn)
        XCTAssertTrue(plain.isEmpty)
        let withMusic = KitChangePreview(applying: manifest, answers: ["music": ["yes"]], to: current, catalog: .builtIn)
        XCTAssertEqual(withMusic.turnsOn, [.spotify])
        XCTAssertEqual(withMusic.newPermissions, [.automation])
        XCTAssertEqual(withMusic.starterTasks, ["Pick a playlist"])
    }

    func testListsOnlyNewHostsOffThisMac() throws {
        let current = AppSettings(modules: ModuleLayout(order: [.planner, .spotify], disabled: []))
        let study = try kit(#"""
        {"formatVersion": 1, "id": "med", "name": "Med", "modules": ["planner", "spotify", "anki", "party"]}
        """#)
        let preview = KitChangePreview(applying: study, to: current, catalog: .builtIn)
        XCTAssertEqual(preview.turnsOn, [.anki, .party])
        // Anki's AnkiConnect runs on this Mac and Now Playing was already on,
        // so only Party's server is new.
        XCTAssertEqual(preview.newNetworkAccess,
                       [ModuleNetworkAccess(host: "friends.example.com", purpose: "your presence and parties")])
    }

    func testRecognizesLocalHosts() {
        XCTAssertTrue(ModuleNetworkAccess(host: "127.0.0.1", purpose: "").isLocal)
        XCTAssertTrue(ModuleNetworkAccess(host: "LOCALHOST", purpose: "").isLocal)
        XCTAssertFalse(ModuleNetworkAccess(host: "i.scdn.co", purpose: "").isLocal)
    }

    func testNotesWhenTheClosedNotchPreviewsChange() throws {
        let current = AppSettings(modules: ModuleLayout(order: [.planner], disabled: []))
        let manifest = try kit(#"""
        {"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner"], "defaults": {"ticker": ["focus"]}}
        """#)
        XCTAssertTrue(KitChangePreview(applying: manifest, to: current, catalog: .builtIn).changesNotchPreviews)
    }
}
