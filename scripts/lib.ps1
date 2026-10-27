# Shared helpers for the Mai Ru server scripts (Windows PowerShell 5.1 and PowerShell 7).
# Dot-sourced by the other scripts, not run directly. Keep this file ASCII only.

# Native commands (docker, curl.exe) do not stop a script on failure, so every call is
# followed by an explicit check of $LASTEXITCODE
$ErrorActionPreference = 'Continue'

$script:KitDir = Split-Path -Parent $PSScriptRoot
Set-Location $script:KitDir

$script:ComposeFile = 'docker-compose.prod.yaml'
# The postgres image is already part of the stack, so it doubles as the toolbox image
# (openssl, tar, gzip) and nothing besides Docker has to be installed on the host
$script:ToolboxImage = 'postgres:18'

function Write-Info($Message) { Write-Host "==> $Message" }
function Write-Warn($Message) { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
function Stop-Script($Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Invoke-Compose {
    docker compose -f (Join-Path $script:KitDir $script:ComposeFile) @args
}

# "v2.31.0-desktop.2" -> [version]"2.31.0"; a missing or unreadable value gives 0.0
function ConvertTo-CleanVersion($Text) {
    if ("$Text" -match '^v?(\d+(\.\d+){1,2})') { return [version]$Matches[1] }
    return [version]'0.0'
}

function Test-Arch {
    if ($env:MAIRU_SKIP_ARCH_CHECK -eq '1') { return }
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -ne 'AMD64') {
        Stop-Script "This host is $arch. Mai Ru images are built for 64-bit x86 (x86_64) only."
    }
}

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Stop-Script 'Docker is not installed. Install Docker Desktop (WSL 2 backend) first.'
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Stop-Script 'Cannot reach the Docker daemon. Start Docker Desktop and try again.'
    }
    $engine = ConvertTo-CleanVersion (docker version --format '{{.Server.Version}}')
    if ($engine -lt [version]'24.0') { Stop-Script "Docker Engine $engine is too old. Version 24 or newer is required." }
    $composeVersion = ConvertTo-CleanVersion (docker compose version --short)
    if ($composeVersion -lt [version]'2.20') {
        Stop-Script "Docker Compose $composeVersion is too old (or missing). Version 2.20 or newer is required."
    }
    $kernel = "$(docker info --format '{{.KernelVersion}}')"
    if ($kernel -notmatch 'WSL2|microsoft') {
        Write-Warn 'Docker Desktop does not seem to use the WSL 2 backend. WSL 2 is the supported setup.'
    }
}

# The data volumes outlive the kit folder, and PostgreSQL keeps the password it was first
# started with, so a new .env must never be generated while the old volumes exist
$script:PostgresVolume = 'mairu_postgres-data'
function Test-VolumesExist {
    docker volume inspect $script:PostgresVolume *> $null
    return ($LASTEXITCODE -eq 0)
}

function Assert-EnvFile {
    if (-not (Test-Path (Join-Path $script:KitDir '.env'))) {
        Stop-Script "No .env file in $script:KitDir. If this is a new kit folder for an upgrade, copy .env and nginx\certs\ from the previous kit folder first. Do not run install.ps1: it would generate new passwords that do not match the existing database."
    }
}

# UTF-8 without a byte order mark and with LF line endings: a BOM would become part of
# the first variable name in .env
function Write-EnvLines($Lines) {
    $path = Join-Path $script:KitDir '.env'
    $text = (($Lines -join "`n") + "`n")
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-EnvValue($Key, $File = '.env') {
    $path = Join-Path $script:KitDir $File
    $value = ''
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line.StartsWith("$Key=")) { $value = $line.Substring($Key.Length + 1) }
    }
    return $value
}

function Set-EnvValue($Key, $Value) {
    $path = Join-Path $script:KitDir '.env'
    $lines = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line.StartsWith("$Key=")) {
            $lines.Add("$Key=$Value")
            $found = $true
        } else {
            $lines.Add($line)
        }
    }
    if (-not $found) { $lines.Add("$Key=$Value") }
    Write-EnvLines $lines.ToArray()
}

# Returns 2*Bytes hex characters from the system random source
function New-RandomHex($Bytes) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buffer)
    $rng.Dispose()
    return (($buffer | ForEach-Object { $_.ToString('x2') }) -join '')
}
