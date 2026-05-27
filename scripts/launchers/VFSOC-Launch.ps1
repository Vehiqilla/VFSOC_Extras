# =============================================================================
#  VFSOC :: Unified launcher
# -----------------------------------------------------------------------------
#  One PowerShell entry point for the three desktop shortcuts.
#
#    -App ingestion   -> brings up Docker infra, then launches the WPF client
#    -App admin       -> brings up Docker infra, then runs the Admin Next.js app
#    -App siem        -> brings up Docker infra, then runs the SIEM Next.js app
#
#  The launcher is designed for non-technical users:
#    * Verifies Docker Desktop is running (starts it automatically if not).
#    * Starts Postgres + OpenSearch + Dashboards via docker compose.
#    * Applies the unified DB schema (idempotent).
#    * Starts the requested app and opens the browser (for web apps).
#    * Spawns a hidden watchdog so that closing the CMD window cleanly stops
#      this app's port and, when nothing else is running, the Docker infra too.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('ingestion','admin','siem')]
    [string]$App
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Paths & config
# ---------------------------------------------------------------------------
$launcherDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir    = Split-Path -Parent $launcherDir
$extrasRoot    = Split-Path -Parent $scriptsDir
$projectsRoot  = Split-Path -Parent $extrasRoot
$configPath    = Join-Path $extrasRoot 'vfsoc.config.json'
$composeFile   = Join-Path $extrasRoot 'scripts\lib\docker-compose.infra.yml'
$schemaFile    = Join-Path $extrasRoot 'scripts\lib\db-schema.sql'
$demoSeedFile  = Join-Path $extrasRoot 'scripts\lib\vfsoc-demo-seed.sql'

if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] vfsoc.config.json not found at $configPath" -ForegroundColor Red
    pause; exit 1
}
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json

$pg = $cfg.services.postgres
$logGen = $cfg.services.log_generation_api

