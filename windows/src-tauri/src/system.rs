//! CPU, memory and GPU load for the System tab, sampled once a second (the
//! Mac's `SystemMonitor` interval) and only while the UI asks for it.
//!
//! CPU comes from the PDH counter `\Processor Information(*)\% Processor Time`
//! (every core and the total), GPU from `\GPU Engine(*)\Utilization
//! Percentage` (the busiest 3D engine, summed over the processes using it, the
//! way Task Manager's GPU graph reads), and memory from
//! `GlobalMemoryStatusEx`. Counters are added by their English names so they
//! work on every display language. Turning the raw readings into the values
//! the UI shows is pure and tested below.

use serde::Serialize;
use std::sync::Mutex;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use windows::Win32::System::Performance::{
    PDH_CSTATUS_NEW_DATA, PDH_CSTATUS_VALID_DATA, PDH_FMT_COUNTERVALUE_ITEM_W, PDH_FMT_DOUBLE,
    PDH_HCOUNTER, PDH_HQUERY, PDH_MORE_DATA, PdhAddEnglishCounterW, PdhCloseQuery,
    PdhCollectQueryData, PdhGetFormattedCounterArrayW, PdhOpenQueryW,
};
use windows::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
use windows::core::{PCWSTR, w};

/// The Mac samples once a second.
pub const INTERVAL: Duration = Duration::from_secs(1);

pub const EVENT: &str = "system:stats";

/// CPU load, each value in `0..=1`. Mirrors the Mac's `CPUUsage`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CpuUsage {
    pub total: f64,
    /// One value per logical processor, in processor order.
    pub per_core: Vec<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoryStats {
    pub used_bytes: u64,
    pub total_bytes: u64,
}

/// One reading. A value the machine cannot report is `null`: CPU on the very
/// first reading (rates need two samples), GPU on machines without the GPU
/// counters (some virtual machines and older drivers).
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemStats {
    pub cpu: Option<CpuUsage>,
    pub memory: Option<MemoryStats>,
    /// Busy fraction of the busiest 3D engine, `0..=1`.
    pub gpu: Option<f64>,
}

fn fraction(percent: f64) -> f64 {
    if percent.is_finite() {
        (percent / 100.0).clamp(0.0, 1.0)
    } else {
        0.0
    }
}

/// `"0,3"` (group 0, processor 3) or `"3"`, as a sortable key. `_Total`
/// instances (the machine and each group) are not processors.
fn processor_key(name: &str) -> Option<(u32, u32)> {
    if name.contains("_Total") {
        return None;
    }
    match name.split_once(',') {
        Some((group, index)) => Some((group.trim().parse().ok()?, index.trim().parse().ok()?)),
        None => Some((0, name.trim().parse().ok()?)),
    }
}

/// CPU usage from the `% Processor Time` instances. The total is the
/// counter's own `_Total`, or the mean of the processors when it is missing.
pub fn cpu_usage(items: &[(String, f64)]) -> Option<CpuUsage> {
    let mut cores: Vec<((u32, u32), f64)> = items
        .iter()
        .filter_map(|(name, value)| processor_key(name).map(|key| (key, fraction(*value))))
        .collect();
    if cores.is_empty() {
        return None;
    }
    cores.sort_by_key(|(key, _)| *key);
    let per_core: Vec<f64> = cores.into_iter().map(|(_, value)| value).collect();
    let total = items
        .iter()
        .find(|(name, _)| name == "_Total")
        .map(|(_, value)| fraction(*value))
        .unwrap_or_else(|| per_core.iter().sum::<f64>() / per_core.len() as f64);
    Some(CpuUsage { total, per_core })
}

/// The engine part of a `GPU Engine` instance name such as
/// `pid_1234_luid_0x00000000_0x0000D1B5_phys_0_eng_0_engtype_3D`, for 3D
/// engines only: `luid_0x00000000_0x0000D1B5_phys_0_eng_0`.
fn engine_3d(name: &str) -> Option<&str> {
    let engine = name.strip_suffix("_engtype_3D")?;
    let start = engine.find("luid_")?;
    Some(&engine[start..])
}

/// GPU usage from the `Utilization Percentage` instances: each 3D engine's
/// load summed over the processes using it, then the busiest engine.
pub fn gpu_usage(items: &[(String, f64)]) -> Option<f64> {
    let mut engines: Vec<(&str, f64)> = Vec::new();
    for (name, value) in items {
        let Some(engine) = engine_3d(name) else {
            continue;
        };
        let value = if value.is_finite() {
            value.max(0.0)
        } else {
            0.0
        };
        match engines.iter_mut().find(|(e, _)| *e == engine) {
            Some((_, sum)) => *sum += value,
            None => engines.push((engine, value)),
        }
    }
    engines
        .into_iter()
        .map(|(_, sum)| fraction(sum))
        .reduce(f64::max)
}

/// Memory in use: everything installed that is not available.
pub fn memory_stats(total: u64, available: u64) -> Option<MemoryStats> {
    (total > 0).then(|| MemoryStats {
        used_bytes: total.saturating_sub(available),
        total_bytes: total,
    })
}

