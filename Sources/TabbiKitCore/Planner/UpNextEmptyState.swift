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
        switch situation {
        case .notAsked:
            symbol = "calendar"
            title = "See what's next"
            detail = "Today's \(upNextEvents). Google calendars show up once added in Internet Accounts."
            action = .requestAccess
            actionTitle = "Show calendar"
            actionHelp = "Allow \(appName) to read your calendars"
        case .denied:
            symbol = "calendar.badge.exclamationmark"
            title = "Calendar access is off"
            detail = "Allow \(appName) in Privacy & Security."
            action = .openPrivacySettings
            actionTitle = "Open Settings"
            actionHelp = "Open Calendars privacy settings"
        case .unavailable:
            symbol = "calendar"
            title = "Connect your calendar"
            detail = "See your \(upNextEvents) here. It only takes a moment."
            action = .openConnections
            actionTitle = "Connect calendar"
            actionHelp = "Open Connections to connect your calendar"
        case .noAccounts:
            symbol = "calendar.badge.plus"
            title = "Add your calendar"
            detail = "Using Google? Add it in Internet Accounts to see your \(upNextEvents) here."
            action = .openInternetAccounts
            actionTitle = "Internet Accounts"
            actionHelp = "Open Internet Accounts to add a Google, Exchange or iCloud calendar"
        case .freeDay:
            symbol = "calendar.badge.checkmark"
            title = "Nothing on today"
            detail = "No events on your calendars today."
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .dayDone:
            symbol = "calendar.badge.checkmark"
            title = "No more events today"
            detail = "The rest of the day is yours."
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .freeTomorrow:
            symbol = "calendar.badge.checkmark"
            title = "Free all day"
            detail = "Nothing on your calendars tomorrow."
            action = nil
            actionTitle = ""
            actionHelp = ""
        case .freeYesterday:
            symbol = "calendar"
            title = "A free day"
            detail = "Nothing was on your calendars yesterday."
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
}