switch ($App) {
    'ingestion' {
        $title       = 'VFSOC Ingestion'
        $appPort     = 0
        $appUrl      = $null
        $ingDir      = Join-Path $projectsRoot $cfg.services.ingestion.path
        $exeRel      = Join-Path $ingDir ($cfg.services.ingestion.wpf_exe_release -replace '/', '\')
        $exeDbg      = Join-Path $ingDir ($cfg.services.ingestion.wpf_exe_debug   -replace '/', '\')
        $projFile    = Join-Path $ingDir ($cfg.services.ingestion.wpf_project     -replace '/', '\')
        $logGenDir   = Join-Path $projectsRoot $logGen.path
        $logGenEntry = Join-Path $logGenDir   $logGen.entry
        $logGenPort  = [int]$logGen.port
        $logGenUrl   = $logGen.url
    }
    'admin' {
        $title       = 'VFSOC Admin'
        $appPort     = [int]$cfg.services.admin_dashboard.port
        $appUrl      = $cfg.services.admin_dashboard.url
        $appDir      = Join-Path $projectsRoot $cfg.services.admin_dashboard.path
    }
    'siem' {
        $title       = 'VFSOC Main Dashboard'
        $appPort     = [int]$cfg.services.main_dashboard.port
        $appUrl      = $cfg.services.main_dashboard.url
        $appDir      = Join-Path $projectsRoot $cfg.services.main_dashboard.path
    }
}

# ---------------------------------------------------------------------------
# Console / UI
# ---------------------------------------------------------------------------
try { $Host.UI.RawUI.WindowTitle = "$title  (close this window to stop)" } catch {}

function Banner($msg) {
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host ("  $msg")  -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
}
function Step($msg) { Write-Host ("  [>] $msg") -ForegroundColor Yellow }
function Ok($msg)   { Write-Host ("  [OK] $msg") -ForegroundColor Green }
function Warn($msg) { Write-Host ("  [!] $msg")  -ForegroundColor Magenta }
function Err($msg)  { Write-Host ("  [ERROR] $msg") -ForegroundColor Red }

Banner "$title"

# ---------------------------------------------------------------------------
# Session lock (reference counting so the last app down also stops infra)
# ---------------------------------------------------------------------------
$stateDir   = Join-Path $env:USERPROFILE '.vfsoc-launcher'
$lockDir    = Join-Path $stateDir 'locks'
$logDir     = Join-Path $stateDir 'logs'
foreach ($d in @($stateDir, $lockDir, $logDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Find the parent CMD process so the watchdog can detect when the user
# closes the terminal window.
$parentCmdPid = $PID  # fallback
try {
    $parent = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
    if ($parent) { $parentCmdPid = [int]$parent }
} catch { }

$sessionId  = "${App}-$parentCmdPid"
$lockFile   = Join-Path $lockDir "$sessionId.lock"
Set-Content -Path $lockFile -Value "app=$App`r`ncmdPid=$parentCmdPid`r`nport=$appPort`r`nstarted=$(Get-Date -Format o)" -Encoding ASCII

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Test-PortListening([int]$Port) {
    if ($Port -le 0) { return $false }
    try {
        return ((Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) -ne $null)
    } catch { return $false }
}

function Test-DockerEngineUp {
    try {
        $null = & docker info --format '{{.ServerVersion}}' 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Start-DockerDesktopIfNeeded {
    if (Test-DockerEngineUp) { Ok "Docker engine is already running"; return $true }

    $dockerExe = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $dockerExe) {
        Err "Docker Desktop is not installed. Please install Docker Desktop first."
        Write-Host "    Download: https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
        return $false
    }

    Step "Starting Docker Desktop (this can take up to 60 seconds the first time)..."
    try { Start-Process -FilePath $dockerExe -WindowStyle Hidden | Out-Null } catch {}

    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if (Test-DockerEngineUp) { Ok "Docker engine is ready"; return $true }
        Start-Sleep -Seconds 3
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    Err "Docker engine did not become ready in time. Please open Docker Desktop manually and re-run."
    return $false
}

function Start-VfsocInfra {
    if (-not (Test-Path $composeFile)) {
        Err "Compose file not found: $composeFile"
        return $false
    }

    # Defend against leftover containers from older stacks (e.g. the legacy
    # VFSOC-Ingestion\docker-compose.yml) that auto-restart and grab our
    # ports. Stop any container holding ports 5432, 9200, 9600, 5601.
    $needed = @(5432, 9200, 9600, 5601)
    $conflicting = @()
    foreach ($port in $needed) {
        try {
            $ids = & docker ps --filter "publish=$port" --format "{{.Names}}" 2>$null
            if ($ids) {
                foreach ($n in ($ids -split "`r?`n" | Where-Object { $_ })) {
                    if ($n -notin @('vfsoc-postgres','vfsoc-opensearch','vfsoc-opensearch-dashboards')) {
                        $conflicting += $n
                    }
                }
            }
        } catch { }
    }
    $conflicting = $conflicting | Sort-Object -Unique
    if ($conflicting.Count -gt 0) {
        Warn ("Stopping conflicting containers on shared ports: {0}" -f ($conflicting -join ', '))
        try { & docker stop $conflicting 2>&1 | Out-Null } catch { }
        try { & docker rm   $conflicting 2>&1 | Out-Null } catch { }
    }

    Step "Starting VFSOC infrastructure (Postgres, OpenSearch, Dashboards)..."
    try {
        & docker compose -f $composeFile -p vfsoc up -d 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) { Err "docker compose up failed"; return $false }
    } catch {
        Err "docker compose up failed: $($_.Exception.Message)"
        return $false
    }

    Step "Waiting for PostgreSQL on port $($pg.port)..."
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect('127.0.0.1', [int]$pg.port); $tcp.Close()
            Ok "PostgreSQL is accepting connections"
            return $true
        } catch { Start-Sleep -Seconds 2 }
    }
    Warn "PostgreSQL is not responding yet; app may show database errors briefly."
    return $true
}

function Apply-VfsocSchema {
    # The schemas / seeds are all idempotent, so re-running is harmless.
    $container = (& docker ps --filter "name=vfsoc-postgres" --format "{{.Names}}" | Select-Object -First 1)
    if (-not $container) { $container = 'vfsoc-postgres' }
    $env:PGPASSWORD = $pg.password

    if (Test-Path $schemaFile) {
        Step "Ensuring database schema is up to date..."
        try {
            Get-Content $schemaFile -Raw | & docker exec -i -e "PGPASSWORD=$($pg.password)" $container psql -U $pg.user -d $pg.database 2>&1 |
                Out-File -FilePath (Join-Path $logDir "db-schema-apply.log") -Encoding utf8
            Ok "Database schema verified"
        } catch {
            Warn "Schema apply step skipped: $($_.Exception.Message)"
        }
    }

    if (Test-Path $demoSeedFile) {
        Step "Seeding fleets, mobility assets and asset-connector links..."
        try {
            Get-Content $demoSeedFile -Raw | & docker exec -i -e "PGPASSWORD=$($pg.password)" $container psql -U $pg.user -d $pg.database -v ON_ERROR_STOP=1 2>&1 |
                Out-File -FilePath (Join-Path $logDir "db-demo-seed-apply.log") -Encoding utf8
            Ok "Fleet / asset demo data seeded"
        } catch {
            Warn "Demo seed step skipped: $($_.Exception.Message)"
        }
    }
}

function Resolve-PythonExecutable {
    foreach ($cmd in @('python', 'py', 'python3')) {
        $info = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($info) {
            try {
                & $info.Source --version *> $null
                if ($LASTEXITCODE -eq 0) { return $info.Source }
            } catch { }
        }
    }
    return $null
}

function Start-VfsocLogGenApi {
    # The WPF Ingestion client depends on the "Format API Server" running on
    # http://localhost:8001 to generate simulated logs. Without it, the UI
    # shows an "API Server Unavailable" banner and connectors can't ingest.
    # Bring it up here (idempotent: skip if already listening), create a venv
    # the first time, install requirements, and wait for the HTTP endpoint.

    if (-not (Test-Path $logGenEntry)) {
        Warn "Log Generation entrypoint not found: $logGenEntry"
        return
    }

    if (Test-PortListening -Port $logGenPort) {
        Ok "Format API Server is already running on port $logGenPort"
        return
    }

    $python = Resolve-PythonExecutable
    if (-not $python) {
        Err "Python is not installed or not on PATH; the Ingestion client's Format API cannot start."
        Write-Host "    Install Python 3.11+ from https://www.python.org/downloads/ and re-run." -ForegroundColor Gray
        return
    }

    # Use a project-local venv so dependencies don't pollute the global env.
    $venvDir    = Join-Path $logGenDir '.venv'
    $venvPython = Join-Path $venvDir   'Scripts\python.exe'
    $reqFile    = Join-Path $logGenDir 'requirements.txt'
    $reqStamp   = Join-Path $venvDir   '.vfsoc-requirements.installed'

    if (-not (Test-Path $venvPython)) {
        Step "Creating Python venv for Format API (one-time)..."
        try {
            & $python -m venv $venvDir | Out-Null
            if (-not (Test-Path $venvPython)) { throw "venv creation produced no python.exe" }
            Ok "Created venv at $venvDir"
        } catch {
            Err "Failed to create venv: $($_.Exception.Message)"
            return
        }
    }

    # (Re)install requirements when the file changes (track by hash).
    $needInstall = $true
    if ((Test-Path $reqFile) -and (Test-Path $reqStamp)) {
        try {
            $hashNow   = (Get-FileHash $reqFile -Algorithm SHA1).Hash
            $hashPrev  = Get-Content $reqStamp -Raw -ErrorAction SilentlyContinue
            if ($hashNow.Trim() -eq ($hashPrev | Out-String).Trim()) { $needInstall = $false }
        } catch { }
    }
    if ($needInstall -and (Test-Path $reqFile)) {
        Step "Installing Format API Python dependencies (this can take a minute the first time)..."
        try {
            & $venvPython -m pip install --quiet --upgrade pip 2>&1 | Out-Null
            & $venvPython -m pip install --quiet -r $reqFile 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Ok "Python dependencies installed"
                try {
                    (Get-FileHash $reqFile -Algorithm SHA1).Hash | Set-Content -Path $reqStamp -Encoding ASCII
                } catch { }
            } else {
                Warn "pip install reported a non-zero exit code; the API may still start if deps are already present"
            }
        } catch {
            Warn "pip install threw: $($_.Exception.Message)"
        }
    }

    Step "Starting Format API Server on port $logGenPort ..."
    $apiLog = Join-Path $logDir "format-api-$parentCmdPid.log"
    # The log_simulator startup prints Unicode glyphs (e.g. checkmarks). Force
    # the child Python process to use UTF-8 for stdout/stderr so it doesn't
    # die with a 'charmap' UnicodeEncodeError on the default Windows codepage.
    $prevEncoding = $env:PYTHONIOENCODING
    $prevUtf8     = $env:PYTHONUTF8
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONUTF8 = '1'
    try {
        # Minimised window so the user can see it if they want, but it
        # doesn't steal focus. The watchdog will close it on exit.
        $apiArgs = @('-u', $logGenEntry)
        $apiProc = Start-Process -FilePath $venvPython `
                                 -ArgumentList $apiArgs `
                                 -WorkingDirectory $logGenDir `
                                 -WindowStyle Minimized `
                                 -PassThru `
                                 -RedirectStandardOutput $apiLog `
                                 -RedirectStandardError  ($apiLog + '.err')
        $script:LogGenApiPid = $apiProc.Id
        Ok "Format API process started (PID $($apiProc.Id)); log: $apiLog"
    } catch {
        Err "Failed to launch Format API: $($_.Exception.Message)"
        return
    } finally {
        $env:PYTHONIOENCODING = $prevEncoding
        $env:PYTHONUTF8       = $prevUtf8
    }

    Step "Waiting for $logGenUrl to respond ..."
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortListening -Port $logGenPort) {
            try {
                $r = Invoke-WebRequest -UseBasicParsing -Uri $logGenUrl -TimeoutSec 2 -ErrorAction Stop
                if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
                    Ok "Format API Server is ready at $logGenUrl"
                    return
                }
            } catch {
                # Port is open but app isn't fully responsive yet - keep waiting
            }
        }
        Start-Sleep -Seconds 2
    }
    Warn "Format API did not become ready within 60s - the Ingestion UI may show 'API Server Unavailable' briefly."
    Warn "Check log: $apiLog"
}

