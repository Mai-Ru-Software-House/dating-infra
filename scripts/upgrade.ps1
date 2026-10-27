# Upgrades a running installation to a new release: backs up, sets the image tags in .env,
# pulls the images and restarts. The api container applies pending database migrations
# when it starts.
#
# Usage: scripts\upgrade.ps1 [-Version 1.0.1] [-SkipBackup]
#   -Version  release to install (default: the version in this kit's .env.example)
# To upgrade: unzip the new kit, copy .env and nginx\certs\ (and backups\ if you like) from
# the old kit folder into the new one, cd into the new folder and run this script.
#
# Rollback: put the tags from backups\<timestamp>\images.txt back into .env, run
# docker compose -f docker-compose.prod.yaml up -d, and restore the backup if the
# new version changed the database (see the README).
param(
    [string]$Version = '',
    [switch]$SkipBackup
)
. "$PSScriptRoot\lib.ps1"

Test-DockerReady
Assert-EnvFile

if ($Version -eq '') {
    $tag = Get-EnvValue 'BACKEND_IMAGE' '.env.example'
    $Version = $tag.Substring($tag.LastIndexOf(':') + 1)
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Stop-Script "Version must look like 1.0.1, got '$Version'" }

# Image name without the tag: the tag is whatever follows the last colon
function Get-Retagged($Image) { return $Image.Substring(0, $Image.LastIndexOf(':')) + ":$Version" }
$oldBackend = Get-EnvValue 'BACKEND_IMAGE'
$oldEngine = Get-EnvValue 'MATCH_ENGINE_IMAGE'
$newBackend = Get-Retagged $oldBackend
$newEngine = Get-Retagged $oldEngine
Write-Host "BACKEND_IMAGE:      $oldBackend -> $newBackend"
Write-Host "MATCH_ENGINE_IMAGE: $oldEngine -> $newEngine"

if ($SkipBackup) {
    Write-Warn 'Skipping the backup'
} else {
    Write-Info 'Backing up first'
    & "$PSScriptRoot\backup.ps1"
    if ($LASTEXITCODE -ne 0) { Stop-Script 'The backup failed, nothing was changed.' }
}

Set-EnvValue 'BACKEND_IMAGE' $newBackend
Set-EnvValue 'MATCH_ENGINE_IMAGE' $newEngine

Write-Info 'Pulling images'
Invoke-Compose pull
if ($LASTEXITCODE -ne 0) {
    Set-EnvValue 'BACKEND_IMAGE' $oldBackend
    Set-EnvValue 'MATCH_ENGINE_IMAGE' $oldEngine
    Stop-Script 'Pull failed. .env still points at the previous images and nothing was restarted.'
}

Write-Info 'Restarting'
Invoke-Compose up -d --wait --wait-timeout 240 --remove-orphans
if ($LASTEXITCODE -ne 0) {
    Invoke-Compose ps -a
    Invoke-Compose logs --no-color --tail 30 api
    Stop-Script "The new version did not become healthy. Previous images: $oldBackend and $oldEngine. Roll back as described at the top of scripts\upgrade.ps1."
}
Invoke-Compose ps

Write-Info 'Running the smoke test'
& "$PSScriptRoot\smoke-test.ps1" -Address localhost
if ($LASTEXITCODE -ne 0) { Write-Warn 'The smoke test failed, see above.' }
Write-Info "Upgraded to $Version"
exit 0
