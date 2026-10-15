<#
.SYNOPSIS
  Measures Tabbi's idle footprint: private working set and CPU over every
  Tabbi process, the host and its WebView2 processes.

.DESCRIPTION
  The phase 1 budget (docs/windows/HANDOFF.md, section 3): at most 80 MB of
  private working set summed over all Tabbi processes, and under 0.1 percent
  CPU, after 10 minutes with the island closed.

  Start Tabbi (a release build), leave the island closed, then run:

    powershell -ExecutionPolicy Bypass -File windows/scripts/measure-idle.ps1 -SettleMinutes 10

  The script waits, then samples CPU time over -SampleSeconds and reads each
  process's "Working Set - Private" counter (what Task Manager shows as Memory).
#>
param(
  [string] $HostName = "tabbi-windows",
  [double] $SettleMinutes = 10,
  [int] $SampleSeconds = 60
)
$ErrorActionPreference = "Stop"

function Get-TabbiProcesses {
  $hostProcess = Get-Process -Name $HostName -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $hostProcess) { throw "$HostName is not running." }
  $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name
  $ids = New-Object System.Collections.Generic.HashSet[int]
  [void]$ids.Add($hostProcess.Id)
  do {
    $added = $false
    foreach ($p in $all) {
      if ($ids.Contains([int]$p.ParentProcessId) -and $ids.Add([int]$p.ProcessId)) { $added = $true }
    }
  } while ($added)
  $all | Where-Object { $ids.Contains([int]$_.ProcessId) }
}

if ($SettleMinutes -gt 0) {
  Write-Host ("Waiting {0} minutes with the island closed..." -f $SettleMinutes)
  Start-Sleep -Seconds ([int]($SettleMinutes * 60))
}

$processes = Get-TabbiProcesses
$before = @{}
foreach ($p in $processes) { $before[[int]$p.ProcessId] = (Get-Process -Id $p.ProcessId).TotalProcessorTime.TotalMilliseconds }
$clock = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds $SampleSeconds
$elapsed = $clock.Elapsed.TotalMilliseconds

$perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Select-Object IDProcess, WorkingSetPrivate
$rows = foreach ($p in $processes) {
  $id = [int]$p.ProcessId
  $live = Get-Process -Id $id -ErrorAction SilentlyContinue
  if (-not $live) { continue }
  $cpu = ($live.TotalProcessorTime.TotalMilliseconds - $before[$id]) / $elapsed / [Environment]::ProcessorCount * 100
  $private = ($perf | Where-Object { $_.IDProcess -eq $id } | Select-Object -First 1).WorkingSetPrivate
  [pscustomobject]@{
    Id = $id
    Name = $p.Name
    PrivateMB = [math]::Round($private / 1MB, 1)
    CpuPercent = [math]::Round($cpu, 3)
  }
}

$rows | Sort-Object PrivateMB -Descending | Format-Table -AutoSize | Out-String | Write-Host
$totalMB = [math]::Round(($rows | Measure-Object PrivateMB -Sum).Sum, 1)
$totalCpu = [math]::Round(($rows | Measure-Object CpuPercent -Sum).Sum, 3)
$memoryOk = $totalMB -le 80
$cpuOk = $totalCpu -lt 0.1
Write-Host ("Total private working set: {0} MB (budget 80 MB): {1}" -f $totalMB, $(if ($memoryOk) { "pass" } else { "over" }))
Write-Host ("Total CPU over {0} s: {1} percent of the machine (budget 0.1): {2}" -f $SampleSeconds, $totalCpu, $(if ($cpuOk) { "pass" } else { "over" }))
if (-not ($memoryOk -and $cpuOk)) { exit 1 }
