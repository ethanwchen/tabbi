//! Named JSON documents on disk: durable data under `%APPDATA%\Tabbi` and
//! caches under `%LOCALAPPDATA%\Tabbi`.
//!
//! A name is `document` or `folder/document`, from a small safe charset, so the
//! UI can never reach outside the two roots. Writes are atomic (a temp file,
//! flushed to disk, then renamed over the old one), so a crash or a power cut
//! leaves either the old document or the new one, never half of each.
//! Everything here works on plain paths, so `cargo test` covers it in a temp
//! folder; demo and snapshot runs never get here, they use the UI's mock host.

use crate::error::{HostError, HostResult};
use serde::Deserialize;
use serde_json::Value;
use std::fs;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Manager};

/// The folder both roots use, the product name.
const FOLDER: &str = "Tabbi";
const EXTENSION: &str = ".json";
const MAX_SEGMENT: usize = 64;

/// Device names Windows reserves in every folder, with or without an extension.
const RESERVED: [&str; 4] = ["con", "prn", "aux", "nul"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Area {
    /// Roaming app data: settings, tasks, the pet, anything the user would miss.
    Durable,
    /// Local app data: anything that can be fetched or rebuilt again.
    Cache,
}

pub struct Storage {
    durable: PathBuf,
    cache: PathBuf,
}

fn invalid(name: &str) -> HostError {
    HostError::new(
        "invalidName",
        format!("\"{name}\" is not a document name (letters, digits, . _ -, one folder level)"),
    )
}

fn io(action: &str, error: std::io::Error) -> HostError {
    HostError::new("io", format!("could not {action}: {error}"))
}

/// One path segment: 1 to 64 of `A-Z a-z 0-9 . _ -`, starting with a letter
/// or digit (so never `.`, `..` or a hidden temp file), not ending in a dot
/// (Windows drops it), with no `..` anywhere and no reserved device name.
pub fn valid_segment(segment: &str) -> bool {
    let bytes = segment.as_bytes();
    let Some(&first) = bytes.first() else {
        return false;
    };
    if bytes.len() > MAX_SEGMENT
        || !first.is_ascii_alphanumeric()
        || segment.ends_with('.')
        || segment.contains("..")
        || !bytes
            .iter()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
    {
        return false;
    }
    let stem = segment
        .split('.')
        .next()
        .unwrap_or(segment)
        .to_ascii_lowercase();
    let device = RESERVED.contains(&stem.as_str())
        || ((stem.starts_with("com") || stem.starts_with("lpt"))
            && stem.len() == 4
            && stem.as_bytes()[3].is_ascii_digit());
    !device
}

/// Splits `folder/document` or `document` into its checked parts.
pub fn parse_name(name: &str) -> HostResult<(Option<&str>, &str)> {
    let parts: Vec<&str> = name.split('/').collect();
    match parts.as_slice() {
        [document] if valid_segment(document) => Ok((None, document)),
        [folder, document] if valid_segment(folder) && valid_segment(document) => {
            Ok((Some(folder), document))
        }
        _ => Err(invalid(name)),
    }
}

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

impl Storage {
    pub fn new(durable: PathBuf, cache: PathBuf) -> Self {
        Self { durable, cache }
    }

    /// The real roots: `%APPDATA%\Tabbi` and `%LOCALAPPDATA%\Tabbi`.
    pub fn for_app(app: &AppHandle) -> tauri::Result<Self> {
        let paths = app.path();
        Ok(Self::new(
            paths.data_dir()?.join(FOLDER),
            paths.local_data_dir()?.join(FOLDER),
        ))
    }

    fn root(&self, area: Area) -> &Path {
        match area {
            Area::Durable => &self.durable,
            Area::Cache => &self.cache,
        }
    }

    /// The file a checked name maps to.
    pub fn path(&self, area: Area, name: &str) -> HostResult<PathBuf> {
        let (folder, document) = parse_name(name)?;
        let mut path = self.root(area).to_path_buf();
        if let Some(folder) = folder {
            path.push(folder);
        }
        path.push(format!("{document}{EXTENSION}"));
        Ok(path)
    }

    /// The document, or `None` when it was never written.
    pub fn read(&self, area: Area, name: &str) -> HostResult<Option<Value>> {
        let path = self.path(area, name)?;
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(io("read the document", error)),
        };
        serde_json::from_slice(&bytes).map(Some).map_err(|error| {
            HostError::new("corrupt", format!("{name} is not valid JSON: {error}"))
        })
    }

    pub fn write(&self, area: Area, name: &str, value: &Value) -> HostResult<()> {
        let path = self.path(area, name)?;
        let folder = path.parent().expect("a document path has a folder");
        fs::create_dir_all(folder).map_err(|error| io("create the folder", error))?;
        let bytes = serde_json::to_vec_pretty(value)
            .map_err(|error| HostError::new("invalid", error.to_string()))?;
        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .expect("a document path has a file name");
        /* A leading dot keeps temp files out of `list` and apart from any document name. */
        let temp = folder.join(format!(
            ".{file_name}.{}.{}.tmp",
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let result = write_atomically(&temp, &path, &bytes);
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result
    }

    /// Every document directly in the area's root (`folder` is `None`) or in
    /// one folder, as full names that `read` accepts, sorted.
    pub fn list(&self, area: Area, folder: Option<&str>) -> HostResult<Vec<String>> {
        let mut dir = self.root(area).to_path_buf();
        if let Some(folder) = folder {
            if !valid_segment(folder) {
                return Err(invalid(folder));
            }
            dir.push(folder);
        }
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(io("list the folder", error)),
        };
        let mut names: Vec<String> = entries
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_ok_and(|t| t.is_file()))
            .filter_map(|entry| entry.file_name().into_string().ok())
            .filter_map(|file| file.strip_suffix(EXTENSION).map(str::to_owned))
            .filter(|stem| valid_segment(stem))
            .map(|stem| match folder {
                Some(folder) => format!("{folder}/{stem}"),
                None => stem,
            })
            .collect();
        names.sort();
        Ok(names)
    }

    /// Removes a document; false when there was nothing to remove.
    pub fn delete(&self, area: Area, name: &str) -> HostResult<bool> {
        let path = self.path(area, name)?;
        match fs::remove_file(&path) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
            Err(error) => Err(io("delete the document", error)),
        }
    }
}

