import SwiftUI
import TabbiKitCore

/// Party's whole setup: a name and a pet. Start saves both and Party
/// registers by itself; the sheet then shows the friend code with a big
/// Copy button, so the next thing the user does is share it.
struct PartySetupView: View {
    @State var name: String
    @State var species: PetSpecies
    let state: PartyConnectionState
    let start: (_ name: String, _ species: PetSpecies) -> Void
    let copy: (String) -> Void
    /// Tries the server again now, from the "can't connect" result.
    let retry: () -> Void
    let close: () -> Void
    /// Whether Start was pressed in this sheet, so it shows the result
    /// rather than the form.
    @State private var started = false
    @FocusState private var nameFocused: Bool

    init(name: String, species: PetSpecies, state: PartyConnectionState,
         start: @escaping (String, PetSpecies) -> Void, copy: @escaping (String) -> Void,
         retry: @escaping () -> Void, close: @escaping () -> Void, started: Bool = false) {
        _name = State(initialValue: name)
        _species = State(initialValue: species)
        _started = State(initialValue: started)
        self.state = state
        self.start = start
        self.copy = copy
        self.retry = retry
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ConnectionSheetHeader(kind: .party, light: started ? state.connectionStatus.light : nil,
                                  title: isReady ? PartySetup.readyTitle : PartySetup.title,
                                  message: isReady ? PartySetup.readyIntro : PartySetup.intro)
            if started {
                result
            } else {
                form
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(duration: 0.3), value: started)
        .animation(.spring(duration: 0.3), value: state)
    }

    private var isReady: Bool {
        guard started, case .connected = state else { return false }
        return true
    }

    // MARK: Before Start

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(PartySetup.nameLabel)
                    .fontWeight(.medium)
                TextField(PartySetup.nameLabel, text: $name, prompt: Text(PartySetup.namePlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(submit)
                    .help("The name friends see, up to \(PartySettings.maxNameLength) letters")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(PartySetup.petLabel)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    ForEach(PetSpecies.allCases, id: \.self) { option in
                        PetChoice(species: option, isSelected: species == option) { species = option }
                    }
                }
                Text(PartySetup.petNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 8)
                Button("Not now", action: close)
                    .keyboardShortcut(.cancelAction)
                    .help("Close this. You can set up Party any time.")
                Button(PartySetup.start, action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(PartySetup.name(from: name) == nil)
                    .help(PartySetup.name(from: name) == nil ? "Type a name first" : "Save your name and pet and join Party")
            }
        }
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard let cleaned = PartySetup.name(from: name) else { return }
        start(cleaned, species)
        started = true
    }

    // MARK: After Start

    @ViewBuilder private var result: some View {
        let status = state.connectionStatus
        switch state {
        case .connected(let code):
            FriendCodeCard(code: code, copy: copy)
            footer(done: true)
        case .offline:
            Label("\(status.headline). \(status.detail)", systemImage: "wifi.exclamationmark")
                .font(.callout)
            HStack(spacing: 12) {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                    .help("Close this. Party keeps trying by itself.")
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Try to reach Party again now")
            }
        case .connecting, .notSetUp:
            Label {
                Text("Joining Party. This takes a second.")
                    .foregroundStyle(.secondary)
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout)
            footer(done: false)
        }
    }

    private func footer(done: Bool) -> some View {
        HStack {
            Spacer()
            Button(done ? "Done" : "Close", action: close)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help(done ? "Close this" : "Close this. Party keeps trying by itself.")
        }
    }
}

/// A big pet button for the setup sheet.
private struct PetChoice: View {
    let species: PetSpecies
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Image(systemName: species == .cat ? "cat.fill" : "dog.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(height: 32)
                Text(species.displayName)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: isSelected)
        .help("Study with a \(species.displayName.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The friend code, large, with one big Copy button.
struct FriendCodeCard: View {
    let code: String
    let copy: (String) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your friend code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                copy(code)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(minWidth: 96)
            }
            .controlSize(.large)
            .help("Copy your friend code to send to a friend")
        }
        .padding(16)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
