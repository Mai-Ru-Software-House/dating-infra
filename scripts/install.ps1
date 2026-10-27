# Installs the Mai Ru server stack: checks the host, creates .env with generated secrets
# (only when it does not exist yet), pulls the images and starts everything. Safe to run
# again: an existing .env and certificate are never replaced.
#
# HTTPS is enabled when nginx\certs\ holds cert.crt and cert.key: port 80 then redirects to
# HTTPS. Without them the server answers on plain HTTP only. Add the certificate and run
# this script again to switch.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\install.ps1 [-Address <name-or-ip>] [-SelfSigned]
#   -Address     address the phones will use; goes into the printed URLs and the
#                self-signed certificate (default: localhost)
#   -SelfSigned  create a self-signed certificate when there is none, which enables HTTPS.
#                Phones do not trust it, so the Android app will not connect
param(
    [string]$Address = 'localhost',
    [switch]$SelfSigned
)
. "$PSScriptRoot\lib.ps1"

if ($Address -notmatch '^[A-Za-z0-9.:-]+$') {
    Stop-Script '-Address may only contain letters, digits, dots, colons and dashes'
}

Write-Info 'Checking the host'
Test-Arch
Test-DockerReady
Write-Host 'Docker Desktop must start when you sign in, or the stack will not come back after a reboot (Docker Desktop > Settings > General).'

Write-Info 'Preparing .env'
$envPath = Join-Path $script:KitDir '.env'
if (-not (Test-Path $envPath) -and (Test-VolumesExist)) {
    Stop-Script "Found data from an earlier install (Docker volume $script:PostgresVolume) but this folder has no .env. New secrets would not match that database. Copy .env and nginx\certs\ from the previous kit folder, or remove the old data first with its scripts\uninstall.ps1 -DeleteVolumes."
}
if (Test-Path $envPath) {
    Write-Host '.env already exists, keeping it.'
} else {
    $example = Join-Path $script:KitDir '.env.example'
    if (-not (Test-Path $example)) { Stop-Script ".env.example is missing from $script:KitDir" }
    $lines = [System.IO.File]::ReadAllLines($example)
    Write-EnvLines $lines
}
# Fills only values that still hold the template placeholder, so a re-run never changes a
# password that PostgreSQL has already been initialised with
function Set-SecretIfPlaceholder($Key, $Bytes) {
    $current = Get-EnvValue $Key
    if ($current -eq '' -or $current.StartsWith('your_')) {
        Set-EnvValue $Key (New-RandomHex $Bytes)
        Write-Host "Generated $Key"
    }
}
Set-SecretIfPlaceholder 'POSTGRES_PASSWORD' 32
Set-SecretIfPlaceholder 'RUSTFS_ACCESS_KEY' 16
Set-SecretIfPlaceholder 'RUSTFS_SECRET_KEY' 32
Set-SecretIfPlaceholder 'JWT_SECRET' 32

Write-Info 'Preparing HTTPS'
$certDir = Join-Path $script:KitDir 'nginx\certs'
New-Item -ItemType Directory -Force -Path $certDir | Out-Null
$hasCrt = Test-Path (Join-Path $certDir 'cert.crt')
$hasKey = Test-Path (Join-Path $certDir 'cert.key')
if ($hasCrt -and $hasKey) {
    Write-Host 'Found nginx\certs\cert.crt and cert.key.'
    $https = $true
} elseif ($hasCrt -or $hasKey) {
    Stop-Script 'nginx\certs\ has only one of cert.crt and cert.key. HTTPS needs both.'
} elseif ($SelfSigned) {
    $san = 'DNS:localhost,IP:127.0.0.1'
    if ($Address -match '^[0-9.]+$') { $san = "$san,IP:$Address" }
    elseif ($Address -ne 'localhost') { $san = "$san,DNS:$Address" }
    # openssl runs in a container so the host does not need it. The command has single
    # quotes only: double quotes inside an argument are mangled by Windows PowerShell 5.1
    $openssl = "openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj '/CN=$Address' -addext 'subjectAltName=$san' -keyout /certs/cert.key -out /certs/cert.crt 2>/dev/null && chmod 644 /certs/cert.crt /certs/cert.key"
    docker run --rm --entrypoint sh -v "${certDir}:/certs" $script:ToolboxImage -c $openssl
    if ($LASTEXITCODE -ne 0) { Stop-Script 'Could not create the self-signed certificate' }
    Write-Host "Created a self-signed certificate for $Address (valid 825 days). Browsers and phones will not trust it."
    $https = $true
} else {
    Write-Host 'No certificate in nginx\certs\, so HTTPS is off and the server answers on plain HTTP.'
    $https = $false
}
# NGINX_CONF follows the certificate on every run, so adding or removing it and running
# this script again is all it takes to switch
if ($https) { Set-EnvValue 'NGINX_CONF' './nginx/nginx.prod.conf' }
else { Set-EnvValue 'NGINX_CONF' './nginx/nginx.prod.http.conf' }

Write-Info 'Checking the compose file'
Invoke-Compose config --quiet
if ($LASTEXITCODE -ne 0) { Stop-Script 'docker compose rejected the configuration (see above)' }

Write-Info 'Pulling images'
Invoke-Compose pull
if ($LASTEXITCODE -ne 0) {
    Stop-Script 'Image pull failed. If the packages are private, sign in first: docker login ghcr.io -u <github-user> (use a token as the password)'
}

Write-Info 'Starting the stack (waiting up to 4 minutes for every service to be healthy)'
Invoke-Compose up -d --wait --wait-timeout 240
if ($LASTEXITCODE -ne 0) {
    Invoke-Compose ps -a
    Invoke-Compose logs --no-color --tail 30
    Stop-Script 'The stack did not become healthy. See the logs above.'
}
Invoke-Compose ps

Write-Info 'Running the smoke test'
$smokeArgs = @{ Address = $Address }
if ($https) { $smokeArgs.ExpectHttps = $true } else { $smokeArgs.ExpectHttp = $true }
& "$PSScriptRoot\smoke-test.ps1" @smokeArgs
if ($LASTEXITCODE -ne 0) { Write-Warn 'The smoke test failed, see above.' }

Write-Host ''
Write-Host 'Mai Ru server is running.'
if ($https) {
    Write-Host "  API: https://$Address/api/v1 (port 80 redirects to it)"
    Write-Host "Build the phone app with EXPO_PUBLIC_API_BASE_URL=https://$Address/api/v1"
    Write-Host 'A certificate the phones do not trust (such as a self-signed one) will make the app fail.'
} else {
    Write-Host "  API: http://$Address/api/v1"
    Write-Host "Build the phone app with EXPO_PUBLIC_API_BASE_URL=http://$Address/api/v1"
    Write-Host 'To enable HTTPS, put cert.crt and cert.key in nginx\certs\ and run scripts\install.ps1 again.'
}
exit 0
