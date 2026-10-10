import AuthenticationServices
import SwiftUI
import TabbiKitCore

/// The Account row in Settings > General: Sign in with Apple when signed
/// out, the account with Sign Out and Delete Account when signed in. The
/// button is Apple's in both editions: it opens the native sheet where the
/// build has the entitlement and Apple's web page elsewhere
/// (`AppleSignInMethod`). Signed out, everything works as without an account.
/// Accounts are for people 13 and older, so until the age check
/// (`PartyAgeCheck`) passed, Sign In opens `AccountAgeSheet` first.
struct AccountSettingsRow: View {
    @ObservedObject var account: SyncStore
    @State private var confirmsDelete = false
    @State private var asksAge = false

    var body: some View {
        LabeledContent {
            controls
        } label: {
            Text(title)
            Text(caption)
                .foregroundStyle(account.notice == nil ? .secondary : Color.orange)
        }
        .confirmationDialog("Delete your \(Edition.current.name) account?", isPresented: $confirmsDelete) {
            Button("Delete Account", role: .destructive) {
                Task { await account.deleteAccount() }
            }
            .help("Delete the account and everything the server keeps for it")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deleteMessage)
        }
        .sheet(isPresented: $asksAge) {
            AccountAgeSheet(status: account.ageStatus,
                            answer: { account.answerAge(birthMonth: $0.month, year: $0.year) },
                            close: { asksAge = false }) {
                AppleSignInButton(account: account)
            }
        }
        .onAppear(perform: account.refreshAgeStatus)
        // The sheet goes once Apple's sign-in takes over.
        .onChange(of: account.phase) { _, phase in
            if phase != .signedOut { asksAge = false }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch account.phase {
        case .signedOut where account.ageStatus == .unanswered:
            Button("Sign In…") { asksAge = true }
                .help("Sign in with your Apple Account to sync your pet across your Macs")
        case .signedOut where account.ageStatus != .passed:
            // Too young: the caption says when signing in opens.
            EmptyView()
        case .signedOut, .signingIn:
            AppleSignInButton(account: account)
                .frame(width: 160, height: 28)
                .disabled(account.phase == .signingIn)
                .opacity(account.phase == .signingIn ? 0.5 : 1)
                .help("Sign in with your Apple Account to sync your pet across your Macs")
        case .signedIn, .deleting:
            HStack(spacing: 8) {
                Button("Sign Out", action: account.signOut)
                    .help("Stop syncing on this Mac. Your pet and progress stay here.")
                Button("Delete Account…", role: .destructive) { confirmsDelete = true }
                    .help("Delete the account and its synced data from the server")
            }
            .disabled(account.phase == .deleting)
        }
    }

    private var title: String {
        switch account.phase {
        case .signedOut, .signingIn: "Account"
        case .signedIn, .deleting: account.name ?? "Signed in with Apple"
        }
    }

    private var caption: String {
        if let notice = account.notice { return notice }
        switch account.phase {
        case .signedOut:
            if case .tooYoung(let until) = account.ageStatus { return AccountAgeText.tooYoung(until: until) }
            return "Sync your pet, points and streaks across your Macs."
        case .signingIn: return "Signing in…"
        case .deleting: return "Deleting your account…"
        case .signedIn:
            if account.isSyncing { return "Syncing…" }
            guard let date = account.lastSyncedAt else { return "Not synced yet" }
            return "Last synced \(Self.relative(date, now: Date()))"
        }
    }

    /// What Delete Account removes, in the confirmation, as Apple asks.
    static let deleteMessage = """
        This deletes your account and everything the server keeps for it: \
        the synced copy of your pet and points, your friend code, friends and parties. \
        Your pet stays on this Mac. This can't be undone.
        """

    /// "just now" for the first minute, then "4 min ago", "2 hr. ago".
    static func relative(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Apple's Sign in with Apple button, which signs `account` in: the native
/// sheet where the build has the entitlement, Apple's web page elsewhere.
struct AppleSignInButton: View {
    @ObservedObject var account: SyncStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch account.signInMethod {
        case .native:
            SignInWithAppleButton(.signIn) { request in
                // The name greets the user; no email is asked for or kept.
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                signIn(with: result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        case .web:
            WebSignInWithAppleButton(style: colorScheme == .dark ? .white : .black) {
                Task { await account.signInOnWeb() }
            }
            // The style is fixed when the button is made.
            .id(colorScheme)
        }
    }

    private func signIn(with result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                account.appleSignInFailed()
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = credential.fullName
                .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                .flatMap { $0.isEmpty ? nil : $0 }
            Task { await account.signIn(identityToken: token, authorizationCode: code, name: name) }
        case .failure(let error):
            // Cancelling is a choice, not an error.
            if (error as? ASAuthorizationError)?.code != .canceled { account.appleSignInFailed() }
        }
    }
}

/// Apple's Sign in with Apple button for the web flow: the same look as the
/// native `SignInWithAppleButton`, which only starts the native sheet, with
/// an action of our own.
private struct WebSignInWithAppleButton: NSViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeNSView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: style)
        button.target = context.coordinator
        button.action = #selector(Coordinator.press)
        return button
    }

    func updateNSView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}