fn write_atomically(temp: &Path, path: &Path, bytes: &[u8]) -> HostResult<()> {
    let mut file = fs::File::create(temp).map_err(|error| io("create a temp file", error))?;
    file.write_all(bytes)
        .and_then(|()| file.sync_all())
        .map_err(|error| io("write the document", error))?;
    drop(file);
    /*
     * Rename replaces the old document in one step. An antivirus scan or the
     * search indexer can hold the target open for a moment, so retry briefly.
     */
    let mut attempt = 0;
    loop {
        match fs::rename(temp, path) {
            Ok(()) => return Ok(()),
            Err(error) if attempt < 4 && error.kind() == ErrorKind::PermissionDenied => {
                attempt += 1;
                thread::sleep(Duration::from_millis(25 * attempt));
            }
            Err(error) => return Err(io("replace the document", error)),
        }
    }
}

#[tauri::command(async)]
pub fn storage_read(app: AppHandle, area: Area, name: String) -> HostResult<Option<Value>> {
    app.state::<Storage>().read(area, &name)
}

#[tauri::command(async)]
pub fn storage_write(app: AppHandle, area: Area, name: String, value: Value) -> HostResult<()> {
    app.state::<Storage>().write(area, &name, &value)
}

#[tauri::command(async)]
pub fn storage_list(app: AppHandle, area: Area, folder: Option<String>) -> HostResult<Vec<String>> {
    app.state::<Storage>().list(area, folder.as_deref())
}

