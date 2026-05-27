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
