//! What the pet coach samples during a focus phase, the Windows side of the
//! Mac's `CGEventSource.secondsSinceLastEventType` and
//! `NSWorkspace.frontmostApplication`: the seconds since the last keyboard
//! or mouse input (`GetLastInputInfo`, only the time, never the input), and
//! the foreground window's executable name (`Discord.exe`), never its title
//! or what it shows. Nothing is stored here; the UI reads a sample every few
//! seconds while a focus phase runs and not at all otherwise.

use serde::Serialize;
use std::ffi::c_void;
use windows::Win32::System::SystemInformation::GetTickCount64;
use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoachSample {
    pub idle_seconds: f64,
    /// The foreground app's executable name, or None for the desktop or a process that cannot be read.
    pub frontmost: Option<String>,
}

/// Only the handle rights needed to read a process's image name, which every
/// process grants.
const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;

// Kernel32 process queries, declared here rather than through a further
// `windows` crate feature: three plain calls.
#[link(name = "kernel32")]
unsafe extern "system" {
    fn OpenProcess(desired_access: u32, inherit_handle: i32, process_id: u32) -> isize;
    fn QueryFullProcessImageNameW(
        process: isize,
        flags: u32,
        exe_name: *mut u16,
        size: *mut u32,
    ) -> i32;
    fn CloseHandle(handle: isize) -> i32;
}

/// Seconds since the last input, from the tick counts Windows keeps. `now`
/// and `last_input` are milliseconds; a `last_input` from before the 32-bit
/// counter wrapped reads as the longest it can.
pub fn idle_seconds(now_ms: u64, last_input_ms: u32) -> f64 {
    let now32 = (now_ms & 0xFFFF_FFFF) as u32;
    now32.wrapping_sub(last_input_ms) as f64 / 1000.0
}

/// The file name of a full image path, the executable name the coach's app
/// lists match ("C:\\Apps\\Discord\\Discord.exe" is "Discord.exe").
pub fn executable_name(path: &str) -> Option<String> {
    let name = path.rsplit(['\\', '/']).next()?.trim();
    (!name.is_empty()).then(|| name.to_owned())
}

fn last_input_ms() -> Option<u32> {
    let mut info = LASTINPUTINFO {
        cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
        dwTime: 0,
    };
    // SAFETY: `info` is a valid, correctly sized LASTINPUTINFO.
    unsafe { GetLastInputInfo(&mut info).as_bool().then_some(info.dwTime) }
}

fn frontmost_executable() -> Option<String> {
    // SAFETY: plain Win32 queries on the foreground window; a null window or a
    // process that refuses to open yields None.
    unsafe {
        let window = GetForegroundWindow();
        if window.0.is_null() {
            return None;
        }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(window, Some(&mut pid));
        if pid == 0 {
            return None;
        }
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if process == 0 {
            return None;
        }
        let mut buffer = [0u16; 1024];
        let mut size = buffer.len() as u32;
        let ok = QueryFullProcessImageNameW(process, 0, buffer.as_mut_ptr(), &mut size);
        CloseHandle(process);
        if ok == 0 {
            return None;
        }
        let path = String::from_utf16_lossy(&buffer[..size as usize]);
        executable_name(&path)
    }
}

#[tauri::command]
pub fn coach_sample() -> Option<CoachSample> {
    let last = last_input_ms()?;
    // SAFETY: GetTickCount64 has no preconditions.
    let now = unsafe { GetTickCount64() };
    Some(CoachSample {
        idle_seconds: idle_seconds(now, last),
        frontmost: frontmost_executable(),
    })
}

/// Keeps the unused-import lint quiet on builds where the sample is never read.
#[allow(dead_code)]
fn _void(_: *const c_void) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_time_follows_the_tick_count_and_survives_a_wrap() {
        assert_eq!(idle_seconds(10_000, 7_500), 2.5);
        assert_eq!(idle_seconds(0x1_0000_03E8, 0xFFFF_FC18), 2.0);
    }

    #[test]
    fn the_executable_name_is_the_last_path_segment() {
        assert_eq!(
            executable_name("C:\\Users\\Me\\AppData\\Local\\Discord\\Discord.exe").as_deref(),
            Some("Discord.exe")
        );
        assert_eq!(executable_name("steam.exe").as_deref(), Some("steam.exe"));
        assert_eq!(executable_name("C:\\folder\\"), None);
    }
}
