# KICS fix plan

Source: [kics_run1_output.txt](kics_run1_output.txt) (KICS v2.1.20, CI run 39400504465, before any fix).
Run 1 total: **47** findings (0 critical, 2 high, 41 medium, 0 low, 4 info). `file:line` below is the line in run 1.

## Owners (one batch and one commit per teammate, split by service)

| Owner | Services (dev + prod) | Findings | Extra work |
|---|---|---|---|
| Chuan | nginx | 10 | `depends_on` on healthy api / match-engine |
| Vic | api, match-engine | 14 | Fix the prod `depends_on` cycle (not reported by KICS) |
| Tae | postgres, rustfs | 18 | Bind dev ports to `127.0.0.1`, README port table |
| Tee | watchtower | 5 | CI job: `docker compose config` for both files + dev stack smoke test; `--fail-on high` after run 2 |

## Rules used for every fix

- `security_opt: ["no-new-privileges:true"]` on every service.
- `cap_drop` with the capabilities the service does not need. No `cap_add` (KICS reports any `cap_add`).
  - `ALL` for services that run as non-root (api as `bun`, rustfs as `rustfs`) and for match-engine (root, but only binds 8000 and reads root-owned files).
  - nginx keeps CHOWN, DAC_OVERRIDE, KILL, SETGID, SETUID: the root master chowns its temp dirs, reads the mounted certs, switches workers to the `nginx` user and signals them.
  - postgres keeps CHOWN, DAC_OVERRIDE, FOWNER, FSETID, SETGID, SETUID: the entrypoint fixes ownership/permissions of the data dir and switches to `postgres` with gosu.
  - watchtower keeps only DAC_OVERRIDE: it runs as root and must read the mounted `~/.docker/config.json`, which is usually mode 600 and owned by the host user.
- A healthcheck on every service, using a program that exists in the image (checked in the image build history / Dockerfile, no local Docker):
  nginx:alpine has busybox `wget`, the backend image has `bun`, match-engine (python:3.12-slim) has `python`, postgres has `pg_isready`, rustfs installs `curl`, watchtower is a scratch image with only `/watchtower --health-check`.
- `depends_on` with `condition: service_healthy` where a service needs another one at start: api needs postgres (migrations run at start) and rustfs; nginx needs api to resolve its upstream.
- Accepted findings are marked in the compose file with `# kics-scan ignore-line` and a comment with the reason. No file-wide disable.
- No `.env` or real secrets are committed.

## Bug not reported by KICS

`docker-compose.prod.yaml` has a `depends_on` cycle: `api -> match-engine -> api`, so `docker compose -f docker-compose.prod.yaml config` fails and prod cannot start.
Fix (Vic): remove `match-engine`'s `depends_on: api`. The two services only call each other at request time.

## Tests

- CI job `compose`: copies `.env.example` to `.env`, then `docker compose -f <file> config --quiet` for both compose files.
- CI job `smoke`: `docker compose -f docker-compose.dev.yaml up -d --wait` (every service must be running and healthy), then
  `http://localhost:3000/api/v1/health`, `http://localhost:8000/health` and `http://localhost/api/v1/health` (through nginx), then `down` (no `-v`).
  This replaces the local `up -d` test, since nobody running this has Docker locally. All images are public, so CI can pull them.

## Findings

