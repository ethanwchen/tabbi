import Combine
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

    public init(
        settings: AnyPublisher<AppSettings, Never>,
        currentSettings: @escaping () -> AppSettings,
        isRecordingHotkey: AnyPublisher<Bool, Never>,
        hotkeyRegistered: @escaping (Bool) -> Void,
        preview: AnyPublisher<TickerItem?, Never>,
        previewVisible: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.currentSettings = currentSettings
        self.isRecordingHotkey = isRecordingHotkey
        self.hotkeyRegistered = hotkeyRegistered
        self.preview = preview
        self.previewVisible = previewVisible
    }
}
