import XCTest
import TabbiKitCore

final class ClaudeAskChatLabelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func label(updated: Date, now: Date) -> String {
        let chat = ClaudeAskChat(id: UUID(), createdAt: updated, updatedAt: updated, sessionID: nil, messages: [])
        return chat.dateLabel(now: now, calendar: calendar, locale: locale)
    }

    func testTodayShowsTheTime() {
        XCTAssertEqual(label(updated: date(2026, 10, 5, 9, 41), now: date(2026, 10, 5, 18)), "9:41\u{202F}AM")
    }

    func testYesterdayIsByCalendarDayNotByHours() {
        XCTAssertEqual(label(updated: date(2026, 10, 4, 23, 50), now: date(2026, 10, 5, 0, 10)), "Yesterday")
    }

    func testThePastWeekShowsTheWeekday() {
        XCTAssertEqual(label(updated: date(2026, 10, 1), now: date(2026, 10, 5)), "Thursday")
    }

    func testOlderChatsShowTheDateAndAYearOnlyWhenItDiffers() {
        XCTAssertEqual(label(updated: date(2026, 9, 20), now: date(2026, 10, 5)), "Sep 20")
        XCTAssertEqual(label(updated: date(2025, 12, 30), now: date(2026, 1, 10)), "Dec 30, 2025")
    }

    func testDemoHistoryIsNewestFirstAndOpensLikeASavedChat() throws {
        let now = date(2026, 10, 5)
        let chats = ClaudeAskChat.demoHistory(now: now)
        XCTAssertGreaterThanOrEqual(chats.count, 3)
        XCTAssertEqual(chats.map(\.updatedAt), chats.map(\.updatedAt).sorted(by: >))
        XCTAssertEqual(Set(chats.map(\.id)).count, chats.count)
        XCTAssertTrue(chats.allSatisfy { $0.updatedAt <= now && $0.sessionID != nil })
        // The first is the demo chat, so the panel can open it on launch.
        let first = try XCTUnwrap(chats.first)
        XCTAssertEqual(first.title, ClaudeAskConversation.demo.savedChat()?.title)
        let restored = ClaudeAskConversation(restoring: first)
        XCTAssertEqual(restored.chatID, first.id)
        XCTAssertEqual(restored.sessionID, first.sessionID)
        XCTAssertEqual(restored.savedChat(updatedAt: first.updatedAt), first)
    }

    func testDemoHistoryCanShowAQuestionAskedAboutAScreenshot() throws {
        let now = date(2026, 10, 5)
        let screenshot = ClaudeAskAttachment(pixelWidth: 1440, pixelHeight: 900)
        let chats = ClaudeAskChat.demoHistory(now: now, screenshot: screenshot)
        XCTAssertEqual(chats.count, ClaudeAskChat.demoHistory(now: now).count + 1)
        XCTAssertEqual(chats.map(\.updatedAt), chats.map(\.updatedAt).sorted(by: >))
        // The demo conversation still opens first; the screenshot chat follows.
        XCTAssertTrue(chats[0].messages.allSatisfy { $0.attachments.isEmpty })
        let restored = ClaudeAskConversation(restoring: chats[1])
        let question = try XCTUnwrap(restored.messages.first)
        XCTAssertEqual(question.role, .user)
        XCTAssertEqual(question.attachments, [screenshot])
        XCTAssertEqual(restored.messages.last?.status, .complete)
        XCTAssertFalse(restored.messages.last?.text.isEmpty ?? true)
    }
}