| # | Severity | Query | file:line (run 1) | Service | Planned fix | Owner |
|---|---|---|---|---|---|---|
| 1 | HIGH | Docker Socket Mounted In Container | `docker-compose.dev.yaml:93` | watchtower | **Accepted**: watchtower needs the Docker socket to restart dev containers on new images; dev only, not in prod. `# kics-scan ignore-line` | Tee |
| 2 | HIGH | Volume Has Sensitive Host Directory | `docker-compose.dev.yaml:93` | watchtower | **Accepted**: same docker.sock line as above. `# kics-scan ignore-line` | Tee |
| 3 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:2` | nginx | Add `cap_drop`: AUDIT_WRITE, FOWNER, FSETID, MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP, SETPCAP, SYS_CHROOT | Chuan |
| 4 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:13` | api | Add `cap_drop: [ALL]` (runs as user `bun`) | Vic |
| 5 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:47` | match-engine | Add `cap_drop: [ALL]` | Vic |
| 6 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:61` | postgres | Add `cap_drop`: AUDIT_WRITE, KILL, MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP, SETPCAP, SYS_CHROOT | Tae |
| 7 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:74` | rustfs | Add `cap_drop: [ALL]` (runs as user `rustfs`) | Tae |
| 8 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.dev.yaml:89` | watchtower | Add `cap_drop`: every default capability except DAC_OVERRIDE | Tee |
| 9 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.prod.yaml:2` | nginx | Add `cap_drop`: AUDIT_WRITE, FOWNER, FSETID, MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP, SETPCAP, SYS_CHROOT | Chuan |
| 10 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.prod.yaml:17` | api | Add `cap_drop: [ALL]` (runs as user `bun`) | Vic |
| 11 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.prod.yaml:51` | match-engine | Add `cap_drop: [ALL]` | Vic |
| 12 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.prod.yaml:63` | postgres | Add `cap_drop`: AUDIT_WRITE, KILL, MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP, SETPCAP, SYS_CHROOT | Tae |
| 13 | MEDIUM | Container Capabilities Unrestricted | `docker-compose.prod.yaml:74` | rustfs | Add `cap_drop: [ALL]` (runs as user `rustfs`) | Tae |
| 14 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.dev.yaml:4` | nginx | **Accepted**: kept open so teammates can test from a phone on the same Wi-Fi. `# kics-scan ignore-line` | Chuan |
| 15 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.dev.yaml:15` | api | **Accepted**: kept open so teammates can test from a phone on the same Wi-Fi. `# kics-scan ignore-line` | Vic |
| 16 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.dev.yaml:49` | match-engine | **Accepted**: kept open so teammates can test from a phone on the same Wi-Fi. `# kics-scan ignore-line` | Vic |
| 17 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.dev.yaml:67` | postgres | Bind to `127.0.0.1` (all ports of the service) | Tae |
| 18 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.dev.yaml:81` | rustfs | Bind to `127.0.0.1` (all ports of the service) | Tae |
| 19 | MEDIUM | Container Traffic Not Bound To Host Interface | `docker-compose.prod.yaml:4` | nginx | **Accepted**: public gateway, 80/443 must be open to the internet. `# kics-scan ignore-line` | Chuan |
| 20 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:2` | nginx | Add healthcheck: busybox `wget` to `http://127.0.0.1/api/v1/health` (through the proxy) | Chuan |
| 21 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:13` | api | Add healthcheck: `bun -e fetch(...)` to `/api/v1/health` (image has no curl/wget) | Vic |
| 22 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:47` | match-engine | Add healthcheck: `python -c urllib.request...` to `/health` (image has no curl/wget) | Vic |
| 23 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:61` | postgres | Add healthcheck: `pg_isready -U app -d dating_app` | Tae |
| 24 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:74` | rustfs | Add healthcheck: `curl -fsS` to `:9000/health` and `:9001/rustfs/console/health` | Tae |
| 25 | MEDIUM | Healthcheck Not Set | `docker-compose.dev.yaml:89` | watchtower | Add healthcheck: `/watchtower --health-check` (scratch image, only the binary) | Tee |
| 26 | MEDIUM | Healthcheck Not Set | `docker-compose.prod.yaml:2` | nginx | Add healthcheck: busybox `wget` to `http://127.0.0.1/api/v1/health` (through the proxy) | Chuan |
| 27 | MEDIUM | Healthcheck Not Set | `docker-compose.prod.yaml:17` | api | Add healthcheck: `bun -e fetch(...)` to `/api/v1/health` (image has no curl/wget) | Vic |
| 28 | MEDIUM | Healthcheck Not Set | `docker-compose.prod.yaml:51` | match-engine | Add healthcheck: `python -c urllib.request...` to `/health` (image has no curl/wget) | Vic |
| 29 | MEDIUM | Healthcheck Not Set | `docker-compose.prod.yaml:63` | postgres | Add healthcheck: `pg_isready -U app -d dating_app` | Tae |
| 30 | MEDIUM | Healthcheck Not Set | `docker-compose.prod.yaml:74` | rustfs | Add healthcheck: `curl -fsS` to `:9000/health` and `:9001/rustfs/console/health` | Tae |
| 31 | MEDIUM | Privileged Ports Mapped In Container | `docker-compose.dev.yaml:4` | nginx | Fix via `cap_drop: NET_BIND_SERVICE` (the rule's own fix). Docker 20.10+ lets containers bind ports below 1024 without it, so 80/443 still work | Chuan |
| 32 | MEDIUM | Privileged Ports Mapped In Container | `docker-compose.prod.yaml:4` | nginx | Fix via `cap_drop: NET_BIND_SERVICE` (the rule's own fix). Docker 20.10+ lets containers bind ports below 1024 without it, so 80/443 still work | Chuan |
| 33 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:2` | nginx | Add `security_opt: ["no-new-privileges:true"]` | Chuan |
| 34 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:13` | api | Add `security_opt: ["no-new-privileges:true"]` | Vic |
| 35 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:47` | match-engine | Add `security_opt: ["no-new-privileges:true"]` | Vic |
| 36 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:61` | postgres | Add `security_opt: ["no-new-privileges:true"]` | Tae |
| 37 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:74` | rustfs | Add `security_opt: ["no-new-privileges:true"]` | Tae |
| 38 | MEDIUM | Security Opt Not Set | `docker-compose.dev.yaml:89` | watchtower | Add `security_opt: ["no-new-privileges:true"]` | Tee |
| 39 | MEDIUM | Security Opt Not Set | `docker-compose.prod.yaml:2` | nginx | Add `security_opt: ["no-new-privileges:true"]` | Chuan |
| 40 | MEDIUM | Security Opt Not Set | `docker-compose.prod.yaml:17` | api | Add `security_opt: ["no-new-privileges:true"]` | Vic |
| 41 | MEDIUM | Security Opt Not Set | `docker-compose.prod.yaml:51` | match-engine | Add `security_opt: ["no-new-privileges:true"]` | Vic |
| 42 | MEDIUM | Security Opt Not Set | `docker-compose.prod.yaml:63` | postgres | Add `security_opt: ["no-new-privileges:true"]` | Tae |
| 43 | MEDIUM | Security Opt Not Set | `docker-compose.prod.yaml:74` | rustfs | Add `security_opt: ["no-new-privileges:true"]` | Tae |
| 44 | INFO | Shared Volumes Between Containers | `docker-compose.dev.yaml:70` | postgres | **Accepted**: false positive, the rule flags every named volume; this volume is used by one service only. `# kics-scan ignore-line` | Tae |
| 45 | INFO | Shared Volumes Between Containers | `docker-compose.dev.yaml:85` | rustfs | **Accepted**: false positive, the rule flags every named volume; this volume is used by one service only. `# kics-scan ignore-line` | Tae |
| 46 | INFO | Shared Volumes Between Containers | `docker-compose.prod.yaml:70` | postgres | **Accepted**: false positive, the rule flags every named volume; this volume is used by one service only. `# kics-scan ignore-line` | Tae |
| 47 | INFO | Shared Volumes Between Containers | `docker-compose.prod.yaml:82` | rustfs | **Accepted**: false positive, the rule flags every named volume; this volume is used by one service only. `# kics-scan ignore-line` | Tae |
