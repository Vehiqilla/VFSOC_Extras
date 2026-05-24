# -----------------------------------------------------------------------------
# Common helpers for all VFSOC scripts. Dot-source this file:
#     . "$PSScriptRoot\lib\Common.ps1"
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

function Get-VfsocRoot {
    # The repository root sits one level above /scripts.
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-VfsocConfig {
    $root = Get-VfsocRoot
    $configPath = Join-Path $root 'vfsoc.config.json'
    if (-not (Test-Path $configPath)) {
        throw "vfsoc.config.json not found at $configPath"
    }
    return (Get-Content $configPath -Raw | ConvertFrom-Json)
}

function Write-VfsocBanner($title) {
    $line = '=' * 70
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host (" VFSOC :: $title") -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
}

function Write-VfsocStep($message) {
    Write-Host ("  [>] {0}" -f $message) -ForegroundColor Yellow
}

function Write-VfsocOk($message) {
    Write-Host ("  [OK] {0}" -f $message) -ForegroundColor Green
}

function Write-VfsocWarn($message) {
    Write-Host ("  [!] {0}" -f $message) -ForegroundColor Magenta
}

function Write-VfsocErr($message) {
    Write-Host ("  [ERROR] {0}" -f $message) -ForegroundColor Red
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Test-PortInUse($port) {
    try {
        $sock = New-Object System.Net.Sockets.TcpClient
        $sock.Connect('127.0.0.1', [int]$port)
        $sock.Close()
        return $true
    } catch {
        return $false
    }
}

function Wait-ForUrl($url, $timeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Stop-VfsocProcessOnPort($port) {
    try {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($null -ne $conn) {
            $pids = $conn.OwningProcess | Select-Object -Unique
            foreach ($p in $pids) {
                try {
                    Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
                    Write-VfsocOk "Stopped PID $p (port $port)"
                } catch { }
            }
        }
    } catch { }
}

function Start-VfsocService {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$LogFile,
        [int]$WaitForPort = 0
    )
    Write-VfsocStep "Starting $Name ..."
    if ($WaitForPort -gt 0 -and (Test-PortInUse $WaitForPort)) {
        Write-VfsocOk "$Name appears to already be running on port $WaitForPort"
        return
    }
    $params = @{
        FilePath         = $Command
        ArgumentList     = $Arguments
        WorkingDirectory = $WorkingDirectory
        WindowStyle      = 'Normal'
        PassThru         = $true
    }
    if ($LogFile) {
        # Redirect output to keep the launcher console clean.
        $params.RedirectStandardOutput = $LogFile
        $params.RedirectStandardError  = "$LogFile.err"
        $params.NoNewWindow            = $true
    }
    try {
        $proc = Start-Process @params
        Write-VfsocOk "$Name started (PID $($proc.Id))"
    } catch {
        Write-VfsocErr "Failed to start $Name : $($_.Exception.Message)"
    }
}
