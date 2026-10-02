import AppKit
import Combine
import SwiftUI
import NotchKitCore

/// The first-run "choose a kit" step: shown once, before the user has picked
/// a kit, so each audience starts from tabs that fit them. Like Settings it
/// is a regular system window, not part of the black notch.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private var choice: AnyCancellable?
    /// Set once Continue lands. `$settings` publishes before the new value
    /// is stored, so `settings` can't be read to tell yet.
    private var hasChosen = false

    init(settings: SettingsStore) {
        self.settings = settings
        let host = NSHostingController(rootView: WelcomeView().environmentObject(settings))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to \(Edition.current.name)"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        // Continue records the choice; the window goes away once it lands.
        choice = settings.$settings
            .map(\.hasChosenKit)
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.hasChosen = true
                self?.close()
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Brings the window forward; the app is an accessory, so it activates
    /// itself or the window would open behind the frontmost app.
    func present() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing without Continue keeps the preselected kit, so the window
    /// never comes back to nag.
    func windowWillClose(_ notification: Notification) {
        if !hasChosen, !settings.settings.hasChosenKit {
            settings.chooseKit(settings.settings.kitID)
        }
    }

    /// Renders the window to PNG data for `SnapshotRenderer`, off screen.
    func snapshot() async -> Data? {
        guard let window else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// App icon, a short pitch, one selectable card per kit, and Continue.
private struct WelcomeView: View {
    @EnvironmentObject private var store: SettingsStore
    /// Starts on the edition's kit, e.g. Medicine for StudyNotch.
    @State private var picked: String?

    var body: some View {
        let selection = picked ?? store.settings.kitID
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: Self.appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Welcome to \(Edition.current.name)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Pick a kit to start with. A kit is a set of tabs for the notch; you can switch kits or change tabs any time in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)

            VStack(spacing: 8) {
                ForEach(store.kits.kits) { kit in
                    KitCard(kit: kit, isSelected: kit.id == selection) { picked = kit.id }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HStack {
                Text("Open the notch by clicking it or pressing \(store.settings.hotkey.displayString).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    store.chooseKit(selection)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Start with the \(store.kits[selection]?.name ?? "selected") kit")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 520)
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selection)
    }

    /// The bundle's icon. `swift run` has no bundle, so fall back to the
    /// repo's icon file (the dev and snapshot working directory).
    private static let appIcon: NSImage = Bundle.main.bundleURL.pathExtension == "app"
        ? NSApp.applicationIconImage
        : NSImage(contentsOfFile: "Resources/AppIcon.icns") ?? NSApp.applicationIconImage
}

/// One kit: its symbol, name and summary, and the tabs it turns on.
private struct KitCard: View {
    let kit: KitManifest
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tabs = kit.layout().enabled
        let tint = tabs.first.map { Theme.Palette.accent(for: $0) } ?? .accentColor
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: kit.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 4) {
                    Text(kit.name)
                        .font(.headline)
                    Text(kit.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(tabs) { module in
                            Image(systemName: module.symbol)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.Palette.accent(for: module))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Theme.Palette.accent(for: module).opacity(0.16)))
                                .help(module.title)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : (hovering ? 0.06 : 0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(kit.name): \(tabs.map(\.title).joined(separator: ", "))")
        .onHover { hovering = $0 }
    }
}
