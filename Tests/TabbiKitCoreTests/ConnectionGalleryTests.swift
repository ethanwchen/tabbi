import XCTest
import TabbiKitCore

final class ConnectionGalleryTests: XCTestCase {
    func testEveryRowGoesFromNothingToConnected() {
        for kind in ConnectionKind.allCases {
            let states = kind.everyState
            XCTAssertFalse(states.isEmpty, "\(kind) has no states")
            XCTAssertTrue(states.allSatisfy { $0.kind == kind }, "\(kind) lists another row's state")
            XCTAssertEqual(states.last?.status.light, .connected, "\(kind) should end connected")
            XCTAssertNotEqual(states.first?.status.light, .connected, "\(kind) should start before connected")
        }
    }

    func testEveryStateIsDistinct() {
        for kind in ConnectionKind.allCases {
            let labels = kind.everyState.map(\.technical)
            XCTAssertEqual(Set(labels).count, labels.count, "\(kind) repeats a state: \(labels)")
        }
    }

    func testEveryProblemHasExactlyOneNextButton() {
        for kind in ConnectionKind.allCases {
            for state in kind.everyState where !state.status.isConnected && state.status.light != .checking {
                XCTAssertNotNil(state.status.action, "\(state.technical) leaves the user stuck")
                XCTAssertNotNil(state.firstFailure, "\(state.technical) has no failed check to explain it")
            }
        }
    }

    func testRowTextNeverRepeatsTheUnlocksLine() {
        for kind in ConnectionKind.allCases {
            let unlocks = kind.unlocks.lowercased().trimmingCharacters(in: .punctuationCharacters)
            for state in kind.everyState {
                for text in [state.status.headline, state.status.detail] {
                    let line = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    XCTAssertFalse(unlocks.hasPrefix(line) || line.hasPrefix(unlocks),
                                   "\(state.technical) repeats \"\(kind.unlocks)\"")
                }
            }
        }
    }

    func testCoversEveryLightARowCanShow() {
        let lights = Set(ConnectionKind.allCases.flatMap { $0.everyState.map(\.status.light) })
        XCTAssertEqual(lights, [.checking, .connected, .needsStep, .notSetUp, .notInstalled])
        XCTAssertTrue(ConnectionKind.anki.everyState.contains { $0.status.light == .notInstalled })
        XCTAssertFalse(ConnectionKind.music.everyState.contains { $0.status.light == .notInstalled },
                       "Music comes with every Mac")
    }

    func testIncludesTheDemoState() {
        for kind in ConnectionKind.allCases {
            XCTAssertTrue(kind.everyState.map(\.status).contains(kind.demoStatus), "\(kind) demo state missing")
        }
    }
}
