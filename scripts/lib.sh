# shellcheck shell=bash
# Shared helpers for the Mai Ru server scripts (Linux and macOS). Sourced by the other
# scripts, not run directly. Written for bash 3.2, which is what macOS ships.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR"

COMPOSE_FILE="docker-compose.prod.yaml"
# The postgres image is already part of the stack, so it doubles as the toolbox image
# (openssl, tar, gzip) and nothing besides Docker has to be installed on the host
export TOOLBOX_IMAGE="postgres:18"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

compose() { docker compose -f "$KIT_DIR/$COMPOSE_FILE" "$@"; }

# version_ge 2.31.0 2.20 -> success when the first version is at least the second
version_ge() {
  local a b i x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x=${a[$i]:-0}
    y=${b[$i]:-0}
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 0
}

# Strips a leading v and anything after the numbers: v2.31.0-desktop.2 -> 2.31.0
clean_version() { printf '%s' "$1" | sed -e 's/^v//' -e 's/[^0-9.].*$//'; }

check_arch() {
  [ "${MAIRU_SKIP_ARCH_CHECK:-}" = "1" ] && return 0
  local machine
  machine=$(uname -m)
  # A shell started under Rosetta reports x86_64 on an Apple Silicon Mac
  if [ "$(uname -s)" = "Darwin" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
    machine=arm64
  fi
  case "$machine" in
    x86_64 | amd64) ;;
    *) die "This host is $machine. Mai Ru images are built for 64-bit x86 (x86_64) only." ;;
  esac
}

check_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Engine (Linux) or Docker Desktop (macOS) first."
  docker info >/dev/null 2>&1 || die "Cannot reach the Docker daemon. Start Docker (or Docker Desktop) and check that this user may run docker."
  local engine compose_version
  engine=$(clean_version "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 0)")
  compose_version=$(clean_version "$(docker compose version --short 2>/dev/null || echo 0)")
  version_ge "$engine" 24 || die "Docker Engine $engine is too old. Version 24 or newer is required."
  version_ge "$compose_version" 2.20 || die "Docker Compose $compose_version is too old (or missing). Version 2.20 or newer is required."
}

# env_get KEY -> value from .env (empty when unset)
env_get() { sed -n "s/^$1=//p" "$KIT_DIR/.env" | tail -n 1; }

# env_set KEY VALUE -> replaces the line in .env, or appends it. Rewrites through a temp
# file because BSD sed (macOS) and GNU sed disagree about sed -i.
env_set() {
  local tmp
  tmp=$(mktemp)
  awk -v k="$1" -v v="$2" 'BEGIN { FS = OFS = "=" }
    $1 == k { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }' "$KIT_DIR/.env" >"$tmp"
  cat "$tmp" >"$KIT_DIR/.env"
  rm -f "$tmp"
}

# random_hex BYTES -> 2*BYTES hex characters from the system random source
random_hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# The data volumes outlive the kit folder, and PostgreSQL keeps the password it was first
# started with, so a new .env must never be generated while the old volumes exist
POSTGRES_VOLUME="mairu_postgres-data"
volumes_exist() { docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1; }

require_env() {
  [ -f "$KIT_DIR/.env" ] && return 0
  die "No .env file in $KIT_DIR. If this is a new kit folder for an upgrade, copy .env and nginx/certs/ from the previous kit folder first. Do not run install.sh: it would generate new passwords that do not match the existing database."
}
