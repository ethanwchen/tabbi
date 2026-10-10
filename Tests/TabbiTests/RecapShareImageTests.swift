import AppKit
import XCTest
import TabbiKitCore
@testable import Tabbi

@MainActor
final class RecapShareImageTests: XCTestCase {
    func testExportsAPNGAtEachFormatsFullSize() throws {
        let archive = RecapArchive.demo(now: Date())
        let recap = try XCTUnwrap(archive.recaps.first)
        for format in RecapShareFormat.allCases {
            let image = RecapShareImage(recap: recap, cheer: archive.cheer(for: recap), pet: nil, format: format)
            let png = try XCTUnwrap(image.png(), "\(format) did not render")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            XCTAssertEqual(bitmap.pixelsWide, format.pixelSize.width)
            XCTAssertEqual(bitmap.pixelsHigh, format.pixelSize.height)
        }
    }

    func testWritesEachShapeUnderItsFileNameAndReplacesAnEarlierExport() throws {
        let archive = RecapArchive.demo(now: Date())
        let recap = try XCTUnwrap(archive.recaps.first)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecapShareImageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for format in RecapShareFormat.allCases {
            let url = try RecapSharing.writeImage(recap: recap, cheer: archive.cheer(for: recap), pet: nil,
                                                  format: format, into: folder)
            XCTAssertEqual(url.lastPathComponent, format.fileName(for: recap.week))
            let again = try RecapSharing.writeImage(recap: recap, cheer: archive.cheer(for: recap), pet: nil,
                                                    format: format, into: folder)
            XCTAssertEqual(again, url)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            XCTAssertEqual(bitmap.pixelsWide, format.pixelSize.width)
            XCTAssertEqual(bitmap.pixelsHigh, format.pixelSize.height)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }
}