fn read_memory() -> Option<MemoryStats> {
    let mut status = MEMORYSTATUSEX {
        dwLength: size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    unsafe { GlobalMemoryStatusEx(&mut status) }.ok()?;
    memory_stats(status.ullTotalPhys, status.ullAvailPhys)
}

/// A PDH query with the CPU and GPU counters. It lives on the sampler thread
/// only, so its raw handles never cross threads.
struct Counters {
    query: PDH_HQUERY,
    cpu: Option<PDH_HCOUNTER>,
    gpu: Option<PDH_HCOUNTER>,
}

impl Counters {
    fn open() -> Option<Self> {
        let mut query = PDH_HQUERY::default();
        if unsafe { PdhOpenQueryW(PCWSTR::null(), 0, &mut query) } != 0 {
            return None;
        }
        let add = |path: PCWSTR| {
            let mut counter = PDH_HCOUNTER::default();
            (unsafe { PdhAddEnglishCounterW(query, path, 0, &mut counter) } == 0).then_some(counter)
        };
        let cpu = add(w!(r"\Processor Information(*)\% Processor Time"));
        let gpu = add(w!(r"\GPU Engine(*)\Utilization Percentage"));
        let counters = Self { query, cpu, gpu };
        counters.collect();
        Some(counters)
    }

    fn collect(&self) -> bool {
        unsafe { PdhCollectQueryData(self.query) == 0 }
    }

    /// Every instance's value, or `None` before a second sample exists.
    fn read(counter: Option<PDH_HCOUNTER>) -> Option<Vec<(String, f64)>> {
        let counter = counter?;
        /* The instance list can grow between the size query and the read; retry. */
        for _ in 0..3 {
            let (mut bytes, mut count) = (0u32, 0u32);
            let status = unsafe {
                PdhGetFormattedCounterArrayW(counter, PDH_FMT_DOUBLE, &mut bytes, &mut count, None)
            };
            if status != PDH_MORE_DATA {
                return None;
            }
            /* u64 words keep the item array aligned; the names follow it in the same buffer. */
            let mut buffer = vec![0u64; (bytes as usize).div_ceil(8)];
            let items = buffer.as_mut_ptr().cast::<PDH_FMT_COUNTERVALUE_ITEM_W>();
            let status = unsafe {
                PdhGetFormattedCounterArrayW(
                    counter,
                    PDH_FMT_DOUBLE,
                    &mut bytes,
                    &mut count,
                    Some(items),
                )
            };
            if status == PDH_MORE_DATA {
                continue;
            }
            if status != 0 {
                return None;
            }
            let items = unsafe { std::slice::from_raw_parts(items, count as usize) };
            return Some(
                items
                    .iter()
                    .filter(|item| {
                        matches!(
                            item.FmtValue.CStatus,
                            PDH_CSTATUS_VALID_DATA | PDH_CSTATUS_NEW_DATA
                        )
                    })
                    .map(|item| {
                        let name = unsafe { item.szName.to_string() }.unwrap_or_default();
                        (name, unsafe { item.FmtValue.Anonymous.doubleValue })
                    })
                    .collect(),
            );
        }
        None
    }

    fn sample(&self) -> SystemStats {
        let collected = self.collect();
        let cpu = collected
            .then(|| Self::read(self.cpu))
            .flatten()
            .and_then(|items| cpu_usage(&items));
        let gpu = collected
            .then(|| Self::read(self.gpu))
            .flatten()
            .and_then(|items| gpu_usage(&items));
        SystemStats {
            cpu,
            memory: read_memory(),
            gpu,
        }
    }
}

impl Drop for Counters {
    fn drop(&mut self) {
        unsafe {
            PdhCloseQuery(self.query);
        }
    }
}

/// The running sampler, if any. Dropping its sender stops it.
#[derive(Default)]
pub struct SystemSampler {
    running: Mutex<Option<Sender<()>>>,
}

fn run(app: &AppHandle, stop: &mpsc::Receiver<()>) {
    let counters = Counters::open();
    /* A first reading at once, so the tab never opens empty; CPU follows a second later. */
    let first = SystemStats {
        cpu: None,
        memory: read_memory(),
        gpu: None,
    };
    let _ = app.emit(EVENT, first);
    loop {
        match stop.recv_timeout(INTERVAL) {
            Err(RecvTimeoutError::Timeout) => {}
            _ => return,
        }
        let stats = match &counters {
            Some(counters) => counters.sample(),
            None => SystemStats {
                cpu: None,
                memory: read_memory(),
                gpu: None,
            },
        };
        let _ = app.emit(EVENT, stats);
    }
}

/// Starts or stops sampling. The UI turns it on while the System tab (or
/// anything else showing these numbers) is visible, and off again after.
#[tauri::command]
pub fn system_watch(app: AppHandle, on: bool) {
    let sampler = app.state::<SystemSampler>();
    let mut running = sampler.running.lock().expect("system sampler lock");
    match (on, running.is_some()) {
        (true, false) => {
            let (sender, receiver) = mpsc::channel();
            let thread_app = app.clone();
            thread::Builder::new()
                .name("tabbi-system".into())
                .spawn(move || run(&thread_app, &receiver))
                .expect("the system sampler thread starts");
            *running = Some(sender);
        }
        (false, true) => *running = None,
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn items(list: &[(&str, f64)]) -> Vec<(String, f64)> {
        list.iter().map(|(n, v)| ((*n).to_owned(), *v)).collect()
    }

    #[test]
    fn cpu_cores_are_ordered_by_group_and_index_and_totals_are_not_cores() {
        let usage = cpu_usage(&items(&[
            ("_Total", 25.0),
            ("0,_Total", 25.0),
            ("0,10", 10.0),
            ("0,2", 50.0),
            ("1,0", 100.0),
            ("0,0", 0.0),
        ]))
        .unwrap();
        assert_eq!(usage.total, 0.25);
        assert_eq!(usage.per_core, vec![0.0, 0.5, 0.1, 1.0]);
    }

    #[test]
    fn cpu_total_falls_back_to_the_mean_and_values_are_clamped() {
        let usage = cpu_usage(&items(&[("0", 120.0), ("1", -5.0), ("2", f64::NAN)])).unwrap();
        assert_eq!(usage.per_core, vec![1.0, 0.0, 0.0]);
        assert!((usage.total - 1.0 / 3.0).abs() < 1e-12);
        assert_eq!(cpu_usage(&items(&[("_Total", 5.0)])), None);
        assert_eq!(cpu_usage(&[]), None);
    }

    #[test]
    fn gpu_is_the_busiest_3d_engine_summed_over_processes() {
        let gpu = gpu_usage(&items(&[
            (
                "pid_100_luid_0x00000000_0x0000D1B5_phys_0_eng_0_engtype_3D",
                20.0,
            ),
            (
                "pid_200_luid_0x00000000_0x0000D1B5_phys_0_eng_0_engtype_3D",
                15.0,
            ),
            (
                "pid_300_luid_0x00000000_0x0000D1B5_phys_0_eng_1_engtype_3D",
                30.0,
            ),
            (
                "pid_200_luid_0x00000000_0x0000D1B5_phys_0_eng_3_engtype_VideoDecode",
                90.0,
            ),
            (
                "pid_400_luid_0x00000000_0x0000E000_phys_0_eng_0_engtype_Copy",
                80.0,
            ),
        ]))
        .unwrap();
        assert!((gpu - 0.35).abs() < 1e-12);
    }

    #[test]
    fn gpu_load_over_a_full_engine_is_capped_and_no_3d_engine_means_no_reading() {
        assert_eq!(
            gpu_usage(&items(&[
                ("pid_1_luid_0x0_0x1_phys_0_eng_0_engtype_3D", 70.0),
                ("pid_2_luid_0x0_0x1_phys_0_eng_0_engtype_3D", 60.0),
            ])),
            Some(1.0)
        );
        assert_eq!(
            gpu_usage(&items(&[(
                "pid_1_luid_0x0_0x1_phys_0_eng_0_engtype_Copy",
                5.0
            )])),
            None
        );
        assert_eq!(
            gpu_usage(&items(&[(
                "pid_1_luid_0x0_0x1_phys_0_eng_0_engtype_3D",
                0.0
            )])),
            Some(0.0)
        );
    }

    #[test]
    fn memory_in_use_is_installed_minus_available() {
        assert_eq!(
            memory_stats(16 << 30, 6 << 30),
            Some(MemoryStats {
                used_bytes: 10 << 30,
                total_bytes: 16 << 30
            })
        );
        assert_eq!(memory_stats(8, 9).unwrap().used_bytes, 0);
        assert_eq!(memory_stats(0, 0), None);
    }

    #[test]
    fn stats_serialize_in_the_ui_shape() {
        let stats = SystemStats {
            cpu: Some(CpuUsage {
                total: 0.5,
                per_core: vec![0.25, 0.75],
            }),
            memory: memory_stats(4, 1),
            gpu: None,
        };
        assert_eq!(
            serde_json::to_value(stats).unwrap(),
            serde_json::json!({
                "cpu": { "total": 0.5, "perCore": [0.25, 0.75] },
                "memory": { "usedBytes": 3, "totalBytes": 4 },
                "gpu": null
            })
        );
    }

    /// Takes two real readings. Run on a Windows desktop with
    /// `cargo test -- --ignored`.
    #[test]
    #[ignore = "reads the real performance counters"]
    fn live_sample() {
        let counters = Counters::open().expect("PDH opens");
        thread::sleep(INTERVAL);
        let stats = counters.sample();
        println!("{stats:?}");
        let cpu = stats.cpu.expect("CPU after two samples");
        assert!(!cpu.per_core.is_empty());
        assert!(stats.memory.expect("memory").total_bytes > 0);
    }
}
