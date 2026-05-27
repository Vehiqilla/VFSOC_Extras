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

# Helper batch + PowerShell scripts the shortcuts call into. These are
# version-controlled under scripts\launchers and contain all of the logic
# (Docker bring-up, app start, watchdog cleanup). This install script just
# verifies they are present.
$launcherDir   = Join-Path $extrasRoot 'scripts\launchers'
$ingestionBat  = Join-Path $launcherDir 'open-ingestion.bat'
$mainBat       = Join-Path $launcherDir 'open-main-dashboard.bat'
$adminBat      = Join-Path $launcherDir 'open-admin-dashboard.bat'
$launchPs1     = Join-Path $launcherDir 'VFSOC-Launch.ps1'
$cleanupPs1    = Join-Path $launcherDir 'VFSOC-Cleanup.ps1'

foreach ($f in @($launchPs1, $cleanupPs1, $ingestionBat, $mainBat, $adminBat)) {
    if (-not (Test-Path $f)) {
        Write-VfsocErr "Launcher file missing: $f"
        Write-VfsocErr "Restore the launchers folder before installing shortcuts."
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Build the shortcuts
# -----------------------------------------------------------------------------
$shell = New-Object -ComObject WScript.Shell

function New-VfsocShortcut {
    param(
        [string]$Name,
        [string]$Target,
        [string]$ArgumentString,
        [string]$WorkingDir,
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
    $sc.WorkingDirectory = if ($WorkingDir) { $WorkingDir } else { Split-Path $Target }
    $sc.Description = $Description
    if ($IconLocation) { $sc.IconLocation = $IconLocation }
    $sc.WindowStyle = 1   # Normal window so the user sees the launcher output
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

# Branded Vehiqilla icons per app. Auto-build them once if the icons folder
# is empty so a fresh install gets pretty shortcuts without an extra step.
$iconDir = Join-Path $extrasRoot 'assets\icons'
$iconIngestion = Join-Path $iconDir 'vfsoc-ingestion.ico'
$iconMain      = Join-Path $iconDir 'vfsoc-main.ico'
$iconAdmin     = Join-Path $iconDir 'vfsoc-admin.ico'
$missingIcons  = -not (Test-Path $iconIngestion) -or
                 -not (Test-Path $iconMain)      -or
                 -not (Test-Path $iconAdmin)
if ($missingIcons) {
    Write-Host "  Building Vehiqilla-branded shortcut icons..." -ForegroundColor DarkGray
    & (Join-Path $PSScriptRoot 'Build-Icons.ps1')
}

New-VfsocShortcut -Name 'VFSOC Ingestion' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$ingestionBat`"" `
                  -WorkingDir $launcherDir `
                  -Description 'VFSOC Ingestion - connectors and data flow' `
                  -IconLocation $iconIngestion

New-VfsocShortcut -Name 'VFSOC Main Dashboard' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$mainBat`"" `
                  -WorkingDir $launcherDir `
                  -Description 'VFSOC Main Dashboard - alerts, fleet overview, investigations' `
                  -IconLocation $iconMain

New-VfsocShortcut -Name 'VFSOC Admin' `
                  -Target "$env:ComSpec" `
                  -ArgumentString "/c `"$adminBat`"" `
                  -WorkingDir $launcherDir `
                  -Description 'VFSOC Admin - users, mobility assets, asset-connector links' `
                  -IconLocation $iconAdmin

Write-VfsocBanner "Done"
Write-Host "Look at your Desktop. Double-click any of the three icons to launch its app." -ForegroundColor White
