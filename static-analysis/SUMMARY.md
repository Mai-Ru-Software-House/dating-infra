# KICS static analysis: summary

Tool: [KICS](https://kics.io) `checkmarx/kics:v2.1.20` (pinned by digest), run in GitHub Actions ([kics.yml](../.github/workflows/kics.yml)).
KICS scans the two compose files and the workflow (5 files in total). It has no rules for `nginx/*.conf`.

| | Run 1 (before fixes) | Run 2 (after fixes) |
|---|---|---|
| Output | [kics_run1_output.txt](kics_run1_output.txt) | [kics_run2_output.txt](kics_run2_output.txt) |
| CI run | 39400504465 | 39402237671 |
| Commit | `69312bc` (workflow only, compose files unchanged) | `0fa4f5d` (last fix commit) |

Both runs are the first scan of the PR and the scan of the last fix commit. Pull request runs use the run name `ci`, so the artifact is `kics-ci`. Its `kics_ci_output.txt` was committed byte for byte under the run 1 / run 2 name; only the file name changed.

## Results by severity

| Severity | Run 1 | Run 2 |
|---|---|---|
| CRITICAL | 0 | 0 |
| HIGH | 2 | 0 |
| MEDIUM | 41 | 0 |
| LOW | 0 | 0 |
| INFO | 4 | 0 |
| **Total** | **47** | **0** |

The 47 run 1 findings break down as **37 fixed** and **10 accepted**. Accepted findings are marked `# kics-scan ignore-line` with the reason next to them, so they no longer count in run 2. Nothing uses a file-wide disable.

## Results by query

| Severity | Query | Run 1 | Fixed | Accepted | Run 2 |
|---|---|---|---|---|---|
| HIGH | Docker Socket Mounted In Container | 1 | 0 | 1 | 0 |
| HIGH | Volume Has Sensitive Host Directory | 1 | 0 | 1 | 0 |
| MEDIUM | Security Opt Not Set | 11 | 11 | 0 | 0 |
| MEDIUM | Healthcheck Not Set | 11 | 11 | 0 | 0 |
| MEDIUM | Container Capabilities Unrestricted | 11 | 11 | 0 | 0 |
| MEDIUM | Container Traffic Not Bound To Host Interface | 6 | 2 | 4 | 0 |
| MEDIUM | Privileged Ports Mapped In Container | 2 | 2 | 0 | 0 |
| INFO | Shared Volumes Between Containers | 4 | 0 | 4 | 0 |
| | **Total** | **47** | **37** | **10** | **0** |

Every finding, with its owner, is listed in [FIX_PLAN.md](FIX_PLAN.md).

## What we fixed

One commit per teammate, split by service:

- **Tee (watchtower, CI):** `no-new-privileges`, `cap_drop` of every default capability except DAC_OVERRIDE (needed to read the mounted `~/.docker/config.json`), and a healthcheck (`/watchtower --health-check`). Added the CI `compose` and `smoke` jobs.
- **Tae (postgres, rustfs):** `no-new-privileges`, `cap_drop`, and healthchecks (`pg_isready -U app -d dating_app`; `curl` to rustfs `/health`). Dev ports 5432, 9000 and 9001 are now bound to `127.0.0.1`.
- **Vic (api, match-engine):** `no-new-privileges`, `cap_drop: [ALL]`, and healthchecks through `bun` and `python`, because these images have no curl or wget. api waits for healthy postgres and rustfs, since migrations run at start.
- **Chuan (nginx):** `no-new-privileges`, `cap_drop` including NET_BIND_SERVICE (Docker 20.10+ lets containers bind ports below 1024 without it), and a healthcheck with busybox `wget` through the proxy. Uses `depends_on: api` with `service_healthy`.

No service uses `cap_add`. Each image's healthcheck program was confirmed from its Dockerfile or image build history.

### Bugs found that KICS does not report

- **Prod could not start.** `docker-compose.prod.yaml` had a `depends_on` cycle (`api -> match-engine -> api`). The new CI job showed `dependency cycle detected: api -> match-engine -> api`. Fixed by removing match-engine's `depends_on: api`; the two services only call each other at request time.
- **Dev nginx start-order race.** After api started waiting for postgres, nginx sometimes started first and exited with `host not found in upstream "api"` (the CI smoke test caught this on `a936d1f`). Fixed by nginx's `depends_on: api` with `condition: service_healthy`.

## What we accepted and why

| Findings | Where | Why |
|---|---|---|
| 2 HIGH: Docker Socket Mounted, Sensitive Host Directory | dev `watchtower` | watchtower needs the Docker socket to restart dev containers when new images are pushed. Dev only; prod has no watchtower. |
| 1 MEDIUM: Traffic Not Bound To Host Interface | prod `nginx` | Public gateway: 80 and 443 must be open to the internet. |
| 3 MEDIUM: Traffic Not Bound To Host Interface | dev `nginx`, `api`, `match-engine` | Left open on all interfaces so a teammate can test from a phone on the same Wi-Fi. postgres and rustfs were bound to 127.0.0.1. |
| 4 INFO: Shared Volumes Between Containers | `postgres-data`, `rustfs-data` (dev + prod) | False positive. The rule flags every named volume a service mounts, but each volume is used by one service only. |

### KICS 2.1.20 ignore-comment quirks

The first try left the 2 HIGH and 4 INFO accepted findings in the report. This is how KICS 2.1.20 reads YAML comments (`pkg/model/comment_yaml.go`, `model_yaml.go`):

- A comment above the **first item of a list** belongs to the list node, and KICS never reads it. A comment above a **mapping key** works.
- In a multi-line comment, the `kics-scan` regex removes the newline before `kics-scan`, so `ignore-line` gets glued to the previous word. A fallback still honors it above a mapping key, but not above a list item.

So the one-item volume lists are written on one line (`volumes: ["postgres-data:/var/lib/postgresql"]`) under the comment. The docker.sock mount is the second item and has a one-line `# kics-scan ignore-line`, with the reason above the `volumes:` key.

Note on Privileged Ports Mapped: both nginx findings are fixed by `cap_drop: NET_BIND_SERVICE`, which is exactly what the rule checks. They are reported on the same `ports:` line that carries the accepted "not bound to host interface" ignore, so run 2 alone doesn't show which one cleared them. The cap_drop makes the rule pass either way.

## Tests

- **CI `compose` job:** copies `.env.example` to `.env`, then runs `docker compose -f <file> config --quiet` for both compose files. It failed on the prod cycle until Vic's commit and passes from `a936d1f` on.
- **CI `smoke` job:** `docker compose -f docker-compose.dev.yaml up -d --wait`. On `0fa4f5d` all 6 services reached `running (healthy)`, and `http://localhost:3000/api/v1/health`, `http://localhost:8000/health` and `http://localhost/api/v1/health` (through nginx) returned `{"status":"ok"}`. Then `down`, without `-v`.
- **Not done:** the local `docker compose -f docker-compose.dev.yaml up -d` test. Nobody running this had Docker locally, so the CI smoke test replaces it (all images are public, so CI can pull them). The prod stack was only checked with `docker compose config`, not started.

## CI gate from now on

The KICS step now uses `--fail-on critical,high` instead of `--ignore-on-exit results`, so a new CRITICAL or HIGH finding fails CI. `--fail-on` is an exact list of severities, so `high` alone would let a CRITICAL finding pass. MEDIUM and lower are still reported in the artifact but don't fail the job.

## Left for later

- **KICS v2.2.0** is released on GitHub but not yet on Docker Hub (newest there is v2.1.20). Bump the pinned tag and digest when it's published.
- **Image tags:** `nginx:alpine`, `rustfs/rustfs:latest` and `containrrr/watchtower` (implicit `latest`) aren't pinned to a version. KICS has no compose rule for this, but pinning would make builds reproducible.