function Spawn-Watchdog {
    $watchdog = Join-Path $launcherDir 'VFSOC-Cleanup.ps1'
    if (-not (Test-Path $watchdog)) { Warn "Watchdog script not found ($watchdog); auto-cleanup disabled."; return }

    $watchdogLog = Join-Path $logDir "watchdog-$sessionId.log"
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
        '-File', $watchdog,
        '-ParentPid', $parentCmdPid,
        '-App', $App,
        '-SessionId', $sessionId,
        '-Port', $appPort,
        '-LockDir', $lockDir,
        '-ComposeFile', $composeFile,
        '-LogFile', $watchdogLog
    )
    # If we started the Python Format API, hand its PID + port to the watchdog
    # so it gets terminated when this launcher window closes.
    if ($App -eq 'ingestion') {
        if ($logGenPort -gt 0) { $args += @('-LogGenPort', $logGenPort) }
        if ($script:LogGenApiPid) { $args += @('-LogGenPid', $script:LogGenApiPid) }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden | Out-Null
        Ok "Cleanup watchdog armed (will run when this window closes)"
    } catch {
        Warn "Could not start watchdog: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Bring up shared infra
# ---------------------------------------------------------------------------
if (-not (Start-DockerDesktopIfNeeded)) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "Press any key to close this window..." -ForegroundColor Gray
    [void][System.Console]::ReadKey($true)
    exit 1
}

