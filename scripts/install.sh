#!/usr/bin/env bash
# Installs the Mai Ru server stack: checks the host, creates .env with generated secrets
# (only when it does not exist yet), pulls the images and starts everything. Safe to run
# again: an existing .env and certificate are never replaced.
#
# HTTPS is enabled when nginx/certs/ holds cert.crt and cert.key: port 80 then redirects to
# HTTPS. Without them the server answers on plain HTTP only. Add the certificate and run
# this script again to switch.
#
# Usage: scripts/install.sh [--host <name-or-ip>] [--self-signed]
#   --host         address the phones will use; goes into the printed URLs and the
#                  self-signed certificate (default: localhost)
#   --self-signed  create a self-signed certificate when there is none, which enables HTTPS.
#                  Phones do not trust it, so the Android app will not connect
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

host=localhost
self_signed=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) [ $# -ge 2 ] || die "--host needs a value"; host="$2"; shift 2 ;;
    --self-signed) self_signed=1; shift ;;
    -h | --help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
case "$host" in *[!A-Za-z0-9.:-]* | "") die "--host may only contain letters, digits, dots, colons and dashes" ;; esac

info "Checking the host"
check_arch
check_docker
if ! systemctl is-enabled docker >/dev/null 2>&1 && [ "$(uname -s)" = "Linux" ]; then
  warn "The Docker service is not enabled at boot, so the stack will not come back after a reboot. Run: sudo systemctl enable docker"
fi

info "Preparing .env"
if [ ! -f .env ] && volumes_exist; then
  die "Found data from an earlier install (Docker volume $POSTGRES_VOLUME) but this folder has no .env. New secrets would not match that database. Copy .env and nginx/certs/ from the previous kit folder, or remove the old data first with its scripts/uninstall.sh --delete-volumes."
fi
if [ -f .env ]; then
  echo ".env already exists, keeping it."
else
  [ -f .env.example ] || die ".env.example is missing from $KIT_DIR"
  cp .env.example .env
  chmod 600 .env
fi
# Fills only values that still hold the template placeholder, so a re-run never changes a
# password that PostgreSQL has already been initialised with
fill_secret() { # KEY BYTES
  case "$(env_get "$1")" in
    "" | your_*) env_set "$1" "$(random_hex "$2")"; echo "Generated $1" ;;
  esac
}
fill_secret POSTGRES_PASSWORD 32
fill_secret RUSTFS_ACCESS_KEY 16
fill_secret RUSTFS_SECRET_KEY 32
fill_secret JWT_SECRET 32

info "Preparing HTTPS"
mkdir -p nginx/certs
if [ -f nginx/certs/cert.crt ] && [ -f nginx/certs/cert.key ]; then
  echo "Found nginx/certs/cert.crt and cert.key."
  https=1
elif [ -f nginx/certs/cert.crt ] || [ -f nginx/certs/cert.key ]; then
  die "nginx/certs/ has only one of cert.crt and cert.key. HTTPS needs both."
elif [ "$self_signed" = 1 ]; then
  san="DNS:localhost,IP:127.0.0.1"
  if [[ "$host" =~ ^[0-9.]+$ ]]; then san="$san,IP:$host"; elif [ "$host" != "localhost" ]; then san="$san,DNS:$host"; fi
  # openssl runs in a container so the host does not need it
  docker run --rm --entrypoint sh -v "$KIT_DIR/nginx/certs:/certs" "$TOOLBOX_IMAGE" -c \
    "openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj '/CN=$host' -addext 'subjectAltName=$san' -keyout /certs/cert.key -out /certs/cert.crt 2>/dev/null && chmod 644 /certs/cert.crt /certs/cert.key" \
    || die "Could not create the self-signed certificate"
  echo "Created a self-signed certificate for $host (valid 825 days). Browsers and phones will not trust it."
  https=1
else
  echo "No certificate in nginx/certs/, so HTTPS is off and the server answers on plain HTTP."
  https=0
fi
# NGINX_CONF follows the certificate on every run, so adding or removing it and running
# this script again is all it takes to switch
if [ "$https" = 1 ]; then
  env_set NGINX_CONF ./nginx/nginx.prod.conf
else
  env_set NGINX_CONF ./nginx/nginx.prod.http.conf
fi

info "Checking the compose file"
compose config --quiet || die "docker compose rejected the configuration (see above)"

info "Pulling images"
if ! compose pull; then
  die "Image pull failed. If the packages are private, sign in first: echo \$GHCR_TOKEN | docker login ghcr.io -u <github-user> --password-stdin"
fi

info "Starting the stack (waiting up to 4 minutes for every service to be healthy)"
if ! compose up -d --wait --wait-timeout 240; then
  compose ps -a || true
  compose logs --no-color --tail 30 || true
  die "The stack did not become healthy. See the logs above."
fi
compose ps

if [ "$https" = 1 ]; then expect=--expect-https; else expect=--expect-http; fi
info "Running the smoke test"
if ! "$KIT_DIR/scripts/smoke-test.sh" "$host" "$expect"; then
  warn "The smoke test failed, see above."
fi

echo
echo "Mai Ru server is running."
if [ "$https" = 1 ]; then
  echo "  API: https://$host/api/v1 (port 80 redirects to it)"
  echo "Build the phone app with EXPO_PUBLIC_API_BASE_URL=https://$host/api/v1"
  echo "A certificate the phones do not trust (such as a self-signed one) will make the app fail."
else
  echo "  API: http://$host/api/v1"
  echo "Build the phone app with EXPO_PUBLIC_API_BASE_URL=http://$host/api/v1"
  echo "To enable HTTPS, put cert.crt and cert.key in nginx/certs/ and run scripts/install.sh again."
fi
