#!/usr/bin/env bash
# Upgrades a running installation to a new release: backs up, sets the image tags in .env,
# pulls the images and restarts. The api container applies pending database migrations
# when it starts.
#
# Usage: scripts/upgrade.sh [version] [--skip-backup]
#   version   release to install, such as 1.0.1 (default: the version in this kit's
#             .env.example)
# To upgrade: unzip the new kit, copy .env and nginx/certs/ (and backups/ if you like) from
# the old kit folder into the new one, cd into the new folder and run this script.
#
# Rollback: put the tags from backups/<timestamp>/images.txt back into .env, run
# docker compose -f docker-compose.prod.yaml up -d, and restore the backup if the
# new version changed the database (see the README).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version=""
skip_backup=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-backup) skip_backup=1; shift ;;
    -h | --help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

check_docker
require_env

if [ -z "$version" ]; then
  version=$(sed -n 's/^BACKEND_IMAGE=.*://p' "$KIT_DIR/.env.example" | tail -n 1)
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must look like 1.0.1, got '$version'"

# Image name without the tag: the tag is whatever follows the last colon
retag() { printf '%s:%s' "${1%:*}" "$version"; }
old_backend=$(env_get BACKEND_IMAGE)
old_engine=$(env_get MATCH_ENGINE_IMAGE)
new_backend=$(retag "$old_backend")
new_engine=$(retag "$old_engine")
echo "BACKEND_IMAGE:      $old_backend -> $new_backend"
echo "MATCH_ENGINE_IMAGE: $old_engine -> $new_engine"

if [ "$skip_backup" = 1 ]; then
  warn "Skipping the backup"
else
  info "Backing up first"
  "$KIT_DIR/scripts/backup.sh"
fi

env_set BACKEND_IMAGE "$new_backend"
env_set MATCH_ENGINE_IMAGE "$new_engine"

info "Pulling images"
if ! compose pull; then
  env_set BACKEND_IMAGE "$old_backend"
  env_set MATCH_ENGINE_IMAGE "$old_engine"
  die "Pull failed. .env still points at the previous images and nothing was restarted."
fi

info "Restarting"
if ! compose up -d --wait --wait-timeout 240 --remove-orphans; then
  compose ps -a || true
  compose logs --no-color --tail 30 api || true
  die "The new version did not become healthy. Previous images: $old_backend and $old_engine. Roll back as described at the top of scripts/upgrade.sh."
fi
compose ps

info "Running the smoke test"
"$KIT_DIR/scripts/smoke-test.sh" localhost || warn "The smoke test failed, see above."
info "Upgraded to $version"
