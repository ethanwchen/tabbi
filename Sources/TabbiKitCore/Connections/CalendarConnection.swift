import Foundation

/// What macOS lets Tabbi do with the calendar, mirrored from EventKit's
/// authorization status so the rules stay in tested core code.
public enum CalendarAccess: String, CaseIterable, Hashable, Sendable {
    /// Never asked.
    case notDetermined
    /// The user said no (or later turned it off).
    case denied
    /// A device policy blocks it.
    case restricted
    /// Tabbi may add events but not read them.
    case writeOnly
    /// Tabbi may read and add events.
    case fullAccess
}

/// Where the calendar connection stands: the access macOS gives and which
/// accounts' calendars Tabbi can see.
public struct CalendarConnectionState: Hashable, Sendable {
    public var access: CalendarAccess
    /// The titles of the accounts (EventKit sources) that hold at least one
    /// event calendar, such as "iCloud", "Google" or "you@gmail.com".
    public var accounts: [String]

    public init(access: CalendarAccess, accounts: [String] = []) {
        self.access = access
        self.accounts = accounts
    }

    /// Whether any visible account looks like Google. macOS names an
    /// account added in Internet Accounts "Google" unless renamed, and
    /// older setups use the address itself.
    public var hasGoogleAccount: Bool { accounts.contains(where: Self.isGoogleAccount) }

    public static func isGoogleAccount(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("google") || lower.hasSuffix("@gmail.com") || lower.hasSuffix("@googlemail.com")
    }

    public var connectionStatus: ConnectionStatus {
        switch access {
        case .notDetermined:
            return ConnectionStatus(light: .notSetUp, headline: "Calendar isn't connected",
                                    detail: "Click Connect, then OK when your Mac asks. It only asks once.",
                                    action: .askPermission(.calendar))
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: "Calendar access is off",
                                    detail: "Turn on Tabbi under Calendars in System Settings.",
                                    action: .openSettings(.calendarPrivacy))
        case .restricted:
            return ConnectionStatus(light: .needsStep, headline: "This Mac blocks calendar access",
                                    detail: "A school or work setting may block it. You can check in System Settings.",
                                    action: .openSettings(.calendarPrivacy))
        case .writeOnly:
            return ConnectionStatus(light: .needsStep, headline: "Tabbi can't read your calendar",
                                    detail: "In System Settings, set Tabbi to Full Access under Calendars.",
                                    action: .openSettings(.calendarPrivacy))
        case .fullAccess where accounts.isEmpty:
            return ConnectionStatus(light: .needsStep, headline: "No calendars yet",
                                    detail: "Add your Google or school account to see its events here.",
                                    action: .showGuide(.googleCalendar))
        case .fullAccess:
            return ConnectionStatus(light: .connected, headline: "Calendar is connected",
                                    detail: "Today's events show up in Tabbi.",
                                    suggestion: hasGoogleAccount ? nil : .showGuide(.googleCalendar))
        }
    }
}
