//! Start with Windows, through the official autostart plugin (a per-user
//! `Run` registry value, no admin prompt). It is off by default and only these
//! commands change it, which the UI calls from the user's own switch in
//! onboarding or Settings; nothing in the host turns it on by itself.

use crate::error::{HostError, HostResult};
use tauri::AppHandle;
use tauri_plugin_autostart::ManagerExt;

fn failure(error: impl std::fmt::Display) -> HostError {
    HostError::new("autostart", error.to_string())
}

#[tauri::command(async)]
pub fn autostart_enable(app: AppHandle) -> HostResult<()> {
    app.autolaunch().enable().map_err(failure)
}

#[tauri::command(async)]
pub fn autostart_disable(app: AppHandle) -> HostResult<()> {
    app.autolaunch().disable().map_err(failure)
}

#[tauri::command(async)]
pub fn autostart_is_enabled(app: AppHandle) -> HostResult<bool> {
    app.autolaunch().is_enabled().map_err(failure)
}