#[tauri::command(async)]
pub fn storage_delete(app: AppHandle, area: Area, name: String) -> HostResult<bool> {
    app.state::<Storage>().delete(area, &name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// A fresh pair of roots in the temp folder, removed when dropped.
    struct TempStorage {
        base: PathBuf,
        storage: Storage,
    }

    impl TempStorage {
        fn new(label: &str) -> Self {
            let base = std::env::temp_dir()
                .join(format!("tabbi-storage-test-{label}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&base);
            let storage = Storage::new(base.join("roaming"), base.join("local"));
            Self { base, storage }
        }
    }

    impl Drop for TempStorage {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.base);
        }
    }

    #[test]
    fn names_allow_one_folder_level_of_safe_segments() {
        assert_eq!(parse_name("settings").unwrap(), (None, "settings"));
        assert_eq!(
            parse_name("Activity/2026-10-15").unwrap(),
            (Some("Activity"), "2026-10-15")
        );
        assert_eq!(
            parse_name("planner.v2_backup").unwrap(),
            (None, "planner.v2_backup")
        );
        assert!(valid_segment(&"a".repeat(64)));
        for bad in [
            "",
            "/",
            "a/",
            "/a",
            "a/b/c",
            "..",
            ".",
            "../secrets",
            "a/../b",
            "a..b",
            ".hidden",
            "trailing.",
            "-dash-first",
            "back\\slash",
            "C:evil",
            "space name",
            "tab\tname",
            "caf\u{e9}",
            "CON",
            "nul.json",
            "Com1",
            "lpt9.txt",
            &"a".repeat(65),
        ] {
            assert!(parse_name(bad).is_err(), "{bad:?} must be rejected");
        }
        assert!(
            valid_segment("console"),
            "only exact device names are reserved"
        );
        assert!(valid_segment("com10"));
        assert_eq!(parse_name("../x").unwrap_err().code, "invalidName");
    }

    #[test]
    fn documents_map_to_json_files_under_their_area() {
        let storage = Storage::new(PathBuf::from("R"), PathBuf::from("L"));
        assert_eq!(
            storage.path(Area::Durable, "Activity/day").unwrap(),
            Path::new("R").join("Activity").join("day.json")
        );
        assert_eq!(
            storage.path(Area::Cache, "calendar").unwrap(),
            Path::new("L").join("calendar.json")
        );
    }

    #[test]
    fn write_read_list_and_delete_round_trip() {
        let temp = TempStorage::new("round-trip");
        let s = &temp.storage;
        assert_eq!(s.read(Area::Durable, "settings").unwrap(), None);
        assert!(s.list(Area::Durable, None).unwrap().is_empty());
        assert!(s.list(Area::Durable, Some("Activity")).unwrap().is_empty());

        let doc = json!({ "schemaVersion": 2, "tasks": ["read", "review"] });
        s.write(Area::Durable, "settings", &doc).unwrap();
        s.write(Area::Durable, "Activity/2026-10-15", &json!([]))
            .unwrap();
        s.write(Area::Durable, "Activity/2026-10-14", &json!([1]))
            .unwrap();
        s.write(Area::Cache, "calendar", &json!(null)).unwrap();

        assert_eq!(s.read(Area::Durable, "settings").unwrap(), Some(doc));
        assert_eq!(
            s.read(Area::Cache, "calendar").unwrap(),
            Some(Value::Null),
            "a stored null is not a missing document"
        );
        assert_eq!(
            s.read(Area::Cache, "settings").unwrap(),
            None,
            "areas are separate"
        );
        assert_eq!(s.list(Area::Durable, None).unwrap(), vec!["settings"]);
        assert_eq!(
            s.list(Area::Durable, Some("Activity")).unwrap(),
            vec!["Activity/2026-10-14", "Activity/2026-10-15"]
        );

        assert!(s.delete(Area::Durable, "Activity/2026-10-14").unwrap());
        assert!(!s.delete(Area::Durable, "Activity/2026-10-14").unwrap());
        assert_eq!(
            s.list(Area::Durable, Some("Activity")).unwrap(),
            vec!["Activity/2026-10-15"]
        );
        assert!(s.list(Area::Durable, Some("..")).is_err());
    }

    #[test]
    fn a_write_replaces_the_whole_document_and_leaves_no_temp_files() {
        let temp = TempStorage::new("replace");
        let s = &temp.storage;
        s.write(
            Area::Durable,
            "pet",
            &json!({ "name": "a much longer name than the next one" }),
        )
        .unwrap();
        s.write(Area::Durable, "pet", &json!({ "name": "Mo" }))
            .unwrap();
        assert_eq!(
            s.read(Area::Durable, "pet").unwrap(),
            Some(json!({ "name": "Mo" }))
        );
        let files: Vec<String> = fs::read_dir(temp.base.join("roaming"))
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        assert_eq!(files, vec!["pet.json"]);
    }

    #[test]
    fn list_skips_temp_files_folders_and_foreign_files() {
        let temp = TempStorage::new("list");
        let s = &temp.storage;
        s.write(Area::Durable, "kept", &json!(1)).unwrap();
        let root = temp.base.join("roaming");
        fs::write(root.join(".kept.json.1.0.tmp"), b"{").unwrap();
        fs::write(root.join("notes.txt"), b"x").unwrap();
        fs::write(root.join("bad name.json"), b"{}").unwrap();
        fs::create_dir_all(root.join("Folder.json")).unwrap();
        assert_eq!(s.list(Area::Durable, None).unwrap(), vec!["kept"]);
    }

    #[test]
    fn a_damaged_document_is_reported_not_returned() {
        let temp = TempStorage::new("corrupt");
        let s = &temp.storage;
        s.write(Area::Durable, "planner", &json!({})).unwrap();
        fs::write(s.path(Area::Durable, "planner").unwrap(), b"{\"tasks\": [").unwrap();
        assert_eq!(
            s.read(Area::Durable, "planner").unwrap_err().code,
            "corrupt"
        );
    }

    #[test]
    fn invalid_names_never_touch_the_disk() {
        let temp = TempStorage::new("invalid");
        let s = &temp.storage;
        assert_eq!(
            s.write(Area::Durable, "../escape", &json!(1))
                .unwrap_err()
                .code,
            "invalidName"
        );
        assert!(!temp.base.join("escape.json").exists());
        assert!(s.read(Area::Cache, "a/b/c").is_err());
        assert!(s.delete(Area::Cache, "").is_err());
    }
}
