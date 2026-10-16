//! Windows toasts through the official notification plugin. Windows itself
//! holds them back while Do Not Disturb or a focus session is on, so Tabbi
//! never has to check.

use crate::error::{HostError, HostResult};
use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

/// Toasts show a few lines at most; anything longer is a bug in the caller.
const MAX_CHARS: usize = 400;

/// Cleans one line of toast text: control characters become spaces and the
/// ends are trimmed.
pub fn clean(text: &str) -> String {
    text.chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect::<String>()
        .trim()
        .to_owned()
}

/// The title and body a toast shows, or why it cannot be shown.
pub fn toast_text(title: &str, body: &str) -> HostResult<(String, String)> {
    let (title, body) = (clean(title), clean(body));
    if title.is_empty() {
        return Err(HostError::new("invalid", "a notification needs a title"));
    }
    if title.chars().count() > MAX_CHARS || body.chars().count() > MAX_CHARS {
        return Err(HostError::new(
            "tooLarge",
            format!("notification text is longer than {MAX_CHARS} characters"),
        ));
    }
    Ok((title, body))
}

#[tauri::command(async)]
pub fn notify(app: AppHandle, title: String, body: String) -> HostResult<()> {
    let (title, body) = toast_text(&title, &body)?;
    let mut builder = app.notification().builder().title(title);
    if !body.is_empty() {
        builder = builder.body(body);
    }
    builder
        .show()
        .map_err(|error| HostError::new("notification", error.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_is_cleaned_and_a_title_is_required() {
        assert_eq!(
            toast_text("  Break time \n", "Stretch\tyour legs").unwrap(),
            ("Break time".to_owned(), "Stretch your legs".to_owned())
        );
        assert_eq!(
            toast_text("Done", "").unwrap(),
            ("Done".to_owned(), String::new())
        );
        assert_eq!(toast_text(" \r\n", "body").unwrap_err().code, "invalid");
    }

    #[test]
    fn overlong_text_is_refused_rather_than_cut() {
        assert!(toast_text(&"a".repeat(400), &"b".repeat(400)).is_ok());
        assert_eq!(
            toast_text(&"a".repeat(401), "").unwrap_err().code,
            "tooLarge"
        );
        assert_eq!(
            toast_text("t", &"\u{e9}".repeat(401)).unwrap_err().code,
            "tooLarge"
        );
    }
}
