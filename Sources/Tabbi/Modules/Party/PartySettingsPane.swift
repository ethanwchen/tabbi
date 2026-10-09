import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Party: the profile friends see, going invisible, the
    /// friends server, and deleting the Party data. `account` is the Apple
    /// account, which owns that data once signed in.
    @MainActor static func party(store: PartyStore, account: SyncStore) -> SettingsPane {
        SettingsPane(id: "party", title: "Party", symbol: "person.2",
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
            LabeledContent("Name") {
                TextField("Name", text: $name, prompt: Text(store.state.profile?.name ?? "Your name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: fieldWidth)
                    .focused($focused, equals: .name)
                    .onSubmit(commitName)
                    .help("The name friends see, up to \(PartySettings.maxNameLength) characters")
            }
            LabeledContent("Friend code") {
                HStack(spacing: 8) {
                    Text(friendCodeText)
                        .font(store.state.friendCode == nil ? .body : .body.monospaced())
                        .foregroundStyle(store.state.friendCode == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                    Button("Copy", action: copyFriendCode)
                        .disabled(store.state.friendCode == nil)
                        .help("Copy your friend code to share it")
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Footer("Friends see this name and the pet you dress in the Closet. Share your code so they can add you.")
        }
    }

    private var friendCodeText: String {
        store.state.friendCode.map { PartyStyle.display(code: $0) } ?? "Not connected yet"
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
                Text("Go invisible")
                Text("Friends see you as offline. Your study minutes still count.")
            }
            .help("Hide your status from friends")
        } header: {
            Text("Privacy")
        } footer: {
            Footer("Only your name, pet, study status and minutes are shared. Nothing about your cards, decks or what you study ever leaves your Mac.")
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
                Text(store.blocked == nil ? emptyBlockedText : "No one is blocked.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Blocked")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Footer("Blocked people can't see you, add you or join your parties. To block or report someone, right-click them in Party.")
                Link(SupportContact.reportLine, destination: SupportContact.mailURL)
                    .font(.callout)
                    .help("Email the \(Edition.current.name) team about a person or a problem")
            }
        }
    }

    /// Before the list arrives: still connecting, or offline.
    private var emptyBlockedText: String {
        if case .connected = store.state.connection { return "Loading…" }
        return "Connect to the friends server to see who you blocked."
    }

    // MARK: Server

    private var serverSection: some View {
        Section {
            LabeledContent("Server") {
                HStack(spacing: 8) {
                    if !store.settings.usesDefaultServer {
                        Button {
                            server = ""
                            commitServer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Use the default \(Edition.current.name) server")
                    }
                    TextField("Server", text: $server, prompt: Text("Default server"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: fieldWidth)
                        .focused($focused, equals: .server)
                        .onSubmit(commitServer)
                        .help("A friends server address. Leave empty for \(PartyServer.productionURL.host ?? "the default server").")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusView
                Spacer(minLength: 8)
                Button("Reconnect") { store.retry() }
                    .disabled(!canReconnect)
                    .help("Try the server again now")
            }
        } header: {
            Text("Friends server")
        } footer: {
            Footer("Friends only see each other on the same server. Change it only to run your own.")
        }
    }

    private var canReconnect: Bool {
        guard !store.isDemo else { return false }
        switch store.state.connection {
        case .invalidServer, .connecting: return false
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
            return ("Can't use this server", message, "exclamationmark.triangle.fill", .orange)
        case .connecting:
            return ("Connecting…", host, "", .secondary)
        case .unreachable(.banned):
            return ("Not available", PartyError.banned.message, "hand.raised.fill", .secondary)
        case .unreachable(let error):
            return ("Can't reach the server", error.message, "wifi.slash", .orange)
        case .connected:
            if let error = store.state.staleError {
                return ("Connection lost", error.message, "wifi.slash", .orange)
            }
            return ("Connected", host, "checkmark.circle.fill", .green)
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
                    Text("Your Party data")
                    Text("It belongs to your Apple Account. Delete Account in General removes it.")
                }
            } else {
                LabeledContent {
                    Button("Delete…", role: .destructive) { confirmsDelete = true }
                        .disabled(store.pending != nil || store.isDemo)
                        .help("Delete your friend code, friends and parties from the friends server")
                } label: {
                    Text("Delete my Party data")
                    Text(store.pending == .deleteData ? "Deleting…" : store.deletionNotice
                        ?? "Removes your profile, friends and parties from the server.")
                }
            }
        } header: {
            Text("Your data")
        }
        .confirmationDialog("Delete your Party data?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive, action: store.deletePartyData)
                .help("Delete your Party data from the friends server")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deleteMessage)
        }
    }

    static let deleteMessage = "This deletes your friend code, your profile and pet as friends see them, your friends list, your party memberships and your study streak from the friends server. Friends will no longer see you. Your pet and points stay on this Mac. If Party stays on, you get a new friend code."

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
            Button(isUnblocking ? "Unblocking…" : "Unblock", action: unblock)
                .disabled(!isEnabled)
                .help("Let \(user.name) find you again. You won't be friends until one of you adds the other.")
        } label: {
            Text(user.name)
            Text(detail)
        }
    }

    private var detail: String {
        guard let since = user.since else { return "With \(user.petName)" }
        return "With \(user.petName), blocked \(since.formatted(.relative(presentation: .named)))"
    }
}

/// Explanatory text under a grouped section, aligned with the section's rows.
private struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
