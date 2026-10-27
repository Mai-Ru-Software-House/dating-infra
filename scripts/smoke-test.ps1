# Checks a running Mai Ru server through Nginx.
# Usage: scripts\smoke-test.ps1 [-Address <host>] [-ExpectHttps | -ExpectHttp]
#   -Address      default: localhost
#   -ExpectHttps  HTTPS must work and port 80 must redirect to it
#   -ExpectHttp   plain HTTP must work (HTTPS is not enabled)
#   neither       HTTPS is expected when https://<host>/api/v1/health answers 200
# Run it from another machine (without a kit folder) to test what a phone would see.
param(
    [string]$Address = 'localhost',
    [switch]$ExpectHttps,
    [switch]$ExpectHttp
)
. "$PSScriptRoot\lib.ps1"

$script:Failures = 0

# HTTP status code; the certificate is not checked because a self-signed one is allowed.
# 000 means no answer. curl.exe ships with Windows 10 and 11.
function Get-Status($Url) {
    return "$(curl.exe -sk -o NUL -w '%{http_code}' --max-time 10 $Url)"
}

function Test-Check($Description, $Expected, $Actual) {
    if ("$Expected" -eq "$Actual") {
        Write-Host "PASS  $Description ($Actual)"
    } else {
        Write-Host "FAIL  $Description`: expected $Expected, got $Actual"
        $script:Failures++
    }
}

if ($ExpectHttps) { $https = $true }
elseif ($ExpectHttp) { $https = $false }
else { $https = ((Get-Status "https://$Address/api/v1/health") -eq '200') }

if ($https) {
    $scheme = 'https'
    Test-Check "GET https://$Address/api/v1/health" 200 (Get-Status "https://$Address/api/v1/health")
    Test-Check "http://$Address/api/v1/health redirects to HTTPS" 301 (Get-Status "http://$Address/api/v1/health")
} else {
    $scheme = 'http'
    Test-Check "GET http://$Address/api/v1/health" 200 (Get-Status "http://$Address/api/v1/health")
    Write-Host 'INFO  HTTPS is not enabled, so it is not checked'
}
Test-Check "${scheme}://$Address/internal/v1/matching-pool is blocked" 404 (Get-Status "${scheme}://$Address/internal/v1/matching-pool")

# The internal services must not be published on the host (exit 7 = refused, 28 = timed out)
foreach ($port in 3000, 8000, 5432, 9000, 9001) {
    curl.exe -s -o NUL --connect-timeout 3 "http://${Address}:$port/" *> $null
    if ($LASTEXITCODE -eq 7 -or $LASTEXITCODE -eq 28) {
        Write-Host "PASS  port $port is not reachable"
    } else {
        Write-Host "FAIL  port $port answered (curl exit $LASTEXITCODE)"
        $script:Failures++
    }
}

if ($script:Failures -gt 0) {
    Write-Host "Smoke test failed: $($script:Failures) check(s)."
    exit 1
}
Write-Host 'Smoke test passed.'
exit 0
