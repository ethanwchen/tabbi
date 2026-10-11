import Foundation

/// What Today's "Up next" card says when it has no event to show, and the
/// one action that would fix it.
///
/// The kit names what the calendar holds (`TodayPlanSettings.upNextEvents`,
/// a lowercase phrase such as "lectures, labs, and shifts"), so a study kit
/// reads naturally without medicine wording in the app. Every state that could be fixed by adding an
/// account explains that Google and other calendars come in through macOS
/// Internet Accounts, since there's no separate sign-in in the app.
public struct UpNextEmptyState: Hashable, Sendable {
    public enum Situation: Hashable, Sendable {
        /// Calendar access was never requested.
        case notAsked
        /// Access is denied, restricted, or write-only.
        case denied
        /// This build can't ask for access from the notch (no usage
        /// description), so Connections takes over.
        case unavailable
        /// Access is granted but every calendar is local, and today is empty:
        /// most likely the user's real calendar lives in an online account.
        case noAccounts
        /// Nothing on any calendar today.
        case freeDay
        /// Today had events, and they're all over.
        case dayDone
        /// Nothing on any calendar tomorrow.
        case freeTomorrow
        /// Nothing was on any calendar yesterday.
        case freeYesterday
    }

    public enum Action: Hashable, Sendable {
        case requestAccess
        case openPrivacySettings
        case openInternetAccounts
        /// Opens the Connections hub, which walks through the steps this
        /// card can't take by itself.
        case openConnections
    }

    public var symbol: String
    public var title: String
    public var detail: String
    public var action: Action?
    /// The action button's label and tooltip; empty without an action.
    public var actionTitle: String
    public var actionHelp: String

    public init(_ situation: Situation, upNextEvents: String, appName: String) {
        let upNextEvents = Self.localizedEvents(upNextEvents)
        switch situation {
        case .notAsked:
            symbol = "calendar"
            title = String(localized: "See what's next", bundle: .tabbi)
            detail = String(localized: "Today's \(upNextEvents). Google calendars show up once added in Internet Accounts.",
                            bundle: .tabbi)
            action = .requestAccess
            actionTitle = String(localized: "Show calendar", bundle: .tabbi)
            actionHelp = String(localized: "Allow \(appName) to read your calendars", bundle: .tabbi)
        case .denied:
            symbol = "calendar.badge.exclamationmark"
            title = String(localized: "Calendar access is off", bundle: .tabbi)
            detail = String(localized: "Allow \(appName) in Privacy & Security.", bundle: .tabbi)
            action = .openPrivacySettings
            actionTitle = String(localized: "Open Settings", bundle: .tabbi)
            actionHelp = String(localized: "Open Calendars privacy settings", bundle: .tabbi)
        case .unavailable:
            symbol = "calendar"
            title = String(localized: "Connect your calendar", bundle: .tabbi)
            detail = String(localized: "See your \(upNextEvents) here. It only takes a moment.", bundle: .tabbi)
            action = .openConnections
            actionTitle = String(localized: "Connect calendar", bundle: .tabbi)
            actionHelp = String(localized: "Open Connections to connect your calendar", bundle: .tabbi)
        case .noAccounts:
            symbol = "calendar.badge.plus"
            title = String(localized: "Add your calendar", bundle: .tabbi)
            detail = String(localized: "Using Google? Add it in Internet Accounts to see your \(upNextEvents) here.", bundle: .tabbi)
            action = .openInternetAccounts
            actionTitle = String(localized: "Internet Accounts", bundle: .tabbi)
            actionHelp = String(localized: "Open Internet Accounts to add a Google, Exchange or iCloud calendar", bundle: .tabbi)
        case .freeDay:
            symbol = "calendar.badge.checkmark"
            title = String(localized: "Nothing on today", bundle: .tabbi)
            detail = String(localized: "No events on your calendars today.", bundle: .tabbi)
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .dayDone:
            symbol = "calendar.badge.checkmark"
            title = String(localized: "No more events today", bundle: .tabbi)
            detail = String(localized: "The rest of the day is yours.", bundle: .tabbi)
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .freeTomorrow:
            symbol = "calendar.badge.checkmark"
            title = String(localized: "Free all day", bundle: .tabbi)
            detail = String(localized: "Nothing on your calendars tomorrow.", bundle: .tabbi)
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .freeYesterday:
            symbol = "calendar"
            title = String(localized: "A free day", bundle: .tabbi)
            detail = String(localized: "Nothing was on your calendars yesterday.", bundle: .tabbi)
            action = nil
            actionTitle = ""
            actionHelp = ""
        }
    }

    /// Which empty state fits a granted calendar with nothing left today, or
    /// nil when there are events to list.
    ///
    /// - Parameters:
    ///   - upcoming: events still ahead today.
    ///   - eventsToday: every timed event today, including finished ones.
    ///   - hasAccounts: whether any calendar syncs from an online account
    ///     (CalDAV, Exchange, iCloud) rather than living only on this Mac.
    public static func granted(upcoming: Int, eventsToday: Int, hasAccounts: Bool) -> Situation? {
        guard upcoming == 0 else { return nil }
        if eventsToday > 0 { return .dayDone }
        return hasAccounts ? .freeDay : .noAccounts
    }

    /// Which empty state fits a granted calendar on `day`: `granted(upcoming:...)`
    /// for today; for yesterday or tomorrow, whether that whole day had any
    /// timed event. Nil when there are events to list.
    public static func granted(on day: PlannerViewedDay, upcoming: Int, eventsThatDay: Int,
                               hasAccounts: Bool) -> Situation? {
        switch day {
        case .today: return granted(upcoming: upcoming, eventsToday: eventsThatDay, hasAccounts: hasAccounts)
        case .yesterday, .tomorrow:
            guard eventsThatDay == 0 else { return nil }
            guard hasAccounts else { return .noAccounts }
            return day == .tomorrow ? .freeTomorrow : .freeYesterday
        }
    }

    /// The kit's phrase for what the calendar holds, in the user's language
    /// when it is one the app ships ("meetings and calls"); a kit's own
    /// phrase stays as written.
    public static func localizedEvents(_ phrase: String) -> String {
        Bundle.tabbi.localizedString(forKey: phrase, value: phrase, table: nil)
    }
}
