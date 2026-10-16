//! The one file Tabbi writes outside its own folders: the weekly recap's
//! share image, saved as a PNG into the user's Pictures folder under a name
//! the UI made. Narrow on purpose: a plain file name (no folders), PNG bytes
//! only, into Pictures only, replacing a file of the same name. The Mac
//! shows a save panel; the Windows host has no dialog plugin, so the image
//! lands in Pictures and the UI says so.

use crate::error::{HostError, HostResult};
use std::fs;
use std::path::{Path, PathBuf};
use windows::Win32::System::Com::CoTaskMemFree;
use windows::Win32::UI::Shell::{FOLDERID_Pictures, KNOWN_FOLDER_FLAG, SHGetKnownFolderPath};

/// Longest file name accepted, well under the file system's limit with the
/// Pictures path in front.
const MAX_NAME: usize = 120;
/// The largest image accepted: a story is 1080 x 1920, far under this.
const MAX_BYTES: usize = 8 * 1024 * 1024;
const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

/// Whether `name` is one plain `.png` file name: no folders, no control
/// characters, none of the characters Windows forbids, not a reserved
/// device name, not ending in a space or dot.
pub fn valid_name(name: &str) -> bool {
    let Some(stem) = name.strip_suffix(".png") else {
        return false;
    };
    if stem.is_empty() || name.chars().count() > MAX_NAME {
        return false;
    }
    if stem.ends_with(' ') || stem.ends_with('.') {
        return false;
    }
    if name.chars().any(|c| {
        c.is_control() || matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|')
    }) {
        return false;
    }
    let base = stem.split('.').next().unwrap_or(stem).to_ascii_uppercase();
    let reserved = matches!(base.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (base.len() == 4
            && (base.starts_with("COM") || base.starts_with("LPT"))
            && base[3..].chars().all(|c| c.is_ascii_digit()));
    !reserved
}

/// Decodes standard base64 (with or without padding); None on any other character.
pub fn decode_base64(text: &str) -> Option<Vec<u8>> {
    fn value(c: u8) -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some((c - b'A') as u32),
            b'a'..=b'z' => Some((c - b'a' + 26) as u32),
            b'0'..=b'9' => Some((c - b'0' + 52) as u32),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let bytes = text.trim_end_matches('=').as_bytes();
    let mut out = Vec::with_capacity(bytes.len() * 3 / 4);
    for chunk in bytes.chunks(4) {
        let mut acc: u32 = 0;
        for (i, &c) in chunk.iter().enumerate() {
            acc |= value(c)? << (18 - 6 * i);
        }
        let count = match chunk.len() {
            4 => 3,
            3 => 2,
            2 => 1,
            _ => return None,
        };
        let parts = [(acc >> 16) as u8, (acc >> 8) as u8, acc as u8];
        out.extend_from_slice(&parts[..count]);
    }
    Some(out)
}

/// Checks the name and the bytes, then says where the file goes under `pictures`.
pub fn destination(pictures: &Path, name: &str, bytes: &[u8]) -> HostResult<PathBuf> {
    if !valid_name(name) {
        return Err(HostError::new(
            "invalidName",
            format!("{name:?} is not a picture file name"),
        ));
    }
    if bytes.len() > MAX_BYTES {
        return Err(HostError::new(
            "tooLarge",
            "the picture is larger than 8 MB",
        ));
    }
    if bytes.len() < PNG_SIGNATURE.len() || bytes[..PNG_SIGNATURE.len()] != PNG_SIGNATURE {
        return Err(HostError::new("invalid", "the picture is not a PNG"));
    }
    Ok(pictures.join(name))
}

/// Writes `bytes` to `path` through a temporary file beside it, so a crash never leaves half a picture.
pub fn write_picture(path: &Path, bytes: &[u8]) -> HostResult<()> {
    let io =
        |action: &str, error: std::io::Error| HostError::new("io", format!("{action}: {error}"));
    if let Some(folder) = path.parent() {
        fs::create_dir_all(folder).map_err(|e| io("create the Pictures folder", e))?;
    }
    let temp = path.with_extension("png.tmp");
    fs::write(&temp, bytes).map_err(|e| io("write the picture", e))?;
    fs::rename(&temp, path).map_err(|e| {
        let _ = fs::remove_file(&temp);
        io("place the picture", e)
    })
}

/// The user's Pictures folder (`FOLDERID_Pictures`), which may be redirected to OneDrive.
fn pictures_folder() -> HostResult<PathBuf> {
    // SAFETY: SHGetKnownFolderPath returns a buffer this function owns and frees.
    unsafe {
        let path = SHGetKnownFolderPath(&FOLDERID_Pictures, KNOWN_FOLDER_FLAG(0), None)
            .map_err(|error| HostError::new("io", format!("no Pictures folder: {error}")))?;
        let text = path
            .to_string()
            .map_err(|error| HostError::new("io", format!("bad Pictures path: {error}")))?;
        CoTaskMemFree(Some(path.0 as *const _));
        Ok(PathBuf::from(text))
    }
}

#[tauri::command(async)]
pub fn picture_save(name: String, png_base64: String) -> HostResult<String> {
    let bytes = decode_base64(&png_base64)
        .ok_or_else(|| HostError::new("invalid", "the picture is not base64"))?;
    let path = destination(&pictures_folder()?, &name, &bytes)?;
    write_picture(&path, &bytes)?;
    Ok(path.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_plain_png_file_names() {
        assert!(valid_name("Tabbi week Oct 5 - 11 (square).png"));
        assert!(!valid_name("week.jpg"));
        assert!(!valid_name("..\\week.png"));
        assert!(!valid_name("sub/week.png"));
        assert!(!valid_name("con.png"));
        assert!(!valid_name("week .png"));
        assert!(!valid_name(".png"));
    }

    #[test]
    fn base64_round_trips_png_bytes() {
        assert_eq!(
            decode_base64("iVBORw0KGgo=").unwrap(),
            PNG_SIGNATURE.to_vec()
        );
        assert_eq!(
            decode_base64("iVBORw0KGgo").unwrap(),
            PNG_SIGNATURE.to_vec()
        );
        assert_eq!(decode_base64("abc$"), None);
    }

    #[test]
    fn only_pngs_go_to_pictures() {
        let pictures = Path::new("C:\\Users\\me\\Pictures");
        let png = [PNG_SIGNATURE.to_vec(), vec![0; 16]].concat();
        assert_eq!(
            destination(pictures, "week.png", &png).unwrap(),
            pictures.join("week.png")
        );
        assert_eq!(
            destination(pictures, "week.png", b"GIF89a")
                .unwrap_err()
                .code,
            "invalid"
        );
        assert_eq!(
            destination(pictures, "week.txt", &png).unwrap_err().code,
            "invalidName"
        );
        assert_eq!(
            destination(pictures, "week.png", &vec![0; MAX_BYTES + 1])
                .unwrap_err()
                .code,
            "tooLarge"
        );
    }

    #[test]
    fn a_picture_is_written_whole_and_replaces_an_older_one() {
        let folder = std::env::temp_dir().join(format!("tabbi-pictures-{}", std::process::id()));
        let path = folder.join("week.png");
        write_picture(&path, b"first").unwrap();
        write_picture(&path, b"second").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"second");
        assert!(!path.with_extension("png.tmp").exists());
        let _ = fs::remove_dir_all(folder);
    }
}
