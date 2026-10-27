#!/usr/bin/env bash
# Runs ON the demo host. .github/workflows/deploy.yml copies it there over SSH and runs it:
#   remote-deploy.sh X.Y.Z
# Finds the running kit, downloads and verifies the kit of release vX.Y.Z when it is not
# unpacked yet, carries .env and the certificate over, runs the kit's scripts/upgrade.sh and
# the smoke test, and goes back to the previous kit when that fails.
#
# DEPLOY_ROOT         folder that holds the kit folders (default /shared)
# RELEASE_BASE_URL    where releases are downloaded from (default: the GitHub releases of
#                     dating-infra). Only changed by tests.
set -euo pipefail

root="${DEPLOY_ROOT:-/shared}"
base="${RELEASE_BASE_URL:-https://github.com/Mai-Ru-Software-House/dating-infra/releases/download}"
version="${1:-}"

info() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Usage: remote-deploy.sh X.Y.Z (got '$version')"
for tool in docker curl sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed on this host"
done

# The running stack knows which folder it was started from
nginx_id=$(docker ps -q --filter label=com.docker.compose.project=mairu --filter label=com.docker.compose.service=nginx | head -n 1)
[ -n "$nginx_id" ] || die "No running Mai Ru stack found. Install it first with scripts/install.sh."
active=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$nginx_id")
[ -f "$active/.env" ] || die "The running kit $active has no .env"
target="$root/mairu-server-$version"
info "Running kit: $active"
info "Target kit:  $target"

if [ "$target" != "$active" ]; then
  if [ ! -d "$target" ]; then
    info "Downloading the $version kit"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    archive="mairu-server-$version.tar.gz"
    curl -fsSL "$base/v$version/$archive" -o "$tmp/$archive" || die "Could not download $base/v$version/$archive"
    curl -fsSL "$base/v$version/SHA256SUMS" -o "$tmp/SHA256SUMS" || die "Could not download SHA256SUMS"
    expected=$(awk -v f="$archive" '$2 == f { print $1 }' "$tmp/SHA256SUMS")
    actual=$(sha256sum "$tmp/$archive" | cut -d ' ' -f 1)
    [ -n "$expected" ] && [ "$expected" = "$actual" ] || die "Checksum mismatch for $archive"
    tar -xzf "$tmp/$archive" -C "$root"
    [ -d "$target" ] || die "The archive did not contain mairu-server-$version/"
  fi
  info "Carrying .env and the certificate over"
  cp -p "$active/.env" "$target/.env"
  if [ -f "$active/nginx/certs/cert.crt" ] && [ -f "$active/nginx/certs/cert.key" ]; then
    # cert.key is usually owned by root (tailscale cert), so a container copies it with its
    # owner and mode kept
    docker run --rm --entrypoint sh -v "$active/nginx/certs:/from:ro" -v "$target/nginx/certs:/to" postgres:18 \
      -c 'cp -p /from/cert.crt /from/cert.key /to/' </dev/null
  fi
fi

rollback() {
  if [ "$target" = "$active" ]; then
    echo "The kit was upgraded in place, so there is no previous folder to go back to."
  else
    info "Rolling back to $active"
    (cd "$active" && docker compose -f docker-compose.prod.yaml up -d --wait --wait-timeout 240 --remove-orphans </dev/null) \
      || echo "ROLLBACK FAILED: check the stack by hand in $active" >&2
  fi
  echo "If the new version already applied a database migration, restore the backup in $target/backups (see the README, Upgrade and roll back)." >&2
}

cd "$target"
info "Upgrading to $version (backup first)"
if ! ./scripts/upgrade.sh "$version" </dev/null; then
  rollback
  die "Upgrade to $version failed"
fi

info "Smoke test on the host"
if ! ./scripts/smoke-test.sh localhost </dev/null; then
  rollback
  die "The smoke test failed after upgrading to $version"
fi
info "Deployed $version from $target"
