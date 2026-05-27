# =============================================================================
#  VFSOC :: Cleanup watchdog (spawned by VFSOC-Launch.ps1)
# -----------------------------------------------------------------------------
#  This script runs in a hidden background PowerShell that survives even if
#  the user violently closes the launcher's CMD window. It waits for the
#  parent CMD PID to disappear, then:
#    1. Removes its session lock file
#    2. Kills any leftover process on the app's port
#    3. For the ingestion app, kills the WPF process too
#    4. If no other VFSOC app is still running, brings the shared Docker
#       infra (Postgres, OpenSearch, Dashboards) down.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [Parameter(Mandatory=$true)][string]$App,
    [Parameter(Mandatory=$true)][string]$SessionId,
    [int]$Port = 0,
    [Parameter(Mandatory=$true)][string]$LockDir,
    [Parameter(Mandatory=$true)][string]$ComposeFile,
    [string]$LogFile,
    # Optional: Ingestion-only. Lets the watchdog also clean up the Python
    # Format API Server that VFSOC-Launch.ps1 started on the user's behalf.
    [int]$LogGenPid = 0,
    [int]$LogGenPort = 0
)

$ErrorActionPreference = 'Continue'

function Log($msg) {
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $line -Encoding utf8 } catch { }
    }
}

Log "Watchdog starting (parent cmd PID=$ParentPid, app=$App, session=$SessionId, port=$Port)"

# ---------------------------------------------------------------------------
# Wait until the parent CMD window closes (process exits)
# ---------------------------------------------------------------------------
while ($true) {
    $p = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Seconds 2
}
Log "Parent CMD (PID $ParentPid) has exited - running cleanup."

# ---------------------------------------------------------------------------
# 1. Free this app's port
# ---------------------------------------------------------------------------
if ($Port -gt 0) {
    try {
        $procs = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($procId in $procs) {
            try {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                Log "Killed PID $procId holding port $Port"
            } catch { Log "Failed to kill PID $procId : $($_.Exception.Message)" }
        }
    } catch { Log "Port cleanup error: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# 2. For ingestion, ensure the WPF client and Format API are closed
# ---------------------------------------------------------------------------
if ($App -eq 'ingestion') {
    try {
        Get-Process -Name 'VFSOC.Ingestion.Client' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Log "Killed WPF PID $($_.Id)" } catch { }
            }
    } catch { }

    # Kill the Python Format API we started by PID (preferred)...
    if ($LogGenPid -gt 0) {
        try {
            Stop-Process -Id $LogGenPid -Force -ErrorAction SilentlyContinue
            Log "Killed Format API PID $LogGenPid"
        } catch { Log "Format API PID $LogGenPid cleanup error: $($_.Exception.Message)" }
    }
    # ...and as a safety net, free port 8001 from whatever is still holding it.
    if ($LogGenPort -gt 0) {
        try {
            $procs = @(Get-NetTCPConnection -State Listen -LocalPort $LogGenPort -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty OwningProcess -Unique)
            foreach ($procId in $procs) {
                try {
                    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                    Log "Killed PID $procId holding Format API port $LogGenPort"
                } catch { Log "Format API port cleanup error: $($_.Exception.Message)" }
            }
        } catch { Log "Format API port lookup error: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# 3. Drop my session lock and (if no others remain) take infra down
# ---------------------------------------------------------------------------
$myLock = Join-Path $LockDir "$SessionId.lock"
Remove-Item $myLock -Force -ErrorAction SilentlyContinue
Log "Removed session lock $myLock"

# Discard locks whose parent CMD is already dead (stale from earlier crashes).
$remainingLocks = @()
foreach ($f in (Get-ChildItem -Path $LockDir -Filter '*.lock' -ErrorAction SilentlyContinue)) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    $cmdPidLine = ($content -split "`r?`n") | Where-Object { $_ -match '^cmdPid=' } | Select-Object -First 1
    if ($cmdPidLine) {
        $cmdPid = [int]($cmdPidLine -replace '^cmdPid=','')
        $alive = Get-Process -Id $cmdPid -ErrorAction SilentlyContinue
        if (-not $alive) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Log "Cleaned stale lock $($f.Name) (cmd PID $cmdPid no longer running)"
            continue
        }
    }
    $remainingLocks += $f
}

if ($remainingLocks.Count -gt 0) {
    Log ("Skipping infra teardown - {0} other VFSOC app(s) still running: {1}" -f $remainingLocks.Count, (($remainingLocks | ForEach-Object { $_.BaseName }) -join ', '))
} else {
    Log "No other VFSOC apps running - bringing infra down."
    try {
        & docker compose -f $ComposeFile -p vfsoc down 2>&1 | ForEach-Object { Log "docker compose: $_" }
    } catch { Log "docker compose down error: $($_.Exception.Message)" }
}

Log "Watchdog finished."
exit 0
