import Foundation
import XCTest
import TabbiKitCore

/// A one-connection HTTP server on 127.0.0.1 that reads the request the
/// awkward ways real AnkiConnect builds do: in tiny `recv` calls, or the
/// headers first and the body only after a pause. It answers like
/// AnkiConnect (`Connection: close`, then closes) and keeps what it got.
private final class FakeAnkiServer: @unchecked Sendable {
    enum ReadStyle {
        /// `recv` a few bytes at a time.
        case tinyReads(Int)
        /// Read up to the blank line, wait, then read the body.
        case headersThenBody
    }

    let port: UInt16
    private let listener: Int32
    private let lock = NSLock()
    private var received: (head: String, body: Data)?
    private let done = DispatchSemaphore(value: 0)

    init(style: ReadStyle, reply: String) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 1) == 0 else { throw URLError(.cannotConnectToHost) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        listener = fd
        port = UInt16(bigEndian: address.sin_port)
        let listener = fd
        Thread.detachNewThread { [self] in
            let client = accept(listener, nil, nil)
            defer { close(client); done.signal() }
            guard client >= 0 else { return }
            var buffer = Data()
            func read(_ count: Int) -> Bool {
                var chunk = [UInt8](repeating: 0, count: count)
                let got = recv(client, &chunk, count, 0)
                guard got > 0 else { return false }
                buffer.append(contentsOf: chunk[0..<got])
                return true
            }
            let separator = Data("\r\n\r\n".utf8)
            let step: Int
            switch style {
            case .tinyReads(let size): step = size
            case .headersThenBody: step = 1
            }
            while buffer.range(of: separator) == nil { guard read(step) else { return } }
            let headEnd = buffer.range(of: separator)!.upperBound
            let head = String(decoding: buffer[..<headEnd], as: UTF8.self)
            let size = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            if case .headersThenBody = style { usleep(100_000) }
            while buffer.count - headEnd < size { guard read(step) else { break } }
            lock.withLock { received = (head, Data(buffer[headEnd...])) }
            let body = Data(reply.utf8)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
            let bytes = Data(response.utf8) + body
            _ = bytes.withUnsafeBytes { send(client, $0.baseAddress, bytes.count, 0) }
        }
    }

    /// The request head and body, once the request was read.
    func request() -> (head: String, body: Data)? {
        _ = done.wait(timeout: .now() + 5)
        close(listener)
        return lock.withLock { received }
    }
}

/// Pins how the real transport writes a request, so a change that splits
/// or chunks it, or adds headers AnkiConnect doesn't expect, is caught.
final class AnkiConnectWireTests: XCTestCase {
    private func roundTrip(_ style: FakeAnkiServer.ReadStyle) async throws -> (head: String, body: Data, decks: [AnkiDeck]) {
        let server = try FakeAnkiServer(style: style, reply: #"{"result":{"Default":1,"Biology::Cells":5},"error":null}"#)
        let transport = URLSessionAnkiConnectTransport(endpoint: URL(string: "http://127.0.0.1:\(server.port)")!)
        let decks = try await AnkiConnectClient(transport: transport).decks()
        let request = try XCTUnwrap(server.request())
        return (request.head, request.body, decks)
    }

    private func assertAnkiConnectReadsIt(_ head: String, _ body: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let lines = head.lowercased().split(separator: "\r\n").map(String.init)
        XCTAssertTrue(lines.first?.hasPrefix("post / http/1.1") == true, head, file: file, line: line)
        XCTAssertTrue(lines.contains("content-type: application/json"), head, file: file, line: line)
        XCTAssertTrue(lines.contains("content-length: \(body.count)"), head, file: file, line: line)
        XCTAssertFalse(lines.contains { $0.hasPrefix("transfer-encoding") }, "AnkiConnect rejects chunked bodies", file: file, line: line)
        XCTAssertFalse(lines.contains { $0.hasPrefix("expect") }, "AnkiConnect never sends 100 Continue", file: file, line: line)
        XCTAssertFalse(lines.contains { $0.hasPrefix("origin") }, "an Origin header needs CORS setup", file: file, line: line)
        // Every header line must split on its first colon, as AnkiConnect's parser does.
        for header in lines.dropFirst() where !header.isEmpty {
            XCTAssertTrue(header.contains(":"), header, file: file, line: line)
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any], file: file, line: line)
        XCTAssertEqual(json["action"] as? String, "deckNamesAndIds", file: file, line: line)
        XCTAssertEqual(json["version"] as? Int, 6, file: file, line: line)
        XCTAssertNil(json["key"], file: file, line: line)
    }

    func testServerReadingTinyChunksGetsTheWholeRequest() async throws {
        let (head, body, decks) = try await roundTrip(.tinyReads(7))
        try assertAnkiConnectReadsIt(head, body)
        XCTAssertEqual(decks.map(\.name), ["Biology::Cells", "Default"])
    }

    func testServerReadingHeadersThenBodyGetsTheWholeRequest() async throws {
        let (head, body, decks) = try await roundTrip(.headersThenBody)
        try assertAnkiConnectReadsIt(head, body)
        XCTAssertEqual(decks.count, 2)
    }
}
