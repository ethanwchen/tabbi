//! Opens a link in whatever the user set as their browser or mail app:
//! Sign in with Apple's page, the Anki download page, the support address.
//! Only `https` and `mailto` links are opened, so the UI can never start a
//! program or open a file through this command. The rule is pure and
//! tested; the shell call itself is the thin part at the end.
//!
//! Not wired yet: `lib.rs` has to add `mod open;` and `open::open_url` to
//! its `invoke_handler` (both files are owned by another task).

use crate::error::{HostError, HostResult};
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use windows::core::PCWSTR;
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

/// Links longer than this are not something a person was shown.
const MAX_CHARS: usize = 2048;

/// The link as it may be handed to the shell, or why it is refused.
pub fn openable_url(text: &str) -> HostResult<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(HostError::new("invalid", "an empty link"));
    }
    if trimmed.chars().count() > MAX_CHARS {
        return Err(HostError::new("tooLarge", "the link is too long"));
    }
    if trimmed.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return Err(HostError::new("invalid", "the link holds control characters or spaces"));
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.starts_with("https://") && lower.len() > "https://".len() {
        return Ok(trimmed.to_owned());
    }
    if lower.starts_with("mailto:") && lower.len() > "mailto:".len() {
        return Ok(trimmed.to_owned());
    }
    Err(HostError::new("blocked", "only https and mailto links can be opened"))
}

fn wide(text: &str) -> Vec<u16> {
    OsStr::new(text).encode_wide().chain(std::iter::once(0)).collect()
}

#[tauri::command(async)]
pub fn open_url(url: String) -> HostResult<()> {
    let url = openable_url(&url)?;
    let operation = wide("open");
    let target = wide(&url);
    /* ShellExecuteW returns a value above 32 on success, an error code otherwise. */
    let result = unsafe {
        ShellExecuteW(
            None,
            PCWSTR(operation.as_ptr()),
            PCWSTR(target.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        )
    };
    if result.0 as usize > 32 {
        Ok(())
    } else {
        Err(HostError::new("io", format!("the shell could not open the link (code {})", result.0 as usize)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_web_pages_and_mail_links_only() {
        assert_eq!(openable_url("https://apps.ankiweb.net").unwrap(), "https://apps.ankiweb.net");
        assert_eq!(openable_url("  mailto:support@tabbinotch.com ").unwrap(), "mailto:support@tabbinotch.com");
        assert_eq!(openable_url("HTTPS://appleid.apple.com/auth/authorize?x=1").unwrap(), "HTTPS://appleid.apple.com/auth/authorize?x=1");
        assert_eq!(openable_url("http://example.com").unwrap_err().code, "blocked");
        assert_eq!(openable_url("file:///C:/Windows/notepad.exe").unwrap_err().code, "blocked");
        assert_eq!(openable_url("C:\\Windows\\notepad.exe").unwrap_err().code, "blocked");
        assert_eq!(openable_url("https://").unwrap_err().code, "blocked");
        assert_eq!(openable_url("").unwrap_err().code, "invalid");
        assert_eq!(openable_url("https://a.b/c d").unwrap_err().code, "invalid");
        assert_eq!(openable_url("https://a.b/\u{7}").unwrap_err().code, "invalid");
        let long = format!("https://a.b/{}", "x".repeat(MAX_CHARS));
        assert_eq!(openable_url(&long).unwrap_err().code, "tooLarge");
    }
}
