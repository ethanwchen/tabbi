@preconcurrency import Combine
import XCTest
@testable import NotchKitCore

@MainActor
final class MainActorDeliveryTests: XCTestCase {
    func testMainThreadValuesArriveSynchronously() {
        var received: [Int] = []
        let subscription = CurrentValueSubject<Int, Never>(1).sinkOnMainActor { received.append($0) }
        XCTAssertEqual(received, [1])
        subscription.cancel()
    }

    func testBackgroundValuesArriveOnTheMainThreadInOrder() {
        let subject = PassthroughSubject<Int, Never>()
        var received: [Int] = []
        let done = expectation(description: "all values delivered")
        let subscription = subject.sinkOnMainActor { value in
            XCTAssertTrue(Thread.isMainThread)
            received.append(value)
            if received.count == 50 { done.fulfill() }
        }
        DispatchQueue.global().async {
            for value in 0..<50 { subject.send(value) }
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(received, Array(0..<50))
        subscription.cancel()
    }
}