if (-not (Start-VfsocInfra)) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "Press any key to close this window..." -ForegroundColor Gray
    [void][System.Console]::ReadKey($true)
    exit 1
}

Apply-VfsocSchema

# The Ingestion WPF client needs the Python "Format API Server" running on
# port 8001 to generate logs. Start it (and wait for it) before launching
# the WPF client so the connectors tab doesn't pop the "API Server
# Unavailable" dialog on first load.
if ($App -eq 'ingestion') {
    Start-VfsocLogGenApi
}

Spawn-Watchdog

# ---------------------------------------------------------------------------
# Launch the requested app
# ---------------------------------------------------------------------------
Write-Host ''
Banner "Launching $title"

if ($App -eq 'ingestion') {
    $exe = if (Test-Path $exeRel) { $exeRel } elseif (Test-Path $exeDbg) { $exeDbg } else { $null }
    if (-not $exe) {
        Step "First-time build of the Ingestion client (this can take a couple of minutes)..."
        if (Get-Command dotnet -ErrorAction SilentlyContinue) {
            Push-Location $ingDir
            try { & dotnet build -c Release $projFile | Out-Host } finally { Pop-Location }
            $exe = if (Test-Path $exeRel) { $exeRel } elseif (Test-Path $exeDbg) { $exeDbg } else { $null }
        } else {
            Err "dotnet SDK 8 is not installed; cannot build the Ingestion client."
        }
    }
    if (-not $exe) {
        Err "Ingestion executable could not be built. See documentation."
        Write-Host ''
        Write-Host "Press any key to close..." -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
        exit 1
    }

    Step "Launching Ingestion client..."
    $proc = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
    Ok "Ingestion client started (PID $($proc.Id))"
    Write-Host ''
    Write-Host "Ingestion is now running. Close THIS window to stop the Ingestion app" -ForegroundColor White
    Write-Host "and (if nothing else is using them) the Postgres + OpenSearch services." -ForegroundColor White
    Write-Host ''
    # Wait for either the app process to exit, OR the window to be closed.
    $proc.WaitForExit()
    Write-Host ''
    Ok "Ingestion app exited."
    Write-Host "Cleaning up..." -ForegroundColor Gray
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    # The watchdog handles infra teardown when this window closes.
    Write-Host ''
    Write-Host "You can close this window now." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    exit 0
}
else {
    # ---- web app (admin / siem) ----
    if (-not (Test-Path $appDir)) { Err "App directory not found: $appDir"; exit 1 }

    if (Test-PortListening -Port $appPort) {
        Ok "$title already running on port $appPort - reusing existing dev server"
    } else {
        # Make sure node deps are installed
        if (-not (Test-Path (Join-Path $appDir 'node_modules'))) {
            Step "Installing Node dependencies (one-time, may take a minute)..."
            Push-Location $appDir
            try { & npm install --no-audit --no-fund | Out-Host } finally { Pop-Location }
        }

        Step "Starting Next.js dev server in $appDir ..."
        # Run npm via cmd.exe in this same console so closing the window
        # tears down the dev server with it.
        $npmLog = Join-Path $logDir "$App-npm.log"
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c','npm','run','dev') `
                              -WorkingDirectory $appDir -NoNewWindow -PassThru
        Ok "Dev server starting (PID $($proc.Id)). Logs stream below."
    }

    Step "Waiting for $appUrl to respond..."
    $ready = $false
    for ($i=0; $i -lt 120; $i++) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $appUrl -TimeoutSec 2 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 1
    }
    if ($ready) { Ok "$title is ready at $appUrl" } else { Warn "$title not ready yet - opening browser anyway; refresh once it loads." }

    try { Start-Process $appUrl | Out-Null } catch { }

    Write-Host ''
    Write-Host "$title is running at $appUrl" -ForegroundColor White
    Write-Host "Close this window to stop the app." -ForegroundColor White
    Write-Host ''
    Write-Host "(Tip: leave this window open while you use the app.)" -ForegroundColor DarkGray
    Write-Host ''

    if ($proc) {
        # Block until the dev server dies (user closes the window or stops it).
        try { $proc.WaitForExit() } catch { }
    } else {
        # No process to wait on (someone else owned the port). Block on a sentinel
        # file so closing this window still wakes the watchdog.
        Write-Host "Press Ctrl+C or close this window to stop."
        while ($true) { Start-Sleep -Seconds 60 }
    }

    Write-Host ''
    Ok "$title dev server stopped."
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    Write-Host "You can close this window now." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    exit 0
}
