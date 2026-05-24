# =============================================================================
#  VFSOC :: One-time setup
# -----------------------------------------------------------------------------
#  - Verifies prerequisites (Docker, Node, Python, .NET)
#  - Writes per-project .env / appsettings files from vfsoc.config.json
#  - Starts PostgreSQL + OpenSearch in Docker
#  - Initialises the unified database schema
#  - Installs Node dependencies for SIEM and Admin
#  - Installs Python dependencies for log generation and ML inference
#
#  Re-running is safe: every step is idempotent.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$SkipDocker,
    [switch]$SkipNode,
    [switch]$SkipPython,
    [switch]$SkipDotnet
)

. "$PSScriptRoot\lib\Common.ps1"

$root = Get-VfsocRoot
$config = Get-VfsocConfig

Write-VfsocBanner "Setup"

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
Write-VfsocStep "Checking prerequisites ..."

$missing = @()
if (-not (Test-Command 'docker'))  { $missing += 'docker (Docker Desktop)' }
if (-not (Test-Command 'node'))    { $missing += 'node (Node.js 18+)' }
if (-not (Test-Command 'npm'))     { $missing += 'npm' }
if (-not (Test-Command 'python'))  { $missing += 'python (3.11+)' }
if (-not (Test-Command 'dotnet'))  { $missing += 'dotnet (.NET 8 SDK)' }

if ($missing.Count -gt 0) {
    Write-VfsocWarn "The following tools were not found on PATH:"
    foreach ($m in $missing) { Write-Host "       - $m" -ForegroundColor Magenta }
    Write-Host "       The setup script will continue, but the affected steps may fail." -ForegroundColor Magenta
} else {
    Write-VfsocOk "All prerequisites detected."
}

# ---------------------------------------------------------------------------
# 2. Write per-project .env files
# ---------------------------------------------------------------------------
Write-VfsocStep "Writing per-project environment files ..."

$pg = $config.services.postgres
$jwt = $config.auth.jwt_secret
$mainUrl = $config.services.main_dashboard.url
$adminUrl = $config.services.admin_dashboard.url

$siemEnv = @"
DB_USER=$($pg.user)
DB_HOST=$($pg.host)
DB_NAME=$($pg.database)
DB_PASSWORD=$($pg.password)
DB_PORT=$($pg.port)
JWT_SECRET=$jwt
OPENSEARCH_URL=$($config.services.opensearch.url)
NODE_ENV=development
NEXT_PUBLIC_ADMIN_DASHBOARD_URL=$adminUrl
"@
$siemEnvPath = Join-Path $root 'VFSOC-SIEM\.env.local'
Set-Content -Path $siemEnvPath -Value $siemEnv -Encoding UTF8
Write-VfsocOk "Wrote $siemEnvPath"

$adminEnv = @"
DB_USER=$($pg.user)
DB_HOST=$($pg.host)
DB_NAME=$($pg.database)
DB_PASSWORD=$($pg.password)
DB_PORT=$($pg.port)
JWT_SECRET=$jwt
NODE_ENV=development
NEXT_PUBLIC_MAIN_DASHBOARD_URL=$mainUrl
"@
$adminEnvPath = Join-Path $root 'VFSOC-Admin\.env.local'
Set-Content -Path $adminEnvPath -Value $adminEnv -Encoding UTF8
Write-VfsocOk "Wrote $adminEnvPath"

