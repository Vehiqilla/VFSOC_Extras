# =============================================================================
#  VFSOC :: Apply the unified database schema (idempotent)
# =============================================================================

[CmdletBinding()]
param()

. "$PSScriptRoot\lib\Common.ps1"

$extrasRoot = Get-VfsocRoot
$config     = Get-VfsocConfig
$pg         = $config.services.postgres

Write-VfsocBanner "Applying database schema"

$schemaPath = Join-Path $extrasRoot 'scripts\lib\db-schema.sql'
if (-not (Test-Path $schemaPath)) {
    throw "Schema file not found at $schemaPath"
}

if (-not (Test-Command 'docker')) {
    Write-VfsocErr "Docker is not installed. Install Docker Desktop or apply the schema manually with psql."
    exit 1
}

# Look up the running postgres container (compose may name it vfsoc-postgres or vfsoc_postgres).
$container = (docker ps --filter "name=postgres" --format '{{.Names}}' | Select-Object -First 1)
if (-not $container) {
    Write-VfsocWarn "No postgres container is running. Starting infra ..."
    docker compose -f (Join-Path $extrasRoot 'scripts\lib\docker-compose.infra.yml') -p vfsoc up -d postgres | Out-Host
    Start-Sleep -Seconds 5
    $container = (docker ps --filter "name=postgres" --format '{{.Names}}' | Select-Object -First 1)
    if (-not $container) { throw "Could not find a running postgres container." }
}

Get-Content $schemaPath -Raw | docker exec -i -e "PGPASSWORD=$($pg.password)" $container psql -U $pg.user -d $pg.database 2>&1 | Out-Host

Write-VfsocOk "Schema applied to database '$($pg.database)' on container '$container'."
