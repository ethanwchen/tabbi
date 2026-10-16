//! Updates through the official updater plugin: it reads `latest.json` from
//! the GitHub release, checks the installer's Ed25519 signature against the
//! public key in `tauri.conf.json` (a tampered build is refused) and runs the
//! per-user NSIS installer in passive mode.
//!
//! A check contacts GitHub, so Tabbi checks only when the user asks (the tray
//! item or the About button), or at launch once the user has turned on
//! Check automatically in Settings > About. That choice is off by default
//! and lives in `updater.json` in the app's config folder.

use crate::error::{HostError, HostResult};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{AppHandle, Manager};
use tauri_plugin_updater::{Update, UpdaterExt};

const SETTINGS_FILE: &str = "updater.json";

/// The update found by the last check, kept for the install that follows,
/// and whether the tray asked Settings to check as it opens.
#[derive(Default)]
pub struct Updates {
    found: Mutex<Option<Update>>,
    requested: AtomicBool,
}

/// What the About page shows about a newer build.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    version: String,
    notes: Option<String>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdaterSettings {
    #[serde(default)]
    check_automatically: bool,
}

fn failure(error: impl std::fmt::Display) -> HostError {
    HostError::new("network", error.to_string())
}

fn settings_path(app: &AppHandle) -> HostResult<std::path::PathBuf> {
    app.path()
        .app_config_dir()
        .map(|dir| dir.join(SETTINGS_FILE))
        .map_err(|error| HostError::new("io", error.to_string()))
}

fn read_settings(app: &AppHandle) -> UpdaterSettings {
    settings_path(app)
        .ok()
        .and_then(|path| std::fs::read(path).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

async fn check(app: &AppHandle) -> HostResult<Option<UpdateInfo>> {
    let update = app
        .updater()
        .map_err(failure)?
        .check()
        .await
        .map_err(failure)?;
    let info = update.as_ref().map(|update| UpdateInfo {
        version: update.version.clone(),
        notes: update.body.clone(),
    });
    *app.state::<Updates>().found.lock().expect("updates lock") = update;
    Ok(info)
}

/// Looks for a newer build; null when this one is the latest.
#[tauri::command]
pub async fn update_check(app: AppHandle) -> HostResult<Option<UpdateInfo>> {
    check(&app).await
}

/// Downloads and installs the update the last check found, then restarts
/// into it. The plugin refuses a download whose signature does not verify.
#[tauri::command]
pub async fn update_install(app: AppHandle) -> HostResult<()> {
    let update = app
        .state::<Updates>()
        .found
        .lock()
        .expect("updates lock")
        .take()
        .ok_or_else(|| HostError::new("invalid", "no update was found to install"))?;
    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(failure)?;
    app.restart();
}

#[tauri::command(async)]
pub fn update_auto_check(app: AppHandle) -> bool {
    read_settings(&app).check_automatically
}

#[tauri::command(async)]
pub fn update_set_auto_check(app: AppHandle, on: bool) -> HostResult<()> {
    let path = settings_path(&app)?;
    let io = |error: std::io::Error| HostError::new("io", error.to_string());
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(io)?;
    }
    let text = serde_json::to_vec(&UpdaterSettings {
        check_automatically: on,
    })
    .map_err(|error| HostError::new("io", error.to_string()))?;
    std::fs::write(path, text).map_err(io)
}

/// True once after the tray's Check for Updates, so the About page that
/// opens for it runs the check.
#[tauri::command]
pub fn update_take_request(app: AppHandle) -> bool {
    app.state::<Updates>()
        .requested
        .swap(false, Ordering::SeqCst)
}

/// The tray's Check for Updates: Settings opens at About and checks there,
/// where the user sees the answer and can install.
pub fn request_check(app: &AppHandle) {
    app.state::<Updates>()
        .requested
        .store(true, Ordering::SeqCst);
}

/// At launch, only when the user turned on Check automatically: a newer
/// build is announced with a toast, and installing waits for the user.
pub fn check_at_launch(app: &AppHandle) {
    if !read_settings(app).check_automatically {
        return;
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        if let Ok(Some(info)) = check(&app).await {
            let _ = crate::notify::notify(
                app,
                format!("Tabbi {} is available", info.version),
                "Open Settings > About to install it.".to_owned(),
            );
        }
    });
}