# ---------------------------------------------------------------------------
# 3. Docker infra (Postgres + OpenSearch)
# ---------------------------------------------------------------------------
if (-not $SkipDocker -and (Test-Command 'docker')) {
    Write-VfsocStep "Starting PostgreSQL and OpenSearch in Docker ..."
    $composePath = Join-Path $root 'scripts\lib\docker-compose.infra.yml'
    if (-not (Test-Path $composePath)) {
        Write-VfsocErr "Missing $composePath"
    } else {
        try {
            docker compose -f $composePath -p vfsoc up -d | Out-Host
            Write-VfsocOk "Docker infra is starting in background."
        } catch {
            Write-VfsocErr "Docker compose failed: $($_.Exception.Message)"
        }
    }

    # Wait for Postgres to accept connections.
    Write-VfsocStep "Waiting for PostgreSQL on port $($pg.port) ..."
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and -not (Test-PortInUse $pg.port)) { Start-Sleep -Seconds 2 }
    if (Test-PortInUse $pg.port) { Write-VfsocOk "PostgreSQL is up." }
    else { Write-VfsocWarn "PostgreSQL is not responding yet; schema apply may fail. Re-run setup later." }

    # Apply schema (idempotent via IF NOT EXISTS / ON CONFLICT).
    $schemaPath = Join-Path $root 'scripts\lib\db-schema.sql'
    Write-VfsocStep "Applying unified database schema ..."
    try {
        Get-Content $schemaPath -Raw | docker exec -i vfsoc-postgres psql -U $pg.user -d $pg.database 2>&1 | Out-Host
        Write-VfsocOk "Schema applied to database '$($pg.database)'."
    } catch {
        Write-VfsocWarn "Schema apply failed; you can re-run later with: scripts\apply-schema.ps1"
    }
} elseif ($SkipDocker) {
    Write-VfsocWarn "Skipped Docker setup as requested."
} else {
    Write-VfsocWarn "Docker not installed; install Docker Desktop and re-run setup."
}

# ---------------------------------------------------------------------------
# 4. Node dependencies
# ---------------------------------------------------------------------------
if (-not $SkipNode -and (Test-Command 'npm')) {
    foreach ($app in @('VFSOC-SIEM', 'VFSOC-Admin')) {
        $dir = Join-Path $root $app
        Write-VfsocStep "npm install in $app ..."
        Push-Location $dir
        try {
            npm install --no-audit --no-fund | Out-Host
            Write-VfsocOk "Installed $app dependencies."
        } catch {
            Write-VfsocErr "npm install failed for $app : $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    }
} elseif ($SkipNode) {
    Write-VfsocWarn "Skipped Node installs as requested."
}

# ---------------------------------------------------------------------------
# 5. Python dependencies
# ---------------------------------------------------------------------------
if (-not $SkipPython -and (Test-Command 'python')) {
    foreach ($pyProj in @('VFSOC-log_generation', 'VFSOC-ML-Models')) {
        $dir = Join-Path $root $pyProj
        $req = Join-Path $dir 'requirements.txt'
        if (-not (Test-Path $req)) { continue }
        Write-VfsocStep "pip install in $pyProj ..."
        Push-Location $dir
        try {
            if (-not (Test-Path .venv)) { python -m venv .venv | Out-Host }
            & .\.venv\Scripts\python.exe -m pip install --quiet --upgrade pip
            & .\.venv\Scripts\python.exe -m pip install --quiet -r requirements.txt
            Write-VfsocOk "Installed $pyProj Python dependencies."
        } catch {
            Write-VfsocErr "pip install failed for $pyProj : $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    }
} elseif ($SkipPython) {
    Write-VfsocWarn "Skipped Python installs as requested."
}

# ---------------------------------------------------------------------------
# 6. .NET build (Ingestion WPF)
# ---------------------------------------------------------------------------
if (-not $SkipDotnet -and (Test-Command 'dotnet')) {
    Write-VfsocStep "dotnet build VFSOC-Ingestion ..."
    $csproj = Join-Path $root 'VFSOC-Ingestion\src\VFSOC.Ingestion.Client\VFSOC.Ingestion.Client.csproj'
    if (Test-Path $csproj) {
        try {
            dotnet build $csproj -c Debug | Out-Host
            Write-VfsocOk "VFSOC-Ingestion built."
        } catch {
            Write-VfsocErr "dotnet build failed: $($_.Exception.Message)"
        }
    } else {
        Write-VfsocWarn "csproj not found at $csproj"
    }
} elseif ($SkipDotnet) {
    Write-VfsocWarn "Skipped .NET build as requested."
}

Write-VfsocBanner "Setup complete"
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Install desktop shortcuts:  scripts\Install-Shortcuts.ps1" -ForegroundColor Gray
Write-Host "  2. Start everything:           scripts\start-vfsoc.ps1" -ForegroundColor Gray
Write-Host ''
Write-Host "Default credentials:" -ForegroundColor White
Write-Host "  admin / admin@123       (full admin)" -ForegroundColor Gray
Write-Host "  operator / analyst@123  (asset/connector management)" -ForegroundColor Gray
Write-Host "  viewer / analyst@123    (read-only admin)" -ForegroundColor Gray
Write-Host "  analyst / analyst@123   (SIEM analyst)" -ForegroundColor Gray
Write-Host ''
