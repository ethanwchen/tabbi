//! Opens a link in the user's default browser, or a Windows Settings page.
//!
//! The UI asks for this when the user clicks a meeting link, a playlist, the
//! Suggest page, Sign in with Apple, or "Open Windows Settings". Only https
//! links and a short list of Settings pages are opened; anything else (a
//! file, a script, another app's scheme) is refused, so a crafted link in a
//! calendar feed or a chat answer can never start a program.

use crate::error::{HostError, HostResult};
use tauri_plugin_http::reqwest::Url;

/// The Windows Settings pages Tabbi points people to.
const SETTINGS_PAGES: [&str; 3] = [
    /* Notifications and Do not disturb, which Windows does not let apps switch. */
    "ms-settings:notifications",
    "ms-settings:quiethours",
    /* Taskbar settings, where tray icons are pinned. */
    "ms-settings:taskbar",
];

const MAX_LENGTH: usize = 4096;

fn refused(message: impl Into<String>) -> HostError {
    HostError::new("blocked", message)
}

/// The exact text to hand to the shell, once it is known to be safe to open.
pub fn openable(text: &str) -> HostResult<String> {
    let text = text.trim();
    if text.len() > MAX_LENGTH {
        return Err(refused("the link is too long"));
    }
    if let Some(page) = SETTINGS_PAGES
        .iter()
        .find(|page| text.eq_ignore_ascii_case(page))
    {
        return Ok((*page).to_owned());
    }
    let url = Url::parse(text).map_err(|_| HostError::new("invalid", "not a valid link"))?;
    if url.scheme() != "https" {
        return Err(refused("only https links open from Tabbi"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(refused("links with a user name or password are not opened"));
    }
    if url.host_str().is_none_or(str::is_empty) {
        return Err(refused("the link has no host"));
    }
    Ok(url.into())
}

/// Opens an https link in the default browser, or an allowed Settings page.
#[tauri::command]
pub fn open_url(url: String) -> HostResult<()> {
    let target = openable(&url)?;
    shell_open(&target)
}

#[cfg(windows)]
fn shell_open(target: &str) -> HostResult<()> {
    use windows::Win32::UI::Shell::ShellExecuteW;
    use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    use windows::core::{HSTRING, w};

    let target = HSTRING::from(target);
    /* ShellExecute reports success as a value above 32. */
    let result = unsafe { ShellExecuteW(None, w!("open"), &target, None, None, SW_SHOWNORMAL) };
    if result.0 as isize > 32 {
        Ok(())
    } else {
        Err(HostError::new("failed", "Windows could not open the link"))
    }
}

#[cfg(not(windows))]
fn shell_open(_target: &str) -> HostResult<()> {
    Err(HostError::new("failed", "opening links needs Windows"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn https_links_open_as_written() {
        assert_eq!(
            openable("https://meet.google.com/abc-defg-hij").unwrap(),
            "https://meet.google.com/abc-defg-hij"
        );
        assert_eq!(
            openable("  https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6?si=1  ").unwrap(),
            "https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6?si=1"
        );
    }

    #[test]
    fn only_the_listed_settings_pages_open() {
        assert_eq!(
            openable("ms-settings:notifications").unwrap(),
            "ms-settings:notifications"
        );
        assert_eq!(
            openable("MS-SETTINGS:Taskbar").unwrap(),
            "ms-settings:taskbar"
        );
        assert!(openable("ms-settings:privacy-webcam").is_err());
        assert!(openable("ms-settings:").is_err());
    }

    #[test]
    fn everything_else_is_refused() {
        for bad in [
            "http://example.com",
            "file:///C:/Windows/System32/calc.exe",
            "C:\\Windows\\System32\\calc.exe",
            "javascript:alert(1)",
            "tabbi://open",
            "steam://run/440",
            "ms-msdt:/id",
            "search-ms:query=x",
            "https://user:pw@example.com",
            "https://",
            "not a link",
            "",
        ] {
            assert!(openable(bad).is_err(), "{bad:?} must be refused");
        }
        assert!(openable(&format!("https://example.com/{}", "a".repeat(5000))).is_err());
    }
}
