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
    /// Whether this copy of Tabbi may show the macOS calendar prompt. A
    /// build without a calendar usage description (a bare `swift run`) is
    /// terminated by macOS when it asks, so it must never offer Connect.
    public var canAsk: Bool

    public init(access: CalendarAccess, accounts: [String] = [], canAsk: Bool = true) {
        self.access = access
        self.accounts = accounts
        self.canAsk = canAsk
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
        // Only a development build gets here (the app bundle always has the
        // usage description), so it has no button and no gallery entry.
        case .notDetermined where !canAsk:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "This copy can't use the calendar", bundle: .tabbi),
                                    detail: String(localized: "Open Tabbi from your Applications folder to connect your calendar.", bundle: .tabbi))
        case .notDetermined:
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "Calendar isn't connected", bundle: .tabbi),
                                    detail: String(localized: "Click Connect, then Allow when your Mac asks. It only asks once.", bundle: .tabbi),
                                    action: .askPermission(.calendar))
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Calendar access is off", bundle: .tabbi),
                                    detail: String(localized: "Turn on Tabbi under Calendars in System Settings.", bundle: .tabbi),
                                    action: .openSettings(.calendarPrivacy))
        case .restricted:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "This Mac blocks calendar access", bundle: .tabbi),
                                    detail: String(localized: "A school or work setting may block it. You can check in System Settings.", bundle: .tabbi),
                                    action: .openSettings(.calendarPrivacy))
        case .writeOnly:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Tabbi can't read your calendar", bundle: .tabbi),
                                    detail: String(localized: "In System Settings, set Tabbi to Full Access under Calendars.", bundle: .tabbi),
                                    action: .openSettings(.calendarPrivacy))
        case .fullAccess where accounts.isEmpty:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "No calendars yet", bundle: .tabbi),
                                    detail: String(localized: "Add your Google or school account to see its events here.", bundle: .tabbi),
                                    action: .showGuide(.googleCalendar))
        case .fullAccess:
            return ConnectionStatus(light: .connected, headline: String(localized: "Calendar is connected", bundle: .tabbi),
                                    detail: String(localized: "Today's events show up in Tabbi.", bundle: .tabbi),
                                    suggestion: hasGoogleAccount ? nil : .showGuide(.googleCalendar))
        }
    }
}
