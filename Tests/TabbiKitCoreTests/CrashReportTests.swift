import XCTest
import TabbiKitCore

final class CrashReportTests: XCTestCase {
    private let environment = DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi")

    private func json(_ report: CrashReport) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: report.jsonData()) as? [String: Any])
    }

    func testBodyCarriesExactlyTheBackendFields() throws {
        let report = try XCTUnwrap(CrashReport(environment: environment, kind: .signal, name: "SIGSEGV", threads: [
            .init(name: "com.apple.main-thread", crashed: true, frames: ["0   Tabbi   0x0000000102a3c4e8 $s5Tabbi4mainyyF + 120"]),
        ]))
        let body = try json(report)

        XCTAssertEqual(Set(body.keys), ["version", "macos", "edition", "kind", "name", "threads"])
        XCTAssertEqual(body["version"] as? String, "1.4.0 (52)")
        XCTAssertEqual(body["macos"] as? String, "15.1.0")
        XCTAssertEqual(body["edition"] as? String, "tabbi")
        XCTAssertEqual(body["kind"] as? String, "signal")
        XCTAssertEqual(body["name"] as? String, "SIGSEGV")
        let thread = try XCTUnwrap((body["threads"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(thread.keys), ["name", "crashed", "frames"])
        XCTAssertEqual(thread["frames"] as? [String], ["0 Tabbi 0x0000000102a3c4e8 $s5Tabbi4mainyyF + 120"])
        XCTAssertEqual(try JSONDecoder().decode(CrashReport.self, from: report.jsonData()), report)
    }

    func testHomeFoldersAndNonASCIIAreRemoved() throws {
        let report = try XCTUnwrap(CrashReport(environment: environment, kind: .exception, name: "NSInvalidArgumentException: Jane's note", threads: [
            .init(name: "Jane\u{2019}s queue\n", crashed: true, frames: [
                "3 Plugin 0x1 /Users/jane.doe/Developer/Tabbi/.build/Plugin.dylib + 4",
                "4 Disk 0x2 /Volumes/Backup HD/Users/jane/lib.dylib",
                "5 Linux 0x3 /home/jane/x",
                "6 Caf\u{E9} 0x4",
            ]),
        ]))

        XCTAssertEqual(report.name, "NSInvalidArgumentExceptionJanesnote")
        XCTAssertEqual(report.threads[0].name, "Jane?s queue?")
        XCTAssertEqual(report.threads[0].frames, [
            "3 Plugin 0x1 ~/Developer/Tabbi/.build/Plugin.dylib + 4",
            "4 Disk 0x2 ~/lib.dylib",
            "5 Linux 0x3 ~/x",
            "6 Caf? 0x4",
        ])
        let text = try XCTUnwrap(String(data: report.jsonData(), encoding: .utf8))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("/home/"))
        XCTAssertFalse(text.contains("jane"))
        XCTAssertTrue(text.unicodeScalars.allSatisfy { $0.isASCII })
    }

    func testLimitsMatchTheBackend() throws {
        let long = String(repeating: "f", count: 2000)
        let threads = (0..<100).map { index in
            CrashReport.Thread(name: String(repeating: "t", count: 200), crashed: true, frames: Array(repeating: "\(index) \(long)", count: 3))
        }
        let report = try XCTUnwrap(CrashReport(environment: environment, kind: .hang, name: String(repeating: "N", count: 100), threads: threads))

        XCTAssertEqual(report.name.count, CrashReport.maxNameLength)
        XCTAssertLessThanOrEqual(report.threads.count, CrashReport.maxThreads)
        XCTAssertEqual(report.threads.filter(\.crashed).count, 1, "only the first crashed thread stays crashed")
        XCTAssertTrue(report.threads[0].crashed)
        for thread in report.threads {
            XCTAssertEqual(thread.name.count, CrashReport.maxThreadNameLength)
            XCTAssertTrue(thread.frames.allSatisfy { $0.count <= CrashReport.maxFrameLength })
        }
        XCTAssertLessThanOrEqual(try report.jsonData().count, CrashReport.maxEncodedBytes)
    }

    func testOversizedReportKeepsTheCrashedThread() throws {
        let frames = (0..<128).map { "\($0) " + String(repeating: "x", count: 500) }
        let threads = [CrashReport.Thread(name: "worker", crashed: false, frames: frames),
                       CrashReport.Thread(name: "main", crashed: true, frames: frames)]
            + (0..<10).map { CrashReport.Thread(name: "bg \($0)", crashed: false, frames: frames) }
        let report = try XCTUnwrap(CrashReport(environment: environment, kind: .signal, name: "SIGABRT", threads: threads))

        XCTAssertLessThanOrEqual(try report.jsonData().count, CrashReport.maxEncodedBytes)
        let crashed = try XCTUnwrap(report.threads.first(where: \.crashed))
        XCTAssertEqual(crashed.name, "main")
        XCTAssertEqual(crashed.frames.first, frames.first, "trimming keeps the innermost frames")
    }

    func testReportWithoutFramesIsNotSent() {
        XCTAssertNil(CrashReport(environment: environment, kind: .signal, name: "SIGSEGV", threads: []))
        XCTAssertNil(CrashReport(environment: environment, kind: .signal, name: "SIGSEGV", threads: [
            .init(name: "main", crashed: true, frames: ["   ", ""]),
        ]))
    }

    func testDisclosureShowsTheBodyWordForWord() throws {
        let report = try XCTUnwrap(CrashReport(environment: environment, kind: .signal, name: "SIGTRAP", threads: [
            .init(name: "main", crashed: true, frames: ["0 Tabbi 0x1 main + 1"]),
        ]))
        let shown = try JSONDecoder().decode(CrashReport.self, from: Data(report.disclosure.utf8))
        XCTAssertEqual(shown, report)
        XCTAssertTrue(report.disclosure.contains("\"name\" : \"SIGTRAP\""))
    }

    // MARK: - Crash log

    func testSignalHandlerOutputBecomesAReport() throws {
        let text = CrashLog.header(for: environment) + """
        kind signal
        name SIGSEGV
        crashed-thread com.apple.main-thread
        0   Tabbi                               0x0000000102a3c4e8 crashHandler + 52
        1   libsystem_platform.dylib            0x000000018e2a2584 _sigtramp + 56
        thread
        0   libsystem_kernel.dylib              0x000000018e1f1c34 mach_msg2_trap + 8

        """
        let report = try XCTUnwrap(CrashLog.report(from: text))

        XCTAssertEqual(report.environment, environment)
        XCTAssertEqual(report.kind, .signal)
        XCTAssertEqual(report.name, "SIGSEGV")
        XCTAssertEqual(report.threads, [
            .init(name: "com.apple.main-thread", crashed: true, frames: [
                "0 Tabbi 0x0000000102a3c4e8 crashHandler + 52",
                "1 libsystem_platform.dylib 0x000000018e2a2584 _sigtramp + 56",
            ]),
            .init(name: "", crashed: false, frames: ["0 libsystem_kernel.dylib 0x000000018e1f1c34 mach_msg2_trap + 8"]),
        ])
    }

    func testWrittenLogReadsBack() throws {
        let threads: [CrashReport.Thread] = [.init(name: "main", crashed: true, frames: ["0 Tabbi 0x1 f + 2", "1 Tabbi 0x2 g + 3"])]
        let text = CrashLog.text(environment: environment, kind: .exception, name: "NSRangeException", threads: threads)
        XCTAssertEqual(
            CrashLog.report(from: text),
            CrashReport(environment: environment, kind: .exception, name: "NSRangeException", threads: threads)
        )
    }

    func testBrokenLogsAreIgnored() {
        XCTAssertNil(CrashLog.report(from: ""))
        XCTAssertNil(CrashLog.report(from: "something else\nkind signal\nthread main\n0 x"))
        XCTAssertNil(CrashLog.report(from: CrashLog.header(for: environment) + "kind meltdown\nthread main\n0 x\n"))
        // The handler died before it wrote a frame.
        XCTAssertNil(CrashLog.report(from: CrashLog.header(for: environment) + "kind signal\nname SIGBUS\ncrashed-thread main\n"))
    }
}
