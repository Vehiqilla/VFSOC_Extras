# =============================================================================
#  VFSOC :: Install three desktop shortcuts (HLD section 4.1)
# -----------------------------------------------------------------------------
#  Creates on the current user's Desktop:
#    1. VFSOC Ingestion       -> launches the Ingestion WPF client
#    2. VFSOC Main Dashboard  -> opens http://localhost:3000 in the browser
#    3. VFSOC Admin           -> opens http://localhost:3001 in the browser
#
#  The shortcuts are .lnk files; the dashboard shortcuts launch a helper
#  that starts the underlying service if it is not running, then opens the
#  URL. The Ingestion shortcut launches the WPF executable directly (after
#  the first successful build with scripts\setup-vfsoc.ps1).
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Remove
)

. "$PSScriptRoot\lib\Common.ps1"

$extrasRoot = Get-VfsocRoot
$projectsRoot = Get-VfsocProjectsRoot
$config = Get-VfsocConfig
$desktop = [Environment]::GetFolderPath('Desktop')

# Helper batch scripts that the shortcuts call into. Storing them in
# scripts\launchers keeps everything inside the repo and self-contained.
$launcherDir = Join-Path $extrasRoot 'scripts\launchers'
if (-not (Test-Path $launcherDir)) { New-Item -ItemType Directory -Path $launcherDir | Out-Null }

