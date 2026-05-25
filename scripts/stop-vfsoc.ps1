# =============================================================================
#  VFSOC :: Stop all services
# -----------------------------------------------------------------------------
#  Stops the Docker infra and frees the application ports used by VFSOC.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$KeepInfra
)

. "$PSScriptRoot\lib\Common.ps1"

$extrasRoot = Get-VfsocRoot
$config     = Get-VfsocConfig

Write-VfsocBanner "Stopping VFSOC"

# Application ports we own.
$ports = @(
    $config.services.main_dashboard.port,
    $config.services.admin_dashboard.port,
    $config.services.log_generation_api.port,
    $config.services.ml_inference.port
)

foreach ($p in $ports) {
    Write-VfsocStep "Releasing port $p ..."
    Stop-VfsocProcessOnPort $p
}

# Stop WPF Ingestion client (if running)
Write-VfsocStep "Stopping Ingestion WPF client (if running) ..."
try {
    Get-Process -Name 'VFSOC.Ingestion.Client' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-VfsocOk "Stopped Ingestion (PID $($_.Id))"
        }
} catch { }

if (-not $KeepInfra -and (Test-Command 'docker')) {
    Write-VfsocStep "Stopping Docker infra ..."
    $compose = Join-Path $extrasRoot 'scripts\lib\docker-compose.infra.yml'
    try {
        docker compose -f $compose -p vfsoc down | Out-Host
        Write-VfsocOk "Docker infra stopped."
    } catch {
        Write-VfsocWarn "docker compose down failed: $($_.Exception.Message)"
    }
} elseif ($KeepInfra) {
    Write-VfsocWarn "Keeping Docker infra running (--KeepInfra)."
}

Write-VfsocBanner "VFSOC stopped"
