import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Party: the profile friends see, going invisible, the
    /// friends server, and deleting the Party data. `account` is the Apple
    /// account, which owns that data once signed in.
    @MainActor static func party(store: PartyStore, account: SyncStore) -> SettingsPane {
        SettingsPane(id: "party", title: String(localized: "Party", bundle: .tabbi), symbol: "person.2",
                     view: AnyView(PartySettingsPane(store: store, account: account)))
    }
}

/// Settings › Party. Text fields edit a draft and commit on Return or when
/// they lose focus, so a half-typed server address never reconnects; the
/// invisible toggle applies at once. Every edit goes through
/// `PartyStore.update(_:)`, which saves it and syncs the server.
struct PartySettingsPane: View {
    @ObservedObject var store: PartyStore
    @ObservedObject var account: SyncStore
    @State private var name = ""
    @State private var confirmsDelete = false
    @State private var server = ""
    @FocusState private var focused: Field?

    private enum Field { case name, server }

    /// Every field (and the controls sharing its column) uses this width,
    /// so the rows line up.
    private let fieldWidth: CGFloat = 240

    var body: some View {
        Form {
            profileSection
            privacySection
            blockedSection
            serverSection
            dataSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: height)
        .motion(Motion.content, value: height)
        .onAppear {
            store.loadBlocked()
            name = store.settings.name
            server = store.settings.serverText
        }
        .onDisappear {
            // Closing the window doesn't end editing; keep what was typed.
            commitName()
            commitServer()
        }
        .onChange(of: focused) { old, _ in
            if old == .name { commitName() }
            if old == .server { commitServer() }
        }
    }

    /// The grouped form doesn't report its content height, so add up the
    /// Blocked rows, which come and go; the window follows the pane's size.
    private var height: CGFloat {
        let rows = max(store.blocked?.count ?? 0, 1)
        return 790 + CGFloat(rows - 1) * 44
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            LabeledContent(String(localized: "Name", bundle: .tabbi)) {
                TextField(String(localized: "Name", bundle: .tabbi), text: $name, prompt: Text(store.state.profile?.name ?? String(localized: "Your name", bundle: .tabbi)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: fieldWidth)
                    .focused($focused, equals: .name)
                    .onSubmit(commitName)
                    .help(String(localized: "The name friends see, up to \(PartySettings.maxNameLength) characters", bundle: .tabbi))
            }
            LabeledContent(String(localized: "Friend code", bundle: .tabbi)) {
                HStack(spacing: 8) {
                    Text(friendCodeText)
                        .font(store.state.friendCode == nil ? .body : .body.monospaced())
                        .foregroundStyle(store.state.friendCode == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                    Button(String(localized: "Copy", bundle: .tabbi), action: copyFriendCode)
                        .disabled(store.state.friendCode == nil)
                        .help(String(localized: "Copy your friend code to share it", bundle: .tabbi))
                }
            }
        } header: {
            Text("Profile", bundle: .tabbi)
        } footer: {
            if let issue = nameIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            } else {
                SectionFooter(String(localized: "Friends see this name and the pet you dress in the Closet. Share your code so they can add you.", bundle: .tabbi))
            }
        }
    }

    /// What friends can't see, checked as the name is typed: the draft
    /// through the app's filter, the saved name and pet name as the store
    /// knows them (including names the server refused).
    private var nameIssue: String? {
        var refused = store.refusedNames
        if name != store.settings.name {
            refused.remove(.name)
            refused.formUnion(PartySettings(name: name).refusedNames(for: store.pet).intersection(.name))
        }
        return refused.message
    }

    private var friendCodeText: String {
        store.state.friendCode.map { PartyStyle.display(code: $0) } ?? String(localized: "Not connected yet", bundle: .tabbi)
    }

    private func commitName() {
        var settings = store.settings
        settings.name = String(name.prefix(PartySettings.maxNameLength * 2))
        store.update(settings)
        name = settings.name
    }

