import Foundation

/// `UserDefaults` that live only in this object, for snapshot runs and tests.
///
/// A named suite is one shared domain on disk: every process that opens it
/// (two snapshot renders, a test run beside another) reads what the others
/// write, so a store built on it can load another run's kit. A suite also
/// leaves a plist in ~/Library/Preferences, even after its domain is removed.
/// These values start empty and are never shared or written anywhere.
public final class InMemoryDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    public init() {
        // A nil suite name is the app's own domain, which every read and
        // write below bypasses.
        super.init(suiteName: nil)!
    }

    override public func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override public func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override public func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    override public func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }

    // The typed accessors go straight to the system's preferences store on
    // Darwin, so each one reads and writes `values` instead.

    override public func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    override public func array(forKey defaultName: String) -> [Any]? {
        object(forKey: defaultName) as? [Any]
    }

    override public func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }

    override public func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    override public func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }

    override public func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    override public func float(forKey defaultName: String) -> Float {
        (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }

    override public func double(forKey defaultName: String) -> Double {
        (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    override public func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    override public func url(forKey defaultName: String) -> URL? {
        object(forKey: defaultName) as? URL
    }

    override public func set(_ value: Int, forKey defaultName: String) {
        set(NSNumber(value: value), forKey: defaultName)
    }

    override public func set(_ value: Float, forKey defaultName: String) {
        set(NSNumber(value: value), forKey: defaultName)
    }

    override public func set(_ value: Double, forKey defaultName: String) {
        set(NSNumber(value: value), forKey: defaultName)
    }

    override public func set(_ value: Bool, forKey defaultName: String) {
        set(NSNumber(value: value), forKey: defaultName)
    }

    override public func set(_ url: URL?, forKey defaultName: String) {
        set(url as Any?, forKey: defaultName)
    }
}
