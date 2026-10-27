# Backs up the database and the photo storage into backups\<timestamp>\ in the kit folder:
#   postgres.dump       pg_dump custom format (restore with pg_restore)
#   rustfs-data.tar.gz  the photo storage volume
#   images.txt          the image tags that were running, for a rollback
# The stack must be running. Usage: scripts\backup.ps1
. "$PSScriptRoot\lib.ps1"

Test-DockerReady
Assert-EnvFile

foreach ($service in 'postgres', 'rustfs') {
    $running = "$(Invoke-Compose ps --status running -q $service)"
    if ($running.Trim() -eq '') {
        Stop-Script "The $service service is not running. Start the stack first (docker compose -f $script:ComposeFile up -d)."
    }
}

$dest = Join-Path $script:KitDir ("backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Info 'Dumping the database'
# The dump is written inside the container and copied out: a PowerShell redirect (>)
# would re-encode the binary data
Invoke-Compose exec -T postgres pg_dump -U app -d dating_app -Fc -f /tmp/dating_app.dump
if ($LASTEXITCODE -ne 0) { Stop-Script 'pg_dump failed' }
Invoke-Compose cp postgres:/tmp/dating_app.dump (Join-Path $dest 'postgres.dump')
if ($LASTEXITCODE -ne 0) { Stop-Script 'Could not copy the dump out of the container' }
Invoke-Compose exec -T postgres rm -f /tmp/dating_app.dump

Write-Info 'Archiving the photo storage'
# --volumes-from reuses whatever volume the rustfs service has mounted at /data
$rustfs = "$(Invoke-Compose ps -q rustfs)".Trim()
docker run --rm --entrypoint tar --volumes-from $rustfs -v "${dest}:/backup" $script:ToolboxImage czf /backup/rustfs-data.tar.gz -C /data .
if ($LASTEXITCODE -ne 0) { Stop-Script 'Archiving the photo storage failed' }

Set-Content -Path (Join-Path $dest 'images.txt') -Encoding ASCII -Value @(
    "BACKEND_IMAGE=$(Get-EnvValue 'BACKEND_IMAGE')",
    "MATCH_ENGINE_IMAGE=$(Get-EnvValue 'MATCH_ENGINE_IMAGE')"
)

Write-Info "Backup written to $dest"
Get-ChildItem $dest | Format-Table Name, Length -AutoSize
exit 0
