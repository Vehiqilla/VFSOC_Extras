# =============================================================================
#  VFSOC :: Apply the unified database schema (idempotent)
# =============================================================================

[CmdletBinding()]
param()

. "$PSScriptRoot\lib\Common.ps1"

$root = Get-VfsocRoot
$config = Get-VfsocConfig
$pg = $config.services.postgres

Write-VfsocBanner "Applying database schema"

$schemaPath = Join-Path $root 'scripts\lib\db-schema.sql'
if (-not (Test-Path $schemaPath)) {
    throw "Schema file not found at $schemaPath"
}

if (-not (Test-Command 'docker')) {
    Write-VfsocErr "Docker is not installed. Install Docker Desktop or apply the schema manually with psql."
    exit 1
}

# Make sure container is up.
$container = 'vfsoc-postgres'
$running = docker ps --filter "name=$container" --format '{{.Names}}'
if (-not $running) {
    Write-VfsocWarn "Container '$container' is not running. Starting infra ..."
    docker compose -f (Join-Path $root 'scripts\lib\docker-compose.infra.yml') -p vfsoc up -d postgres | Out-Host
    Start-Sleep -Seconds 5
}

Get-Content $schemaPath -Raw | docker exec -i $container psql -U $pg.user -d $pg.database 2>&1 | Out-Host

Write-VfsocOk "Schema applied to database '$($pg.database)'."
