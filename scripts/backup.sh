#!/usr/bin/env bash
# Backs up the database and the photo storage into backups/<timestamp>/ in the kit folder:
#   postgres.dump       pg_dump custom format (restore with pg_restore)
#   rustfs-data.tar.gz  the photo storage volume
#   images.txt          the image tags that were running, for a rollback
# The stack must be running. Usage: scripts/backup.sh
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_docker
require_env

for service in postgres rustfs; do
  [ -n "$(compose ps --status running -q "$service")" ] || die "The $service service is not running. Start the stack first (docker compose -f $COMPOSE_FILE up -d)."
done

dest="$KIT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dest"

info "Dumping the database"
# The dump is written inside the container and copied out, because a shell redirect
# would not be safe on every platform
compose exec -T postgres pg_dump -U app -d dating_app -Fc -f /tmp/dating_app.dump
compose cp postgres:/tmp/dating_app.dump "$dest/postgres.dump"
compose exec -T postgres rm -f /tmp/dating_app.dump

info "Archiving the photo storage"
# --volumes-from reuses whatever volume the rustfs service has mounted at /data
docker run --rm --entrypoint tar --volumes-from "$(compose ps -q rustfs)" \
  -v "$dest:/backup" "$TOOLBOX_IMAGE" czf /backup/rustfs-data.tar.gz -C /data .

{
  echo "BACKEND_IMAGE=$(env_get BACKEND_IMAGE)"
  echo "MATCH_ENGINE_IMAGE=$(env_get MATCH_ENGINE_IMAGE)"
} >"$dest/images.txt"

info "Backup written to $dest"
ls -l "$dest"
