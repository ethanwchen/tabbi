//! Small Windows shell services for Settings: the official file dialog for a
//! kit file, opening a web page or a Windows Settings page in the user's
//! default handler, opening one of the few apps Connections knows, Windows'
//! toast setting for Tabbi, and the Windows version. Each one is narrowly
//! scoped (one .json file of a kit's size, https and ms-settings links only,
//! three named executables), so the UI never gets a general shell.

use crate::error::{HostError, HostResult};
use serde::Serialize;
use tauri::{AppHandle, Manager};
use windows::UI::Notifications::{NotificationSetting, ToastNotificationManager};
use windows::Wdk::System::SystemServices::RtlGetVersion;
use windows::Win32::Foundation::HWND;
use windows::Win32::System::SystemInformation::OSVERSIONINFOW;
use windows::Win32::UI::Controls::Dialogs::{
    GetOpenFileNameW, OFN_EXPLORER, OFN_FILEMUSTEXIST, OFN_NOCHANGEDIR, OFN_PATHMUSTEXIST,
    OPENFILENAMEW,
};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
use windows::core::{HSTRING, PCWSTR};

/// The largest kit file the UI accepts (KitLimits.maxFileBytes), plus room
/// for the dialog to hand over a file the UI then refuses with its own words.
const MAX_KIT_BYTES: u64 = 256 * 1024;

/// A kit file the user picked: its name and its text.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KitFilePick {
    file_name: String,
    text: String,
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

/// The official Open dialog, limited to one .json file, owned by the
/// Settings window so it is modal to it. `None` when the user cancels.
fn pick_json(owner: Option<HWND>, title: &str) -> Option<std::path::PathBuf> {
    let mut path = vec![0u16; 32 * 1024];
    let filter = wide("Kit (*.json)\0*.json\0\0");
    let title = wide(title);
    let extension = wide("json");
    let mut options = OPENFILENAMEW {
        lStructSize: std::mem::size_of::<OPENFILENAMEW>() as u32,
        hwndOwner: owner.unwrap_or_default(),
        lpstrFilter: PCWSTR(filter.as_ptr()),
        nFilterIndex: 1,
        lpstrFile: windows::core::PWSTR(path.as_mut_ptr()),
        nMaxFile: path.len() as u32,
        lpstrTitle: PCWSTR(title.as_ptr()),
        Flags: OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR,
        lpstrDefExt: PCWSTR(extension.as_ptr()),
        ..Default::default()
    };
    /* The struct and every buffer it points at outlive the call. */
    let picked = unsafe { GetOpenFileNameW(&mut options) }.as_bool();
    if !picked {
        return None;
    }
    let end = path.iter().position(|&c| c == 0).unwrap_or(path.len());
    Some(std::path::PathBuf::from(String::from_utf16_lossy(
        &path[..end],
    )))
}

/// Reads the picked kit file, refusing anything but a small text file.
pub fn read_kit(path: &std::path::Path) -> HostResult<KitFilePick> {
    let size = std::fs::metadata(path)
        .map_err(|error| HostError::new("io", error.to_string()))?
        .len();
    if size > MAX_KIT_BYTES {
        return Err(HostError::new(
            "tooLarge",
            format!("a kit file is at most {MAX_KIT_BYTES} bytes"),
        ));
    }
    let bytes = std::fs::read(path).map_err(|error| HostError::new("io", error.to_string()))?;
    let text = String::from_utf8(bytes)
        .map_err(|_| HostError::new("invalid", "a kit file must be UTF-8 text"))?;
    let file_name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "kit.json".into());
    Ok(KitFilePick { file_name, text })
}

#[tauri::command(async)]
pub fn dialog_pick_kit(app: AppHandle) -> HostResult<Option<KitFilePick>> {
    let owner = app
        .get_webview_window("settings")
        .and_then(|window| window.hwnd().ok())
        .map(|hwnd| HWND(hwnd.0));
    match pick_json(owner, "Import a Kit") {
        None => Ok(None),
        Some(path) => read_kit(&path).map(Some),
    }
}

/// Whether a link may be opened in the user's default handler: a web page
/// over https, or a page of Windows Settings. Nothing else, so the UI can
/// never launch a program or a file through this command.
pub fn is_openable_url(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    if lower.starts_with("ms-settings:") {
        return url.len() < 200
            && url[12..].chars().all(|c| {
                c.is_ascii_alphanumeric() || c == '-' || c == ':' || c == '?' || c == '='
            });
    }
    if !(lower.starts_with("https://") || lower.starts_with("mailto:")) {
        return false;
    }
    url.len() < 2048 && !url.chars().any(|c| c.is_control() || c.is_whitespace())
}

