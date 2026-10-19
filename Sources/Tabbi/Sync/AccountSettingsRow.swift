import AuthenticationServices
import SwiftUI
import TabbiKit
import TabbiKitCore

/// The Account row in Settings > General: Sign in with Apple when signed
/// out, the account with Sign Out and Delete Account when signed in. The
/// button is Apple's in both editions: it opens the native sheet where the
/// build has the entitlement and Apple's web page elsewhere
/// (`AppleSignInMethod`). Signed out, everything works as without an account.
/// Accounts are for people 13 and older, as the Terms beside the button
/// say, but signing in never asks for a birthday (App Review guideline
/// 5.1.1(v)); only an answer under 13 given in Party hides the button.
struct AccountSettingsRow: View {
    @ObservedObject var account: SyncStore
    @State private var confirmsDelete = false

    var body: some View {
        LabeledContent {
            controls
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if showsFoundingBadge { FoundingBadge(.label, isMe: true) }
            }
            Text(caption)
                .foregroundStyle(account.notice == nil ? .secondary : Color.orange)
            if showsAgreement {
                Text(LocalizedStringKey(AccountAgeText.agreement))
            }
        }
        .confirmationDialog(String(localized: "Delete your \(Edition.current.name) account?", bundle: .tabbi), isPresented: $confirmsDelete) {
            Button(String(localized: "Delete Account", bundle: .tabbi), role: .destructive) {
                Task { await account.deleteAccount() }
            }
            .help(String(localized: "Delete the account and everything the server keeps for it", bundle: .tabbi))
            Button(String(localized: "Cancel", bundle: .tabbi), role: .cancel) {}
        } message: {
            Text(Self.deleteMessage)
        }
        .onAppear(perform: account.refreshAgeStatus)
    }

    @ViewBuilder
    private var controls: some View {
        switch account.phase {
        case .signedOut where isTooYoung:
            // The caption says when signing in opens.
            EmptyView()
        case .signedOut, .signingIn:
            AppleSignInButton(account: account)
                .frame(width: 160, height: 28)
                .disabled(account.phase == .signingIn)
                .opacity(account.phase == .signingIn ? 0.5 : 1)
                .help(String(localized: "Sign in with your Apple Account to sync your pet across your Macs", bundle: .tabbi))
        case .signedIn, .deleting:
            HStack(spacing: 8) {
                Button(String(localized: "Sign Out", bundle: .tabbi), action: account.signOut)
                    .help(String(localized: "Stop syncing on this Mac. Your pet and progress stay here.", bundle: .tabbi))
                Button(String(localized: "Delete Account", bundle: .tabbi), role: .destructive) { confirmsDelete = true }
                    .help(String(localized: "Delete the account and its synced data from the server", bundle: .tabbi))
            }
            .disabled(account.phase == .deleting)
        }
    }

    private var title: String {
        switch account.phase {
        case .signedOut, .signingIn: String(localized: "Account", bundle: .tabbi)
        case .signedIn, .deleting: account.name ?? String(localized: "Signed in with Apple", bundle: .tabbi)
        }
    }

    /// Only on a signed-in account: the badge is about the account.
    private var showsFoundingBadge: Bool {
        account.isFoundingMember && (account.phase == .signedIn || account.phase == .deleting)
    }

    private var showsAgreement: Bool {
        account.notice == nil && !isTooYoung
            && (account.phase == .signedOut || account.phase == .signingIn)
    }

    private var isTooYoung: Bool {
        if case .tooYoung = account.ageStatus { return true }
        return false
    }

    private var caption: String {
        if let notice = account.notice { return notice }
        switch account.phase {
        case .signedOut:
            if case .tooYoung(let until) = account.ageStatus { return AccountAgeText.tooYoung(until: until) }
            return String(localized: "Sync your pet, points and streaks across your Macs.", bundle: .tabbi)
        case .signingIn: return String(localized: "Signing in…", bundle: .tabbi)
        case .deleting: return String(localized: "Deleting your account…", bundle: .tabbi)
        case .signedIn:
            if account.isSyncing { return String(localized: "Syncing…", bundle: .tabbi) }
            guard let date = account.lastSyncedAt else { return String(localized: "Not synced yet", bundle: .tabbi) }
            return String(localized: "Last synced \(Self.relative(date, now: Date()))", bundle: .tabbi)
        }
    }

    /// What Delete Account removes, in the confirmation, as Apple asks.
    static let deleteMessage = String(localized: """
        This deletes your account and everything the server keeps for it: \
        the synced copy of your pet and points, your friend code, friends and parties. \
        Your pet stays on this Mac. This can't be undone.
        """, bundle: .tabbi)

    /// "just now" for the first minute, then "4 min ago", "2 hr. ago".
    static func relative(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "just now", bundle: .tabbi) }
        let formatter = RelativeDateTimeFormatter()
        // .short, not .abbreviated, which reads "-4 мин" in Russian.
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Apple's Sign in with Apple button, which signs `account` in: the native
/// sheet where the build has the entitlement, Apple's web page elsewhere.
/// Both start from the window the button is in, so the native sheet always
/// has a window to appear over.
struct AppleSignInButton: View {
    @ObservedObject var account: SyncStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppleIDButton(style: colorScheme == .dark ? .white : .black) { window in
            Task { await account.signInWithApple(from: window) }
        }
        // The style is fixed when the button is made.
        .id(colorScheme)
    }
}

/// Apple's own `ASAuthorizationAppleIDButton`, with an action of our own
/// that gets the button's window. SwiftUI's `SignInWithAppleButton` runs
/// the native request itself, with no say in where its sheet goes.
private struct AppleIDButton: NSViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: style)
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        return button
    }

    func updateNSView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        // An AppKit control doesn't follow SwiftUI's .disabled by itself.
        button.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject {
        var action: (NSWindow?) -> Void
        init(action: @escaping (NSWindow?) -> Void) { self.action = action }
        @objc func press(_ sender: NSView) { action(sender.window) }
    }
}

/// What the account says about age, in the row.
enum AccountAgeText {
    /// The links the user agrees to by signing in, as Markdown.
    static var agreement: String {
        String(localized: "By signing in you agree to the [Terms of Use](\(SupportContact.termsURL.absoluteString)) and the [Privacy Policy](\(SupportContact.privacyURL.absoluteString)).", bundle: .tabbi)
    }

    /// What the account row says to someone Party found too young.
    static func tooYoung(until date: Date) -> String {
        String(localized: "Accounts are for people \(PartyAgeCheck.minimumAge) and older. Signing in opens in \(PartyAgeCheck.opensText(date)).", bundle: .tabbi)
    }
}
