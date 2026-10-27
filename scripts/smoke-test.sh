#!/usr/bin/env bash
# Checks a running Mai Ru server through Nginx.
# Usage: scripts/smoke-test.sh [host] [--expect-https | --expect-http]
#   host            default: localhost
#   --expect-https  HTTPS must work and port 80 must redirect to it
#   --expect-http   plain HTTP must work (HTTPS is not enabled)
#   neither         HTTPS is expected when https://host/api/v1/health answers 200
# Run it from another machine (without a kit folder) to test what a phone would see.
set -euo pipefail

host=localhost
mode=auto
for arg in "$@"; do
  case "$arg" in
    --expect-https) mode=https ;;
    --expect-http) mode=http ;;
    -h | --help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) host="$arg" ;;
  esac
done
failures=0

# status [curl options] URL -> HTTP status code; the certificate is not checked because a
# self-signed one is allowed. 000 means no answer.
status() { curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; }

check() { # description expected actual
  if [ "$2" = "$3" ]; then
    printf 'PASS  %s (%s)\n' "$1" "$3"
  else
    printf 'FAIL  %s: expected %s, got %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

if [ "$mode" = auto ]; then
  if [ "$(status "https://$host/api/v1/health")" = 200 ]; then mode=https; else mode=http; fi
fi

if [ "$mode" = https ]; then
  scheme=https
  check "GET https://$host/api/v1/health" 200 "$(status "https://$host/api/v1/health")"
  check "http://$host/api/v1/health redirects to HTTPS" 301 "$(status "http://$host/api/v1/health")"
else
  scheme=http
  check "GET http://$host/api/v1/health" 200 "$(status "http://$host/api/v1/health")"
  echo "INFO  HTTPS is not enabled, so it is not checked"
fi
check "$scheme://$host/internal/v1/matching-pool is blocked" 404 "$(status "$scheme://$host/internal/v1/matching-pool")"

# The internal services must not be published on the host (exit 7 = refused, 28 = timed out)
for port in 3000 8000 5432 9000 9001; do
  rc=0
  curl -s -o /dev/null --connect-timeout 3 "http://$host:$port/" || rc=$?
  if [ "$rc" = 7 ] || [ "$rc" = 28 ]; then
    printf 'PASS  port %s is not reachable\n' "$port"
  else
    printf 'FAIL  port %s answered (curl exit %s)\n' "$port" "$rc"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "Smoke test failed: $failures check(s)."
  exit 1
fi
echo "Smoke test passed."
