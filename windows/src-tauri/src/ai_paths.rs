//! Where the AI command line tools and their usage logs live: the Claude Code
//! and Codex data folders, and the `claude`, `codex` and `gemini` executables.
//! Port of the Mac's `AIExecutableLocator` lookup order: the
//! `TABBI_<TOOL>_PATH` override, then `%USERPROFILE%\.local\bin` (where the
//! native Claude Code installer puts `claude.exe`), then `PATH`. Running a
//! tool is a later feature.
//!
//! The tools' usage logs are read here too, for the AI Usage tab, and only
//! here: `ai_logs_list` walks `%USERPROFILE%\.claude\projects` or
//! `%USERPROFILE%\.codex\sessions` for `.jsonl` files, and `ai_log_read`
//! hands back a capped slice of one of them. Every path is checked against
//! the tool's own folder, nothing is ever written, and the two folders are
//! the whole reach of these commands.

use crate::error::{HostError, HostResult};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub const TOOLS: [&str; 3] = ["claude", "codex", "gemini"];

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiPaths {
    /// `%USERPROFILE%\.claude`, when it exists.
    pub claude_home: Option<String>,
    /// `%USERPROFILE%\.codex`, when it exists.
    pub codex_home: Option<String>,
    pub claude: Option<String>,
    pub codex: Option<String>,
    pub gemini: Option<String>,
}

/// The file names a tool installs as on Windows: a native `.exe`, or the
/// `.cmd` shim npm writes for Node tools (Codex and Gemini CLI).
pub fn file_names(tool: &str) -> [String; 2] {
    [format!("{tool}.exe"), format!("{tool}.cmd")]
}

/// The environment variable that points at a tool and overrides discovery,
/// such as `TABBI_CODEX_PATH`.
pub fn override_variable(tool: &str) -> String {
    format!("TABBI_{}_PATH", tool.to_ascii_uppercase())
}

/// The folders to search, most specific first. Relative `PATH` entries are
/// skipped, so a tool is never picked up from whatever folder Tabbi started in.
pub fn search_dirs(home: Option<&Path>, path: Option<&std::ffi::OsStr>) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(home) = home {
        dirs.push(home.join(".local").join("bin"));
    }
    if let Some(path) = path {
        dirs.extend(std::env::split_paths(path).filter(|dir| dir.is_absolute()));
    }
    dirs
}

/// The first existing executable for `tool`: the override when it names a
/// file, then each folder in order, trying every file name in each folder.
pub fn locate(
    tool: &str,
    override_path: Option<&Path>,
    dirs: &[PathBuf],
    is_file: impl Fn(&Path) -> bool,
) -> Option<PathBuf> {
    if let Some(path) = override_path.filter(|path| is_file(path)) {
        return Some(path.to_path_buf());
    }
    let names = file_names(tool);
    dirs.iter()
        .flat_map(|dir| names.iter().map(move |name| dir.join(name)))
        .find(|candidate| is_file(candidate))
}

fn home() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .filter(|home| home.is_absolute())
}

fn existing_dir(path: PathBuf) -> Option<String> {
    path.is_dir().then(|| path.to_string_lossy().into_owned())
}

pub fn lookup() -> AiPaths {
    let home = home();
    let dirs = search_dirs(home.as_deref(), std::env::var_os("PATH").as_deref());
    let find = |tool: &str| {
        let override_path = std::env::var_os(override_variable(tool)).map(PathBuf::from);
        locate(tool, override_path.as_deref(), &dirs, Path::is_file)
            .map(|path| path.to_string_lossy().into_owned())
    };
    AiPaths {
        claude_home: home.as_ref().and_then(|h| existing_dir(h.join(".claude"))),
        codex_home: home.as_ref().and_then(|h| existing_dir(h.join(".codex"))),
        claude: find(TOOLS[0]),
        codex: find(TOOLS[1]),
        gemini: find(TOOLS[2]),
    }
}

/// Looks on disk, so it runs off the main thread.
#[tauri::command(async)]
pub fn ai_paths() -> AiPaths {
    lookup()
}

/// Whose usage logs: Claude Code's transcripts or Codex's session rollouts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LogTool {
    Claude,
    Codex,
}

