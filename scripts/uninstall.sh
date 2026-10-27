#!/usr/bin/env bash
# Stops and removes the Mai Ru containers. The data volumes (database and photos) are
# deleted only after you confirm. .env, the certificate and backups/ are never touched.
#
# Usage: scripts/uninstall.sh [--delete-volumes | --keep-volumes]
#   no option         asks whether to delete the data volumes
#   --delete-volumes  deletes them without asking
#   --keep-volumes    keeps them without asking
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

choice=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --delete-volumes) choice=delete; shift ;;
    --keep-volumes) choice=keep; shift ;;
    -h | --help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

check_docker
require_env

if [ "$choice" = ask ]; then
  echo "This removes the Mai Ru containers."
  printf 'Also DELETE the data volumes postgres-data and rustfs-data (all users, messages and photos)? Type "yes" to delete, anything else keeps them: '
  read -r answer || answer=""
  if [ "$answer" = "yes" ]; then choice=delete; else choice=keep; fi
fi

if [ "$choice" = delete ]; then
  info "Removing containers, networks and data volumes"
  compose down --remove-orphans --volumes
else
  info "Removing containers and networks, keeping the data volumes"
  compose down --remove-orphans
fi
info "Done"
