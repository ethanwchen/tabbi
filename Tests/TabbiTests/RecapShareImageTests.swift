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
}
