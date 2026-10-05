import Foundation
import os

/// Collects the fields of a kit file that no part of the kit format reads,
/// such as a typo (`"tickers"`) or a field from a newer format.
///
/// `KitManifest.decode(from:)` passes one in the decoder's `userInfo`, and
/// each kit type's `init(from:)` reports the keys its own `CodingKeys`
/// don't cover, so the list of known fields lives in exactly one place per
/// type. `moduleSettings` is free-form and never checked here.
final class KitFieldReport: Sendable {
    static let key = CodingUserInfoKey(rawValue: "tabbi.kitFieldReport")!

    private let paths = OSAllocatedUnfairLock(initialState: [String]())

    /// Unknown field paths such as `defaults.tickers` or `onboarding[0].options[1].lable`, sorted.
    var unknownFields: [String] { paths.withLock { $0.sorted() } }

    func add(_ path: String) {
        paths.withLock { $0.append(path) }
    }
}

private struct AnyKitKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    /// Reports every key of the object being decoded that `Keys` doesn't
    /// list. Does nothing when no `KitFieldReport` was passed in.
    func reportUnknownKitFields<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type) {
        guard let report = userInfo[KitFieldReport.key] as? KitFieldReport,
              let container = try? container(keyedBy: AnyKitKey.self) else { return }
        let known = Set(Keys.allCases.map(\.stringValue))
        for key in container.allKeys where !known.contains(key.stringValue) {
            report.add(Self.kitPath(codingPath + [key]))
        }
    }

    /// `defaults.focusSounds[0].volume` style paths, as kit authors write them.
    static func kitPath(_ path: [CodingKey]) -> String {
        path.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}
