import XCTest
import TabbiKitCore
@testable import Tabbi

/// The launch-time opt-in: a crash is asked about until the person picks a
/// standing answer, nothing is sent without a yes, and the prompt shows the
/// exact body the uploader sends.
@MainActor
final class CrashReportFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var asked: [CrashReport] = []
    private var sent: [CrashReport] = []
    private let report = CrashReportPrompt.sample

    override func setUp() async throws {
        suiteName = "CrashReportFlowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        asked = []
        sent = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func flow(answer: CrashReportFlow.Answer) -> CrashReportFlow {
        CrashReportFlow(
            consent: CrashReportConsentStore(defaults: defaults),
            ask: { [unowned self] in asked.append($0); return answer },
            send: { [unowned self] in sent.append($0) }
        )
    }

    func testNoCrashAsksAndSendsNothing() {
        flow(answer: .init(choice: .send, dontAskAgain: true)).run(with: nil)
        XCTAssertTrue(asked.isEmpty)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(CrashReportConsentStore(defaults: defaults).load(), .ask)
    }

    func testSendOnceSendsAndAsksAgainNextTime() {
        flow(answer: .init(choice: .send, dontAskAgain: false)).run(with: report)
        XCTAssertEqual(asked, [report])
        XCTAssertEqual(sent, [report])
        flow(answer: .init(choice: .dontSend, dontAskAgain: false)).run(with: report)
        XCTAssertEqual(asked.count, 2, "without Don't ask again the next crash is asked about too")
        XCTAssertEqual(sent.count, 1)
    }

    func testDontSendSendsNothing() {
        flow(answer: .init(choice: .dontSend, dontAskAgain: false)).run(with: report)
        XCTAssertEqual(asked.count, 1)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(CrashReportConsentStore(defaults: defaults).load(), .ask)
    }

    func testAlwaysSendStopsAsking() {
        flow(answer: .init(choice: .send, dontAskAgain: true)).run(with: report)
        XCTAssertEqual(CrashReportConsentStore(defaults: defaults).load(), .alwaysSend)
        flow(answer: .init(choice: .dontSend, dontAskAgain: false)).run(with: report)
        XCTAssertEqual(asked.count, 1, "an always-send answer is not asked again")
        XCTAssertEqual(sent.count, 2)
    }

    func testNeverSendDropsLaterReportsUnseen() {
        flow(answer: .init(choice: .dontSend, dontAskAgain: true)).run(with: report)
        XCTAssertEqual(CrashReportConsentStore(defaults: defaults).load(), .neverSend)
        flow(answer: .init(choice: .send, dontAskAgain: false)).run(with: report)
        XCTAssertEqual(asked.count, 1)
        XCTAssertTrue(sent.isEmpty)
    }

    func testPromptShowsTheExactBodyAndTheChoices() throws {
        let alert = CrashReportPrompt.makeAlert(for: report)
        XCTAssertEqual(alert.messageText, "\(Edition.current.name) closed unexpectedly. Send a crash report?")
        XCTAssertEqual(alert.buttons.map(\.title), ["Send", "Don't Send"])
        XCTAssertTrue(alert.showsSuppressionButton)
        XCTAssertEqual(alert.suppressionButton?.title, "Don't ask again")
        let scroll = try XCTUnwrap(alert.accessoryView as? NSScrollView)
        let shown = try XCTUnwrap((scroll.documentView as? NSTextView)?.string)
        XCTAssertEqual(shown, report.disclosure)
        let body = try JSONSerialization.jsonObject(with: report.jsonData()) as? NSDictionary
        let disclosed = try JSONSerialization.jsonObject(with: Data(shown.utf8)) as? NSDictionary
        XCTAssertEqual(body, disclosed, "the disclosure is the body that is sent")
    }
}