# Resolve concrete paths from the config so the .bat files don't need to
# parse JSON at launch time.
$projectsRootEsc = $projectsRoot.TrimEnd('\')
$siemPath        = Join-Path $projectsRootEsc $config.services.main_dashboard.path
$adminPath       = Join-Path $projectsRootEsc $config.services.admin_dashboard.path
$ingestionPath   = Join-Path $projectsRootEsc $config.services.ingestion.path
$ingestionExeDbg = Join-Path $ingestionPath ($config.services.ingestion.wpf_exe_debug -replace '/', '\')
$ingestionExeRel = Join-Path $ingestionPath ($config.services.ingestion.wpf_exe_release -replace '/', '\')
$ingestionProj   = Join-Path $ingestionPath ($config.services.ingestion.wpf_project -replace '/', '\')
$mainUrl         = $config.services.main_dashboard.url
$mainPort        = $config.services.main_dashboard.port
$adminUrl        = $config.services.admin_dashboard.url
$adminPort       = $config.services.admin_dashboard.port

# -----------------------------------------------------------------------------
# Per-shortcut helper batch scripts
# -----------------------------------------------------------------------------
$ingestionBat = Join-Path $launcherDir 'open-ingestion.bat'
@"
@echo off
REM Launches the VFSOC Ingestion WPF client.
setlocal
set EXE_REL=$ingestionExeRel
set EXE_DBG=$ingestionExeDbg
set PROJ=$ingestionProj

if exist "%EXE_REL%" (
    start "" "%EXE_REL%"
    endlocal & exit /b 0
)

if exist "%EXE_DBG%" (
    start "" "%EXE_DBG%"
    endlocal & exit /b 0
)

echo Building VFSOC-Ingestion for the first time...
pushd "$ingestionPath"
dotnet build -c Release "%PROJ%"
popd

if exist "%EXE_REL%" (
    start "" "%EXE_REL%"
) else if exist "%EXE_DBG%" (
    start "" "%EXE_DBG%"
) else (
    echo Ingestion executable still not found. Run VFSOC_Extras\setup.cmd from a developer console.
    pause
    exit /b 1
)
endlocal
"@ | Set-Content -Path $ingestionBat -Encoding ASCII

# Shared helper: ensure the Next.js dev server is up, then open the URL once
# it responds HTTP 200. Handles cold-start Next.js compilation gracefully.
$waitPs1 = Join-Path $launcherDir 'WaitForDevServer.ps1'
@'
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AppDir,
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][string]$Url,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'SilentlyContinue'

$listening = $false
try {
    $listening = (Get-NetTCPConnection -State Listen -LocalPort $Port).Count -gt 0
} catch { $listening = $false }

if (-not $listening) {
    Write-Host "Starting Next.js dev server in $AppDir ..." -ForegroundColor Cyan
    Start-Process cmd -ArgumentList "/k","cd /d `"$AppDir`" && npm run dev"
}

Write-Host "Waiting for $Url ..." -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch { }
    Start-Sleep -Seconds 1
}

if ($ok) {
    Write-Host "Service ready at $Url" -ForegroundColor Green
} else {
    Write-Host "Service did not respond on $Url within $TimeoutSeconds s." -ForegroundColor Yellow
    Write-Host "Opening URL anyway; reload the page once the dev console shows 'Ready'." -ForegroundColor Yellow
}
Start-Process $Url
'@ | Set-Content -Path $waitPs1 -Encoding ASCII

$mainBat = Join-Path $launcherDir 'open-main-dashboard.bat'
@"
@echo off
REM Opens VFSOC Main Dashboard, starting the Next.js dev server if needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "$waitPs1" -AppDir "$siemPath" -Port $mainPort -Url "$mainUrl"
"@ | Set-Content -Path $mainBat -Encoding ASCII

$adminBat = Join-Path $launcherDir 'open-admin-dashboard.bat'
@"
@echo off
REM Opens VFSOC Admin Dashboard, starting the Next.js dev server if needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "$waitPs1" -AppDir "$adminPath" -Port $adminPort -Url "$adminUrl"
"@ | Set-Content -Path $adminBat -Encoding ASCII

# -----------------------------------------------------------------------------
# Build the shortcuts
# -----------------------------------------------------------------------------
$shell = New-Object -ComObject WScript.Shell

function New-VfsocShortcut {
    param(
        [string]$Name,
        [string]$Target,
        [string]$ArgumentString,
        [string]$Description,
        [string]$IconLocation
    )
    $path = Join-Path $desktop "$Name.lnk"
    if ((Test-Path $path) -and -not $Force) {
        Write-VfsocWarn "$Name.lnk already exists (use -Force to overwrite)"
        return
    }
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath = $Target
    $sc.Arguments = $ArgumentString
    $sc.WorkingDirectory = Split-Path $Target
    $sc.Description = $Description
    if ($IconLocation) { $sc.IconLocation = $IconLocation }
    $sc.WindowStyle = 7   # Minimized
    $sc.Save()
    Write-VfsocOk "Created shortcut: $path"
}

if ($Remove) {
    Write-VfsocBanner "Removing VFSOC desktop shortcuts"
    foreach ($n in @('VFSOC Ingestion', 'VFSOC Main Dashboard', 'VFSOC Admin')) {
        $p = Join-Path $desktop "$n.lnk"
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-VfsocOk "Removed $p"
        }
    }
    return
}

Write-VfsocBanner "Installing VFSOC desktop shortcuts"
Write-Host ("  Extras root   : {0}" -f $extrasRoot) -ForegroundColor DarkGray
Write-Host ("  Projects root : {0}" -f $projectsRoot) -ForegroundColor DarkGray

# Icon for browser-based shortcuts: use the default Windows browser icon via
# IconLocation %SystemRoot%\System32\SHELL32.dll,<index>.
$iconBrowser  = "$env:SystemRoot\System32\SHELL32.dll,14"
$iconDesktop  = "$env:SystemRoot\System32\SHELL32.dll,15"
$iconAdmin    = "$env:SystemRoot\System32\SHELL32.dll,165"

New-VfsocShortcut -Name 'VFSOC Ingestion' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$ingestionBat`"" `
                  -Description 'VFSOC Ingestion - connectors and data flow' `
                  -IconLocation $iconDesktop

New-VfsocShortcut -Name 'VFSOC Main Dashboard' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$mainBat`"" `
                  -Description 'VFSOC Main Dashboard - alerts, fleet overview, investigations' `
                  -IconLocation $iconBrowser

New-VfsocShortcut -Name 'VFSOC Admin' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$adminBat`"" `
                  -Description 'VFSOC Admin - users, mobility assets, asset-connector links' `
                  -IconLocation $iconAdmin

Write-VfsocBanner "Done"
Write-Host "Look at your Desktop. Double-click any of the three icons to launch its app." -ForegroundColor White
