//! Where the AI command line tools and their usage logs live: the Claude Code
//! and Codex data folders, and the `claude`, `codex` and `gemini` executables.
//! Port of the Mac's `AIExecutableLocator` lookup order: the
//! `TABBI_<TOOL>_PATH` override, then `%USERPROFILE%\.local\bin` (where the
//! native Claude Code installer puts `claude.exe`), then `PATH`. Only the
//! lookup lives here; running a tool is a later feature.

use serde::Serialize;
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

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
