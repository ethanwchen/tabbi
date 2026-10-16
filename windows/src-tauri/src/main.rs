// No console window behind the island in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tabbi_windows_lib::run();
}