/// One usage log the walk found, mirrored by `AiLogFile` in `src/host/host.ts`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogFile {
    pub path: String,
    pub size: u64,
    /// The file's creation time in 100 ns ticks, as a decimal string: it
    /// changes when the file is replaced, which the usage scanner compares
    /// (the Mac uses the inode), and a string keeps all 64 bits in JSON.
    pub identity: String,
    /// Last modified, in seconds since 1970.
    pub modified: f64,
}

/// The most bytes one `ai_log_read` returns; a longer file is read over
/// several scans, which carry on from where the last one stopped.
pub const READ_CAP: usize = 16 * 1024 * 1024;

const LOG_EXTENSION: &str = "jsonl";

/// Where a tool keeps its logs under the user's profile: Claude Code's
/// `.claude\projects` and Codex's `.codex\sessions`.
pub fn logs_root(home: &Path, tool: LogTool) -> PathBuf {
    match tool {
        LogTool::Claude => home.join(".claude").join("projects"),
        LogTool::Codex => home.join(".codex").join("sessions"),
    }
}

fn blocked(message: impl Into<String>) -> HostError {
    HostError::new("blocked", message)
}

fn io(action: &str, error: std::io::Error) -> HostError {
    HostError::new("io", format!("could not {action}: {error}"))
}

fn is_log(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case(LOG_EXTENSION))
}

/// A dot file or folder: temp files and editor leftovers, never a log.
fn is_hidden(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| n.starts_with('.'))
}

#[cfg(windows)]
fn creation_ticks(metadata: &fs::Metadata) -> u64 {
    use std::os::windows::fs::MetadataExt;
    metadata.creation_time()
}

#[cfg(not(windows))]
fn creation_ticks(metadata: &fs::Metadata) -> u64 {
    metadata
        .created()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_nanos() as u64 / 100)
        .unwrap_or(0)
}

fn modified_seconds(metadata: &fs::Metadata) -> f64 {
    metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// Every `.jsonl` file under `root`, at any depth, hidden entries skipped,
/// sorted by path. A missing root is an empty list, not an error: the tool
/// may simply never have run.
pub fn list_logs(root: &Path) -> HostResult<Vec<LogFile>> {
    let mut files = Vec::new();
    if !root.is_dir() {
        return Ok(files);
    }
    let mut pending = vec![root.to_path_buf()];
    while let Some(dir) = pending.pop() {
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            /* A folder that vanished or is locked mid-walk only costs its files this scan. */
            Err(_) => continue,
        };
        for entry in entries.filter_map(Result::ok) {
            let path = entry.path();
            if is_hidden(&path) {
                continue;
            }
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            if metadata.is_dir() {
                pending.push(path);
            } else if metadata.is_file() && is_log(&path) {
                files.push(LogFile {
                    path: path.to_string_lossy().into_owned(),
                    size: metadata.len(),
                    identity: creation_ticks(&metadata).to_string(),
                    modified: modified_seconds(&metadata),
                });
            }
        }
    }
    files.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(files)
}

/// `path` as a log file inside `root`, or why not. Both sides are
/// canonicalized, so `..`, junctions and symbolic links can't lead out of
/// the tool's folder, and only `.jsonl` files pass.
pub fn checked_log_path(root: &Path, path: &Path) -> HostResult<PathBuf> {
    let root =
        fs::canonicalize(root).map_err(|_| blocked("the tool's log folder does not exist"))?;
    let file = fs::canonicalize(path).map_err(|_| blocked("not a log file"))?;
    if !file.starts_with(&root) || !is_log(&file) || is_hidden(&file) {
        return Err(blocked("not a log file in the tool's folder"));
    }
    Ok(file)
}

/// The bytes of `path` from `offset`, at most `cap` of them.
pub fn read_log(path: &Path, offset: u64, cap: usize) -> HostResult<Vec<u8>> {
    let mut file = fs::File::open(path).map_err(|error| io("open the log", error))?;
    let length = file
        .metadata()
        .map_err(|error| io("read the log", error))?
        .len();
    if offset >= length {
        return Ok(Vec::new());
    }
    file.seek(SeekFrom::Start(offset))
        .map_err(|error| io("read the log", error))?;
    let wanted = usize::try_from(length - offset)
        .unwrap_or(usize::MAX)
        .min(cap);
    let mut bytes = Vec::with_capacity(wanted);
    file.take(wanted as u64)
        .read_to_end(&mut bytes)
        .map_err(|error| io("read the log", error))?;
    Ok(bytes)
}

