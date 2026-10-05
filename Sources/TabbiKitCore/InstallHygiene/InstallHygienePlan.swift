import Foundation

/// What Tabbi remembers about installing itself, kept in `UserDefaults`.
public struct InstallRecord: Codable, Equatable, Sendable {
    /// The user chose "Don't Ask Again" in the move prompt.
    public var neverOfferMove: Bool
    /// Launch at login has been turned on by default once (or deliberately
    /// skipped for someone who already used Tabbi), so it is never forced
    /// again after the user turns it off.
    public var launchAtLoginDefaultApplied: Bool

    public init(neverOfferMove: Bool = false, launchAtLoginDefaultApplied: Bool = false) {
        self.neverOfferMove = neverOfferMove
        self.launchAtLoginDefaultApplied = launchAtLoginDefaultApplied
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        neverOfferMove = try container.decodeIfPresent(Bool.self, forKey: .neverOfferMove) ?? false
        launchAtLoginDefaultApplied = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginDefaultApplied) ?? false
    }

    /// The stored format; add a step here when it changes.
    public static let schema = VersionedJSON(current: 1)
    /// The `UserDefaults` key holding the record as versioned JSON.
    public static let defaultsKey = "install.record"

    /// The saved record, or nil on a first launch (or if it can't be read).
    public static func load(from defaults: UserDefaults) -> InstallRecord? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? schema.decode(InstallRecord.self, from: data)
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? Self.schema.encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// The launch-time decisions of install hygiene, made from plain facts so
/// they are testable: whether to offer the move to Applications, where the
/// copy goes, and whether to turn launch at login on by default.
public struct InstallHygienePlan: Equatable, Sendable {
    /// Offer to move the app to an Applications folder.
    public var offerMove: Bool
    /// Turn launch at login on now, the one time it defaults to on.
    public var enableLaunchAtLogin: Bool
    /// The record to save after this launch, or nil to leave it as it is.
    public var record: InstallRecord?

    public init(offerMove: Bool, enableLaunchAtLogin: Bool, record: InstallRecord?) {
        self.offerMove = offerMove
        self.enableLaunchAtLogin = enableLaunchAtLogin
        self.record = record
    }

    /// - Parameters:
    ///   - location: where the app runs from.
    ///   - record: the saved record, nil on the first launch with install hygiene.
    ///   - runMode: demo and snapshot runs leave the system and the record alone.
    ///   - isReturningUser: this Mac already has Tabbi settings from before
    ///     install hygiene existed. Read only while `record` is nil: such a
    ///     user already made their login item choice, so it stands.
    public init(location: InstallLocation, record: InstallRecord?, runMode: RunMode, isReturningUser: Bool) {
        guard !runMode.isEphemeral else {
            self.init(offerMove: false, enableLaunchAtLogin: false, record: nil)
            return
        }
        var updated = record ?? InstallRecord(launchAtLoginDefaultApplied: isReturningUser)
        // A login item registered from a disk image or a translocated path
        // would point at a path that is gone next time, so the default waits
        // until the app runs from an Applications folder.
        let enable = !updated.launchAtLoginDefaultApplied && location.isInstalled
        if enable { updated.launchAtLoginDefaultApplied = true }
        self.init(offerMove: location.shouldOfferMove && !updated.neverOfferMove,
                  enableLaunchAtLogin: enable,
                  record: updated == record ? nil : updated)
    }

    /// The Applications folder the moved copy goes to: `/Applications` when
    /// it can be written to (an admin account), otherwise `~/Applications`.
    public static func destinationFolder(home: URL, systemApplicationsIsWritable: Bool) -> URL {
        systemApplicationsIsWritable
            ? URL(fileURLWithPath: "/Applications", isDirectory: true)
            : home.appendingPathComponent("Applications", isDirectory: true)
    }
}
