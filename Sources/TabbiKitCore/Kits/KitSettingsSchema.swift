import Foundation

/// The shape of one module's section in a kit's `moduleSettings`, declared
/// on the module's descriptor (`ModuleDescriptor.kitSettings`), so kit
/// validation can warn about a mistyped key or a value of the wrong kind
/// in any module's section without knowing that module.
///
/// The schema is data, not code, and has no type for URLs, paths or
/// commands: a module's kit settings can only be plain values within
/// bounds. Modules still read their section leniently and fall back to
/// their defaults, so a warning here never stops a kit from loading.
public struct KitSettingsSchema: Hashable, Sendable {
    /// The keys the section may have. Every key is optional.
    public var fields: [String: KitSettingType]

    public init(_ fields: [String: KitSettingType]) {
        self.fields = fields
    }

    /// What's wrong with `section`, with paths starting at `path` (such as
    /// `moduleSettings.planner`), sorted by path so warnings read in a
    /// stable order.
    public func issues(in section: KitValue, at path: String) -> [KitIssue] {
        KitSettingType.object(fields).issues(in: section, at: path)
    }
}

/// A value a module accepts in its kit settings.
public indirect enum KitSettingType: Hashable, Sendable {
    case bool
    /// A number within `range`.
    case number(ClosedRange<Double>)
    /// Text of at most `maxLength` characters.
    case text(maxLength: Int)
    /// One of a fixed set of strings, such as a mode.
    case choice([String])
    /// A single line of text or a list of up to `maxCount` lines, each at
    /// most `maxLength` characters.
    case lines(maxLength: Int, maxCount: Int)
    /// An object with these optional keys.
    case object([String: KitSettingType])
    /// A list of up to `maxCount` items, each checked against `item`, so a
    /// warning names the one item that doesn't fit (`methods[2]`).
    case list(KitSettingType, maxCount: Int)

    /// What the value should be, for a warning: "a number from 0 to 22".
    public var expectation: String {
        switch self {
        case .bool: "true or false"
        case .number(let range): "a number from \(range.lowerBound.formatted()) to \(range.upperBound.formatted())"
        case .text(let maxLength): "text of at most \(maxLength) characters"
        case .choice(let values): "one of " + values.map { "\"\($0)\"" }.joined(separator: ", ")
        case .lines(let maxLength, let maxCount):
            "a line or a list of up to \(maxCount) lines, each at most \(maxLength) characters"
        case .object: "an object"
        case .list(_, let maxCount): "a list of up to \(maxCount) items"
        }
    }

    func issues(in value: KitValue, at path: String) -> [KitIssue] {
        if case .object(let fields) = self, case .object(let object) = value {
            return object.keys.sorted().flatMap { key -> [KitIssue] in
                let child = "\(path).\(key)"
                guard let type = fields[key] else { return [.unknownField(child)] }
                return type.issues(in: object[key] ?? .null, at: child)
            }
        }
        if case .list(let item, let maxCount) = self, case .array(let items) = value, items.count <= maxCount {
            return items.indices.flatMap { item.issues(in: items[$0], at: "\(path)[\($0)]") }
        }
        let fits: Bool = switch (self, value) {
        case (.bool, .bool): true
        case (.number(let range), .number(let number)): range.contains(number)
        case (.text(let maxLength), .string(let text)): text.count <= maxLength
        case (.choice(let values), .string(let text)): values.contains(text)
        case (.lines(let maxLength, _), .string(let text)): text.count <= maxLength
        case (.lines(let maxLength, let maxCount), .array(let items)):
            items.count <= maxCount && items.allSatisfy { $0.stringValue.map { $0.count <= maxLength } ?? false }
        default: false
        }
        return fits ? [] : [.invalidModuleSetting(path: path, expected: expectation)]
    }
}
