# Stops and removes the Mai Ru containers. The data volumes (database and photos) are
# deleted only after you confirm. .env, the certificate and backups\ are never touched.
#
# Usage: scripts\uninstall.ps1 [-DeleteVolumes | -KeepVolumes]
#   no option       asks whether to delete the data volumes
#   -DeleteVolumes  deletes them without asking
#   -KeepVolumes    keeps them without asking
param(
    [switch]$DeleteVolumes,
    [switch]$KeepVolumes
)
. "$PSScriptRoot\lib.ps1"

if ($DeleteVolumes -and $KeepVolumes) { Stop-Script 'Use either -DeleteVolumes or -KeepVolumes, not both' }

Test-DockerReady
Assert-EnvFile

$delete = $DeleteVolumes
if (-not $DeleteVolumes -and -not $KeepVolumes) {
    Write-Host 'This removes the Mai Ru containers.'
    $answer = Read-Host 'Also DELETE the data volumes postgres-data and rustfs-data (all users, messages and photos)? Type "yes" to delete, anything else keeps them'
    $delete = ($answer -eq 'yes')
}

if ($delete) {
    Write-Info 'Removing containers, networks and data volumes'
    Invoke-Compose down --remove-orphans --volumes
} else {
    Write-Info 'Removing containers and networks, keeping the data volumes'
    Invoke-Compose down --remove-orphans
}
if ($LASTEXITCODE -ne 0) { Stop-Script 'docker compose down failed' }
Write-Info 'Done'
exit 0