fn tool_root(tool: LogTool) -> HostResult<PathBuf> {
    home()
        .map(|home| logs_root(&home, tool))
        .ok_or_else(|| blocked("no user profile folder"))
}

/// Walks the tool's log folder, so it runs off the main thread.
#[tauri::command(async)]
pub fn ai_logs_list(tool: LogTool) -> HostResult<Vec<LogFile>> {
    list_logs(&tool_root(tool)?)
}

/// Reads one listed log from `offset`; the raw bytes travel as a binary
/// body rather than a JSON array.
#[tauri::command(async)]
pub fn ai_log_read(tool: LogTool, path: String, offset: u64) -> HostResult<tauri::ipc::Response> {
    let file = checked_log_path(&tool_root(tool)?, Path::new(&path))?;
    read_log(&file, offset, READ_CAP).map(tauri::ipc::Response::new)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

    /// A fresh profile folder in the temp folder, removed when dropped.
    struct TempHome {
        base: PathBuf,
    }

    impl TempHome {
        fn new(label: &str) -> Self {
            let base = std::env::temp_dir()
                .join(format!("tabbi-ai-logs-test-{label}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&base);
            fs::create_dir_all(&base).unwrap();
            Self { base }
        }

        fn write(&self, relative: &str, text: &str) -> PathBuf {
            let path = self.base.join(relative);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(&path, text).unwrap();
            path
        }
    }

    impl Drop for TempHome {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.base);
        }
    }

    #[test]
    fn the_log_roots_follow_the_tools_own_folders() {
        let home = Path::new(r"C:\Users\me");
        assert_eq!(
            logs_root(home, LogTool::Claude),
            PathBuf::from(r"C:\Users\me\.claude\projects")
        );
        assert_eq!(
            logs_root(home, LogTool::Codex),
            PathBuf::from(r"C:\Users\me\.codex\sessions")
        );
    }

    #[test]
    fn listing_walks_every_depth_for_jsonl_and_skips_hidden_and_other_files() {
        let home = TempHome::new("list");
        home.write(".claude/projects/a/one.jsonl", "{\"a\":1}\n");
        home.write(".claude/projects/a/deep/two.JSONL", "{}\n{}\n");
        home.write(".claude/projects/notes.txt", "not a log");
        home.write(".claude/projects/.hidden/three.jsonl", "{}");
        home.write(".claude/projects/a/.tmp.jsonl", "{}");
        let root = logs_root(&home.base, LogTool::Claude);
        let files = list_logs(&root).unwrap();
        let names: Vec<&str> = files
            .iter()
            .map(|f| Path::new(&f.path).file_name().unwrap().to_str().unwrap())
            .collect();
        assert_eq!(names, vec!["two.JSONL", "one.jsonl"]);
        assert_eq!(files[1].size, 8);
        assert!(files[0].modified > 1.0e9, "modified is seconds since 1970");
        assert!(
            files[0].identity.parse::<u64>().is_ok(),
            "the identity is a decimal 64-bit integer"
        );
        assert!(
            list_logs(&logs_root(&home.base, LogTool::Codex))
                .unwrap()
                .is_empty(),
            "a tool that never ran has no logs"
        );
    }

    #[test]
    fn reading_starts_at_the_offset_and_stops_at_the_cap() {
        let home = TempHome::new("read");
        let path = home.write(".codex/sessions/2026/one.jsonl", "0123456789");
        assert_eq!(read_log(&path, 0, READ_CAP).unwrap(), b"0123456789");
        assert_eq!(read_log(&path, 4, READ_CAP).unwrap(), b"456789");
        assert_eq!(read_log(&path, 4, 3).unwrap(), b"456");
        assert_eq!(read_log(&path, 10, READ_CAP).unwrap(), b"");
        assert_eq!(read_log(&path, 99, READ_CAP).unwrap(), b"");
    }

    #[test]
    fn only_a_jsonl_file_inside_the_tools_folder_may_be_read() {
        let home = TempHome::new("checked");
        let inside = home.write(".codex/sessions/one.jsonl", "{}");
        let outside = home.write(".codex/config.toml", "model = \"x\"");
        let other_tool = home.write(".claude/projects/one.jsonl", "{}");
        let hidden = home.write(".codex/sessions/.draft.jsonl", "{}");
        let root = logs_root(&home.base, LogTool::Codex);
        assert!(checked_log_path(&root, &inside).is_ok());
        let dotted = root.join("..").join("sessions").join("one.jsonl");
        assert!(
            checked_log_path(&root, &dotted).is_ok(),
            "a dotted path that stays inside is fine"
        );
        for bad in [
            outside,
            other_tool,
            hidden,
            root.join("..").join("config.toml"),
            root.join("missing.jsonl"),
        ] {
            let error = checked_log_path(&root, &bad).unwrap_err();
            assert_eq!(error.code, "blocked", "{}", bad.display());
        }
        assert_eq!(
            checked_log_path(
                &logs_root(&home.base, LogTool::Claude).join("nope"),
                &inside
            )
            .unwrap_err()
            .code,
            "blocked",
            "a missing root refuses everything"
        );
    }

    fn files(list: &[&str]) -> impl Fn(&Path) -> bool {
        let set: Vec<PathBuf> = list.iter().map(PathBuf::from).collect();
        move |path: &Path| set.iter().any(|p| p == path)
    }

    #[test]
    fn the_override_variable_follows_the_mac_name() {
        assert_eq!(override_variable("claude"), "TABBI_CLAUDE_PATH");
        assert_eq!(override_variable("gemini"), "TABBI_GEMINI_PATH");
    }

    #[test]
    fn local_bin_comes_first_and_relative_path_entries_are_skipped() {
        let path = OsString::from(r"C:\Windows;.\tools;;C:\Users\me\AppData\Roaming\npm");
        let dirs = search_dirs(Some(Path::new(r"C:\Users\me")), Some(&path));
        assert_eq!(
            dirs,
            vec![
                PathBuf::from(r"C:\Users\me\.local\bin"),
                PathBuf::from(r"C:\Windows"),
                PathBuf::from(r"C:\Users\me\AppData\Roaming\npm"),
            ]
        );
        assert!(search_dirs(None, None).is_empty());
    }

    #[test]
    fn tools_are_found_in_folder_order_as_exe_or_npm_shim() {
        let dirs = vec![
            PathBuf::from(r"C:\Users\me\.local\bin"),
            PathBuf::from(r"C:\Users\me\AppData\Roaming\npm"),
        ];
        let disk = files(&[
            r"C:\Users\me\.local\bin\claude.exe",
            r"C:\Users\me\AppData\Roaming\npm\claude.cmd",
            r"C:\Users\me\AppData\Roaming\npm\codex.cmd",
        ]);
        assert_eq!(
            locate("claude", None, &dirs, &disk),
            Some(PathBuf::from(r"C:\Users\me\.local\bin\claude.exe"))
        );
        assert_eq!(
            locate("codex", None, &dirs, &disk),
            Some(PathBuf::from(r"C:\Users\me\AppData\Roaming\npm\codex.cmd"))
        );
        assert_eq!(locate("gemini", None, &dirs, &disk), None);
    }

    #[test]
    fn an_override_wins_only_when_it_names_a_file() {
        let dirs = vec![PathBuf::from(r"C:\bin")];
        let disk = files(&[r"C:\bin\claude.exe", r"D:\tools\claude.exe"]);
        assert_eq!(
            locate(
                "claude",
                Some(Path::new(r"D:\tools\claude.exe")),
                &dirs,
                &disk
            ),
            Some(PathBuf::from(r"D:\tools\claude.exe"))
        );
        assert_eq!(
            locate("claude", Some(Path::new(r"D:\missing.exe")), &dirs, &disk),
            Some(PathBuf::from(r"C:\bin\claude.exe")),
            "a stale override falls back to discovery"
        );
    }
}