    private func copyFriendCode() {
        guard let code = store.state.friendCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PartyStyle.display(code: code), forType: .string)
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: invisible) {
                Text("Go invisible", bundle: .tabbi)
                Text("Friends see you as offline. Your study minutes still count.", bundle: .tabbi)
            }
            .help(String(localized: "Hide your status from friends", bundle: .tabbi))
        } header: {
            Text("Privacy", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Only your name, pet, study status and minutes are shared. Nothing about your cards, decks or what you study ever leaves your Mac.", bundle: .tabbi))
        }
    }

    private var invisible: Binding<Bool> {
        Binding(get: { store.settings.invisible },
                set: { value in
                    var settings = store.settings
                    settings.invisible = value
                    store.update(settings)
                })
    }

    // MARK: Blocked

    /// The people I blocked, each with Unblock, and the support address.
    /// Blocking and reporting start from a right-click on someone in Party.
    private var blockedSection: some View {
        Section {
            if let blocked = store.blocked, !blocked.isEmpty {
                ForEach(blocked) { user in
                    BlockedRow(user: user, isUnblocking: store.pending == .unblock(user.code),
                               isEnabled: store.pending == nil) {
                        store.unblock(code: user.code)
                    }
                }
            } else {
                Text(store.blocked == nil ? emptyBlockedText : String(localized: "No one is blocked.", bundle: .tabbi))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Blocked", bundle: .tabbi)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                SectionFooter(String(localized: "Blocked people can't see you, add you or join your parties. To block or report someone, right-click them in Party.", bundle: .tabbi))
                Link(SupportContact.reportLine, destination: SupportContact.mailURL)
                    .font(.callout)
                    .help(String(localized: "Email the \(Edition.current.name) team about a person or a problem", bundle: .tabbi))
            }
        }
    }

    /// Before the list arrives: still connecting, or offline.
    private var emptyBlockedText: String {
        if case .connected = store.state.connection { return String(localized: "Loading…", bundle: .tabbi) }
        return String(localized: "Connect to the friends server to see who you blocked.", bundle: .tabbi)
    }

    // MARK: Server

    private var serverSection: some View {
        Section {
            LabeledContent(String(localized: "Server", bundle: .tabbi)) {
                HStack(spacing: 8) {
                    if !store.settings.usesDefaultServer {
                        Button {
                            server = ""
                            commitServer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Use the default \(Edition.current.name) server", bundle: .tabbi))
                    }
                    TextField(String(localized: "Server", bundle: .tabbi), text: $server, prompt: Text("Default server", bundle: .tabbi))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: fieldWidth)
                        .focused($focused, equals: .server)
                        .onSubmit(commitServer)
                        .help(String(localized: "A friends server address. Leave empty for \(PartyServer.productionURL.host ?? "tabbinotch.com").", bundle: .tabbi))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusView
                Spacer(minLength: 8)
                Button(String(localized: "Reconnect", bundle: .tabbi)) { store.retry() }
                    .disabled(!canReconnect)
                    .help(String(localized: "Try the server again now", bundle: .tabbi))
            }
        } header: {
            Text("Friends server", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Friends only see each other on the same server. Change it only to run your own.", bundle: .tabbi))
        }
    }

    private var canReconnect: Bool {
        guard !store.isDemo else { return false }
        switch store.state.connection {
        case .invalidServer, .ageCheck, .connecting: return false
        case .unreachable, .connected: return true
        }
    }

    private var statusView: some View {
        let status = self.status
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                Text(status.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            if status.symbol.isEmpty {
                Spinner()
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.color)
            }
        }
        .help(status.detail)
    }

    /// The connection as one status row; an empty symbol shows a spinner.
    private var status: (title: String, detail: String, symbol: String, color: Color) {
        let host = store.settings.serverURL?.host ?? ""
        switch store.state.connection {
        case .invalidServer(let message):
            return (String(localized: "Can't use this server", bundle: .tabbi), message, "exclamationmark.triangle.fill", .orange)
        case .ageCheck(nil):
            return (String(localized: "Not joined yet", bundle: .tabbi), String(localized: "Open the Party tab to join.", bundle: .tabbi), "person.crop.circle.badge.questionmark", .secondary)
        case .ageCheck(let until?):
            return (String(localized: "Not available", bundle: .tabbi), String(localized: "Party is for people \(PartyAgeCheck.minimumAge) and older. It opens in \(PartyAgeCheck.opensText(until)).", bundle: .tabbi),
                    "hand.raised.fill", .secondary)
        case .connecting:
            return (String(localized: "Connecting…", bundle: .tabbi), host, "", .secondary)
        case .unreachable(.banned):
            return (String(localized: "Not available", bundle: .tabbi), PartyError.banned.message, "hand.raised.fill", .secondary)
        case .unreachable(let error):
            return (String(localized: "Can't reach the server", bundle: .tabbi), error.message, "wifi.slash", .orange)
        case .connected:
            if let error = store.state.staleError {
                return (String(localized: "Connection lost", bundle: .tabbi), error.message, "wifi.slash", .orange)
            }
            return (String(localized: "Connected", bundle: .tabbi), host, "checkmark.circle.fill", .green)
        }
    }

    // MARK: Your data

    /// Signed out, Party's anonymous identity is all the server keeps, so
    /// it can be deleted here. Signed in, it belongs to the Apple account
    /// and goes with Delete Account in Settings > General.
    private var dataSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Your Party data", bundle: .tabbi)
                    Text("It belongs to your Apple Account. Delete Account in General removes it.", bundle: .tabbi)
                }
            } else {
                LabeledContent {
                    Button(String(localized: "Delete…", bundle: .tabbi), role: .destructive) { confirmsDelete = true }
                        .disabled(store.pending != nil || store.isDemo)
                        .help(String(localized: "Delete your friend code, friends and parties from the friends server", bundle: .tabbi))
                } label: {
                    Text("Delete my Party data", bundle: .tabbi)
                    Text(store.pending == .deleteData ? String(localized: "Deleting…", bundle: .tabbi) : store.deletionNotice
                        ?? String(localized: "Removes your profile, friends and parties from the server.", bundle: .tabbi))
                }
            }
        } header: {
            Text("Your data", bundle: .tabbi)
        }
        .confirmationDialog(String(localized: "Delete your Party data?", bundle: .tabbi), isPresented: $confirmsDelete) {
            Button(String(localized: "Delete", bundle: .tabbi), role: .destructive, action: store.deletePartyData)
                .help(String(localized: "Delete your Party data from the friends server", bundle: .tabbi))
            Button(String(localized: "Cancel", bundle: .tabbi), role: .cancel) {}
        } message: {
            Text(Self.deleteMessage)
        }
    }

    static var deleteMessage: String { String(localized: "This deletes your friend code, your profile and pet as friends see them, your friends list, your party memberships and your study streak from the friends server. Friends will no longer see you. Your pet and points stay on this Mac. If Party stays on, you get a new friend code.", bundle: .tabbi) }

    private func commitServer() {
        var settings = store.settings
        settings.serverText = server.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(settings)
        server = settings.serverText
    }
}

/// Someone on the Blocked list: their name, their pet and when, with Unblock.
private struct BlockedRow: View {
    let user: PartyBlockedUser
    let isUnblocking: Bool
    let isEnabled: Bool
    let unblock: () -> Void

    var body: some View {
        LabeledContent {
            Button(isUnblocking ? String(localized: "Unblocking…", bundle: .tabbi) : String(localized: "Unblock", bundle: .tabbi), action: unblock)
                .disabled(!isEnabled)
                .help(String(localized: "Let \(user.name) find you again. You won't be friends until one of you adds the other.", bundle: .tabbi))
        } label: {
            Text(user.name)
            Text(detail)
        }
    }

    private var detail: String {
        guard let since = user.since else { return String(localized: "With \(user.petName)", bundle: .tabbi) }
        return String(localized: "With \(user.petName), blocked \(since.formatted(.relative(presentation: .named)))", bundle: .tabbi)
    }
}