fn shell_open(file: &str) -> HostResult<()> {
    let file = wide(file);
    let verb = wide("open");
    let result = unsafe {
        ShellExecuteW(
            None,
            PCWSTR(verb.as_ptr()),
            PCWSTR(file.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        )
    };
    /* ShellExecute returns a value above 32 on success, an error code otherwise. */
    if result.0 as usize > 32 {
        Ok(())
    } else {
        Err(HostError::new(
            "io",
            format!("ShellExecute failed with {}", result.0 as usize),
        ))
    }
}

#[tauri::command(async)]
pub fn open_url(url: String) -> HostResult<()> {
    if !is_openable_url(&url) {
        return Err(HostError::new(
            "refused",
            "only https and ms-settings links open",
        ));
    }
    shell_open(&url)
}

/// The executable each app Connections may open goes by, found through the
/// shell (App Paths and PATH), never a path the UI supplies.
pub fn app_executable(app: &str) -> Option<&'static str> {
    match app {
        "anki" => Some("anki.exe"),
        "spotify" => Some("spotify.exe"),
        "powershell" => Some("powershell.exe"),
        _ => None,
    }
}

#[tauri::command(async)]
pub fn open_app(app: String) -> HostResult<()> {
    let executable = app_executable(&app)
        .ok_or_else(|| HostError::new("refused", format!("{app} is not an app Tabbi opens")))?;
    shell_open(executable)
}

/// Windows' toast setting for Tabbi, as the UI names it (`NotificationSetting` in host.ts).
pub fn setting_name(setting: NotificationSetting) -> &'static str {
    match setting {
        NotificationSetting::Enabled => "enabled",
        NotificationSetting::DisabledForApplication => "disabledForApplication",
        NotificationSetting::DisabledForUser => "disabledForUser",
        NotificationSetting::DisabledByGroupPolicy => "disabledByGroupPolicy",
        _ => "disabledByManifest",
    }
}

#[tauri::command(async)]
pub fn notifications_setting(app: AppHandle) -> HostResult<&'static str> {
    /* The same application id the notification plugin shows toasts under. */
    let id = HSTRING::from(app.config().identifier.as_str());
    let notifier = ToastNotificationManager::CreateToastNotifierWithId(&id)
        .map_err(|error| HostError::new("notification", error.to_string()))?;
    let setting = notifier
        .Setting()
        .map_err(|error| HostError::new("notification", error.to_string()))?;
    Ok(setting_name(setting))
}

/// The Windows version as "10.0.26200", from the kernel rather than the
/// compatibility-shimmed GetVersionEx.
pub fn system_version() -> String {
    let mut info = OSVERSIONINFOW {
        dwOSVersionInfoSize: std::mem::size_of::<OSVERSIONINFOW>() as u32,
        ..Default::default()
    };
    /* RtlGetVersion only writes the struct it is given. */
    let status = unsafe { RtlGetVersion(&mut info) };
    if status.0 != 0 {
        return "unknown".into();
    }
    format!(
        "{}.{}.{}",
        info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_https_mailto_and_settings_links_open() {
        assert!(is_openable_url(
            "https://tabbinotch.com/suggest?version=0.1.0"
        ));
        assert!(is_openable_url("ms-settings:notifications"));
        assert!(is_openable_url("mailto:support@tabbinotch.com"));
        assert!(!is_openable_url("http://example.com"));
        assert!(!is_openable_url("file:///C:/Windows/notepad.exe"));
        assert!(!is_openable_url("C:\\Windows\\notepad.exe"));
        assert!(!is_openable_url("https://example.com/a b"));
        assert!(!is_openable_url("ms-settings:notifications; cmd"));
    }

    #[test]
    fn apps_are_a_fixed_list() {
        assert_eq!(app_executable("anki"), Some("anki.exe"));
        assert_eq!(app_executable("powershell"), Some("powershell.exe"));
        assert_eq!(app_executable("cmd"), None);
    }

    #[test]
    fn toast_settings_are_named_for_the_ui() {
        assert_eq!(setting_name(NotificationSetting::Enabled), "enabled");
        assert_eq!(
            setting_name(NotificationSetting::DisabledByGroupPolicy),
            "disabledByGroupPolicy"
        );
        assert_eq!(setting_name(NotificationSetting(99)), "disabledByManifest");
    }

    #[test]
    fn a_kit_file_is_read_as_text_and_capped() {
        let dir = std::env::temp_dir().join(format!("tabbi-kit-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("deep-work.json");
        std::fs::write(&path, "{\"id\":\"deep-work\"}").unwrap();
        let pick = read_kit(&path).unwrap();
        assert_eq!(pick.file_name, "deep-work.json");
        assert_eq!(pick.text, "{\"id\":\"deep-work\"}");
        std::fs::write(&path, vec![b' '; MAX_KIT_BYTES as usize + 1]).unwrap();
        assert_eq!(read_kit(&path).unwrap_err().code, "tooLarge");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_windows_version_has_three_parts() {
        let version = system_version();
        assert_eq!(version.split('.').count(), 3);
    }
}
