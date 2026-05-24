# =============================================================================
#  VFSOC :: Start all services
# -----------------------------------------------------------------------------
#  Order:
#    1. Docker infra (PostgreSQL + OpenSearch + Dashboards)
#    2. Log Generation API (FastAPI, :8001)
#    3. ML Inference Service (Flask, :5000)
#    4. VFSOC-SIEM Main Dashboard (Next.js, :3000)
#    5. VFSOC-Admin Admin Dashboard (Next.js, :3001)
#    6. VFSOC-Ingestion WPF client (Windows desktop app)
#
#  Each service starts in its own window so you can watch the logs and stop
#  individual ones if needed. Use stop-vfsoc.ps1 to stop everything at once.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$NoIngestion,    # skip launching the WPF client
    [switch]$NoBrowser,      # do not auto-open browser tabs
    [switch]$NoInfra         # do not (re)start Docker infra
)

. "$PSScriptRoot\lib\Common.ps1"

$root   = Get-VfsocRoot
$config = Get-VfsocConfig
$logs   = Join-Path $root 'logs'
if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs | Out-Null }

Write-VfsocBanner "Starting VFSOC services"

# ---------------------------------------------------------------------------
# 1. Docker infra
# ---------------------------------------------------------------------------
if (-not $NoInfra) {
    if (Test-Command 'docker') {
        Write-VfsocStep "Starting Docker infra (Postgres, OpenSearch, Dashboards) ..."
        $compose = Join-Path $root 'scripts\lib\docker-compose.infra.yml'
        try {
            docker compose -f $compose -p vfsoc up -d | Out-Host
            Write-VfsocOk "Docker infra is up."
        } catch {
            Write-VfsocErr "Failed to start Docker infra: $($_.Exception.Message)"
        }
    } else {
        Write-VfsocWarn "Docker not available; skipping infra."
    }
} else {
    Write-VfsocWarn "Skipping Docker infra (--NoInfra)."
}

# ---------------------------------------------------------------------------
# 2. Log Generation API (port 8001)
# ---------------------------------------------------------------------------
$logGenDir = Join-Path $root $config.services.log_generation_api.path
$logGenVenv = Join-Path $logGenDir '.venv\Scripts\python.exe'
if (Test-Path $logGenVenv) {
    Start-VfsocService -Name 'Log Generation API' `
        -WorkingDirectory $logGenDir `
        -Command 'cmd.exe' `
        -Arguments @('/c', "start `"VFSOC Log Generation API`" cmd /k `"call .venv\Scripts\activate.bat && python run_api.py`"") `
        -WaitForPort $config.services.log_generation_api.port
} else {
    Write-VfsocWarn "Python venv not found in VFSOC-log_generation. Run scripts\setup-vfsoc.ps1 first."
}

# ---------------------------------------------------------------------------
# 3. ML Inference Service (port 5000)
# ---------------------------------------------------------------------------
$mlDir = Join-Path $root $config.services.ml_inference.path
$mlVenv = Join-Path $mlDir '.venv\Scripts\python.exe'
if (Test-Path $mlVenv) {
    Start-VfsocService -Name 'ML Inference Service' `
        -WorkingDirectory $mlDir `
        -Command 'cmd.exe' `
        -Arguments @('/c', "start `"VFSOC ML Inference`" cmd /k `"call .venv\Scripts\activate.bat && python model_inference_service.py`"") `
        -WaitForPort $config.services.ml_inference.port
} else {
    Write-VfsocWarn "Python venv not found in VFSOC-ML-Models. Skipping ML (it is optional)."
}

# ---------------------------------------------------------------------------
# 4. VFSOC-SIEM Main Dashboard (port 3000)
# ---------------------------------------------------------------------------
$siemDir = Join-Path $root $config.services.main_dashboard.path
Start-VfsocService -Name 'VFSOC Main Dashboard (SIEM)' `
    -WorkingDirectory $siemDir `
    -Command 'cmd.exe' `
    -Arguments @('/c', 'start "VFSOC Main Dashboard" cmd /k "npm run dev"') `
    -WaitForPort $config.services.main_dashboard.port

# ---------------------------------------------------------------------------
# 5. VFSOC-Admin Admin Dashboard (port 3001)
# ---------------------------------------------------------------------------
$adminDir = Join-Path $root $config.services.admin_dashboard.path
Start-VfsocService -Name 'VFSOC Admin Dashboard' `
    -WorkingDirectory $adminDir `
    -Command 'cmd.exe' `
    -Arguments @('/c', 'start "VFSOC Admin Dashboard" cmd /k "npm run dev"') `
    -WaitForPort $config.services.admin_dashboard.port

# ---------------------------------------------------------------------------
# 6. Ingestion WPF
# ---------------------------------------------------------------------------
if (-not $NoIngestion) {
    $ingDir = Join-Path $root $config.services.ingestion.path
    $exe    = Join-Path $ingDir $config.services.ingestion.wpf_exe
    if (Test-Path $exe) {
        Write-VfsocStep "Launching Ingestion WPF client ..."
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
        Write-VfsocOk "Ingestion client launched."
    } else {
        Write-VfsocWarn "Ingestion exe not built. Run scripts\setup-vfsoc.ps1 or VFSOC-Ingestion\build_and_run.bat"
    }
} else {
    Write-VfsocWarn "Skipping Ingestion WPF (--NoIngestion)."
}

# ---------------------------------------------------------------------------
# Health wait + browser
# ---------------------------------------------------------------------------
Write-VfsocStep "Waiting for Main Dashboard at $($config.services.main_dashboard.url) ..."
if (Wait-ForUrl $config.services.main_dashboard.url 90) {
    Write-VfsocOk "Main Dashboard responded."
} else {
    Write-VfsocWarn "Main Dashboard did not respond within 90s."
}

Write-VfsocStep "Waiting for Admin Dashboard at $($config.services.admin_dashboard.url) ..."
if (Wait-ForUrl $config.services.admin_dashboard.url 90) {
    Write-VfsocOk "Admin Dashboard responded."
} else {
    Write-VfsocWarn "Admin Dashboard did not respond within 90s."
}

if (-not $NoBrowser) {
    Start-Process $config.services.main_dashboard.url
    Start-Process $config.services.admin_dashboard.url
}

Write-VfsocBanner "VFSOC is running"
Write-Host "  Main Dashboard : $($config.services.main_dashboard.url)" -ForegroundColor White
Write-Host "  Admin          : $($config.services.admin_dashboard.url)" -ForegroundColor White
Write-Host "  Ingestion      : Windows desktop app"                    -ForegroundColor White
Write-Host "  Log Gen API    : $($config.services.log_generation_api.url)" -ForegroundColor White
Write-Host "  ML Inference   : $($config.services.ml_inference.url)"   -ForegroundColor White
Write-Host "  OpenSearch     : $($config.services.opensearch.url)"     -ForegroundColor White
Write-Host "  OS Dashboards  : $($config.services.opensearch.dashboards_url)" -ForegroundColor White
Write-Host ''
Write-Host "Stop everything with:  scripts\stop-vfsoc.ps1" -ForegroundColor Gray
Write-Host ''
