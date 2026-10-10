import Combine
import Foundation
import TabbiKitCore

/// The app state `NotchController` follows: the user's settings, the hotkey
/// recorder, and the closed notch's live preview. Publishers and closures
/// keep TabbiKit free of the app's settings store and ticker.
@MainActor
public struct NotchInputs {
    /// Emits the current settings on subscribe and then every change.
    public var settings: AnyPublisher<AppSettings, Never>
    /// The settings as they are right now, read on each pointer move.
    public var currentSettings: () -> AppSettings
    /// True while Settings records a new shortcut, so the old one is paused.
    public var isRecordingHotkey: AnyPublisher<Bool, Never>
    /// Reports whether the global shortcut could be registered.
    public var hotkeyRegistered: (Bool) -> Void
    /// The item beside the closed notch; nil keeps the notch plain black.
    public var preview: AnyPublisher<TickerItem?, Never>
    /// Tells the preview whether it can be seen, so it only ticks while closed.
    public var previewVisible: (Bool) -> Void
    /// Shows the next live activity beside the closed notch (a swipe down or
    /// a middle-click) and returns whether the preview changed.
    public var cyclePreview: () -> Bool
    /// True while the app's `NotchContent.takeover` should fill the notch:
    /// the notch opens on it and stays open until it ends.
    public var takeover: AnyPublisher<Bool, Never>

    public init(
        settings: AnyPublisher<AppSettings, Never>,
        currentSettings: @escaping () -> AppSettings,
        isRecordingHotkey: AnyPublisher<Bool, Never>,
        hotkeyRegistered: @escaping (Bool) -> Void,
        preview: AnyPublisher<TickerItem?, Never>,
        previewVisible: @escaping (Bool) -> Void,
        cyclePreview: @escaping () -> Bool = { false },
        takeover: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
    ) {
        self.settings = settings
        self.currentSettings = currentSettings
        self.isRecordingHotkey = isRecordingHotkey
        self.hotkeyRegistered = hotkeyRegistered
        self.preview = preview
        self.previewVisible = previewVisible
        self.cyclePreview = cyclePreview
        self.takeover = takeover
    }
}
