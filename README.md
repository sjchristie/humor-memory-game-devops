# 🎮 Humor Memory Game — Docker Infrastructure

> A complete Docker containerisation of a full-stack web application, demonstrating production-grade DevOps practices across networking, security, persistence, and multi-service orchestration.

**Environment:** Arch Linux VM (`ops-box-01`) · SSH access  
**Deployment:** Docker · Docker Compose v2  
**Stack:** Node.js 22 · Express · PostgreSQL 15.2 · Redis 7.0 · Nginx 1.25  
**Status:** Fully deployed and verified — 25/25 automated tests passing

---

## Table of Contents

- [What This Project Is](#what-this-project-is)
- [Skills Demonstrated](#skills-demonstrated)
- [Application Architecture](#application-architecture)
- [Tech Stack](#tech-stack)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Issues Encountered and Resolved](#issues-encountered-and-resolved)
- [Documentation](#documentation)
- [Technical Detail](#technical-detail)
- [Key Decisions](#key-decisions)
- [Quick Reference](#quick-reference)

---

## What This Project Is

This repository contains the complete Docker infrastructure for the **Humor Memory Game** — a full-stack web application built with Node.js, PostgreSQL, and Redis.

The application was developed by a previous developer and ran successfully in a local development environment using `npm start`. This repository represents the **DevOps Phase** of the project — taking that source code and containerising it into a production-ready, orchestrated multi-service deployment using Docker and Docker Compose.

### The Real-World Scenario

This project mirrors a common and critical DevOps responsibility:

> *"Here is an application a developer built. Your job is to containerise it, make it production-ready, and deploy it reliably — without breaking the source code or modifying the developer's repository."*

This is not a tutorial follow-along. Every decision, configuration file, and fix documented here was worked through from first principles against a real application that had real errors.

---

## Skills Demonstrated

### Docker and Containerisation

| Skill | Implementation |
|-------|---------------|
| Multi-stage Dockerfile builds | Frontend image reduced from ~500MB to ~90MB (82% reduction) |
| Docker layer caching optimisation | Dependencies copied before source code — rebuilds in seconds not minutes |
| Build context management | Two-repository pattern with explicit context and Dockerfile paths |
| Non-root container security | Applications run as unprivileged users inside containers |

### Container Orchestration

| Skill | Implementation |
|-------|---------------|
| Multi-service Docker Compose | 4 services orchestrated with dependency ordering and health checks |
| Service discovery | Docker internal DNS — services communicate by name, not IP |
| Health checks | Automatic failure detection with configurable retry and grace periods |
| Restart policies | Self-healing containers with `unless-stopped` policy |
| Named volumes | Data persistence across container restarts for PostgreSQL and Redis |

### Networking and Security

| Skill | Implementation |
|-------|---------------|
| Network isolation | Two isolated bridge networks — frontend cannot access database |
| Reverse proxy configuration | Nginx proxies `/api/*` requests to backend service |
| Secrets management | Environment variables via `.env` file, excluded from git |
| `.env.example` pattern | Safe template committed to repository, secrets never exposed |

### Linux and System Administration

| Skill | Implementation |
|-------|---------------|
| Arch Linux package management | `pacman` for Docker and tooling installation |
| Kernel parameter tuning | `vm.overcommit_memory` for Redis stability |
| Shell scripting | POSIX-compliant `sh` startup scripts with environment injection |
| File permissions | `chmod`/`chown` ordering in Dockerfiles for non-root users |

### Debugging and Troubleshooting

| Skill | Implementation |
|-------|---------------|
| Container log analysis | Diagnosing failures from `docker compose logs` output |
| Runtime inspection | `docker exec` for live container debugging |
| Environment drift diagnosis | Identifying differences between developer and container environments |
| Systematic issue resolution | 9 distinct issues identified, root-caused, and permanently fixed |

---

## Application Architecture

```
User Browser (http://ops-box-01:3000)
        │
        ▼
┌───────────────────┐
│      Nginx        │  Port 80 (internal) / 3000 (host)
│   (Frontend)      │  ├─ Serves static HTML/CSS/JS
│                   │  └─ Proxies /api/* → Backend
└────────┬──────────┘
         │ frontend-network
         ▼
┌───────────────────┐
│   Express.js      │  Port 3001
│   (Backend API)   │  ├─ REST API and business logic
│                   │  ├─ Reads/writes PostgreSQL
└────────┬──────────┘  └─ Caches with Redis
         │ backend-network
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌────────┐
│Postgres│ │ Redis  │  Internal only — not exposed to host
│ :5432  │ │ :6379  │  Frontend has NO route to these services
└────────┘ └────────┘
```

**Security by architecture:** The frontend network isolation is enforced at the Docker network layer — not by policy or configuration. The frontend container has no DNS entry for `postgres` or `redis` and cannot reach them regardless of application-level behaviour.

---

## Tech Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Frontend Server | Nginx | 1.25-alpine | Static file serving, API reverse proxy |
| Backend Runtime | Node.js | 22-alpine | Express.js REST API |
| Primary Database | PostgreSQL | 15.2-alpine | Persistent data storage |
| Cache Layer | Redis | 7.0-alpine | Session cache, leaderboard cache |
| Orchestration | Docker Compose | v2 | Multi-service management |
| OS | Arch Linux | Latest | DevOps VM host |

---

## Quick Start

### Prerequisites

- Arch Linux VM (`ops-box-01`) with SSH access
- Docker and Docker Compose installed
- GitHub SSH access configured
- Developer repository cloned at `~/workspace/humor-memory-game`

### Clone and Deploy

```bash
# Clone this DevOps repository
cd ~/workspace
git clone git@github.com:<github-username>/humor-memory-game-devops.git
cd humor-memory-game-devops

# Configure environment
cp .env.example .env
nano .env

# Copy supporting files to frontend source directory
cp docker/frontend/nginx.conf ../humor-memory-game/frontend/nginx.conf
cp docker/frontend/start.sh ../humor-memory-game/frontend/start.sh

# Build and start all services
docker compose build --no-cache
docker compose up -d

# Verify deployment
docker compose ps
curl http://localhost:3001/api/health
```

### Verify Everything is Working

```bash
sh game_check.sh
```

Expected output:

```
Total tests: 25
Passed:      25
Failed:      0
✅ ALL TESTS PASSED — application fully verified
```

---

## Repository Structure

```
humor-memory-game-devops/
├─ docker-compose.yml           ← Service orchestration
├─ .env.example                 ← Environment variable template
├─ .gitignore                   ← Excludes .env and secrets
├─ game_check.sh                ← Automated 25-test suite
├─ docker/
│  ├─ backend/
│  │  └─ Dockerfile             ← Node.js multi-layer build
│  └─ frontend/
│     ├─ Dockerfile             ← Two-stage build (Node → Nginx)
│     ├─ nginx.conf             ← Reverse proxy configuration
│     └─ start.sh               ← Environment injection startup script
└─ docs/
   ├─ DOCKER_OVERVIEW.md
   ├─ ENVIRONMENT_SETUP.md
   ├─ GIT_WORKFLOW.md
   ├─ DOCKERFILES.md
   ├─ DOCKER_CONFIG.md
   ├─ DOCKER_IMAGE_TESTS.md
   ├─ DOCKER_COMPOSE.md
   ├─ BUILD_AND_START.md
   └─ VERIFICATION.md
```

---

## Issues Encountered and Resolved

Nine issues were encountered across build, startup, and runtime. All resolved and documented inline in the relevant phase document.

| # | Issue | Document | Root Cause |
|---|-------|----------|-----------|
| 1 | `ERR_REQUIRE_ESM` — server would not start | `DOCKERFILES.md` | Node.js version mismatch — `node:18` in Dockerfile vs `node:22` in dev environment |
| 2 | `COPY failed: no source files` | `DOCKERFILES.md` | Build context pointed to DevOps repo — source code in developer repo was invisible |
| 3 | `npm ci` failed — lockfile not found | `DOCKERFILES.md` | `package-lock.json` not committed to developer repository |
| 4 | `COPY nginx.conf: file does not exist` | `DOCKER_CONFIG.md` | Config files in DevOps repo unreachable from frontend build context — symlinks don't cross context boundaries |
| 5 | `sed: no previous regexp` | `DOCKER_CONFIG.md` | Empty pattern in `sed` substitution — shell expanded unset variable to empty string |
| 6 | `Permission denied` on static files | `DOCKER_CONFIG.md` | `chown` ran before `COPY --from=builder` — files copied after `chown` were owned by root |
| 7 | `no configuration file provided: not found` | `BUILD_AND_START.md` | `docker compose` commands run from the wrong directory |
| 8 | `invalid input syntax for type uuid: "daily-challenge"` | `VERIFICATION.md` | Express route ordering — dynamic `/:gameId` matched before specific `/daily-challenge` route |

> Full root cause analysis, exact error messages, fixes, and prevention strategies are documented inline in each phase document.

---

## Documentation

| Document | Contents |
|----------|---------|
| [DOCKER_OVERVIEW.md](./docs/DOCKER_OVERVIEW.md) | Architecture, issue index, quick reference — start here |
| [ENVIRONMENT_SETUP.md](./docs/ENVIRONMENT_SETUP.md) | VM prep, Docker install, workspace setup |
| [GIT_WORKFLOW.md](./docs/GIT_WORKFLOW.md) | Git and GitHub setup, commit and push workflow |
| [DOCKERFILES.md](./docs/DOCKERFILES.md) | Source code analysis, Dockerfile creation, Issues 1–3 |
| [DOCKER_CONFIG.md](./docs/DOCKER_CONFIG.md) | nginx.conf, start.sh, .dockerignore, Issues 4–6 |
| [DOCKER_IMAGE_TESTS.md](./docs/DOCKER_IMAGE_TESTS.md) | Standalone image build and test |
| [DOCKER_COMPOSE.md](./docs/DOCKER_COMPOSE.md) | Orchestration, environment config, networks and volumes |
| [BUILD_AND_START.md](./docs/BUILD_AND_START.md) | Build all images, start stack, service management, Issue 7 |
| [VERIFICATION.md](./docs/VERIFICATION.md) | 25-test automated suite, full end-to-end verification, Issue 8 |

---

## Technical Detail

### Dockerfiles

**Backend — `node:22-alpine`**

- Dependencies copied before source code — layer cache preserved on code-only changes
- `npm ci --omit=dev` — reproducible, production-only install
- Runs as non-root `node` user
- Built-in health check via `curl /api/health`

**Frontend — Two-Stage Build**

| Stage | Base Image | Purpose | Size |
|-------|-----------|---------|------|
| builder | `node:22-alpine` | `npm ci` + `npm run build` → `dist/` | ~500MB (discarded) |
| serve | `nginx:1.25-alpine` | Copies `dist/`, runs `start.sh` | ~90MB (final) |

82% image size reduction versus a single-stage build.

**start.sh — Environment Injection**

Runs before Nginx starts. Uses `sed` to substitute `${API_BASE_URL}`, `${NODE_ENV}`, and `${BUILD_TIMESTAMP}` into HTML and JS files at container startup — the same image runs in development and production without rebuilding. Uses `find` for JS file traversal — `**` glob is bash-only and Alpine uses `sh`.

### Services

| Service | Image | Port | Health Check |
|---------|-------|------|-------------|
| postgres | `postgres:15.2-alpine` | 5432 (internal) | `pg_isready` |
| redis | `redis:7.0-alpine` | 6379 (internal) | `redis-cli ping` |
| backend | `humor-memory-game-backend:latest` | 3001 (host) | `curl /api/health` |
| frontend | `humor-memory-game-frontend:latest` | 3000 (host) → 80 (container) | `curl localhost:80` |

Startup ordering: postgres and redis must be healthy before backend starts. Backend must be started before frontend starts.

Restart policy: `unless-stopped` on all services — self-healing without manual intervention.

Data persistence: named volumes `postgres_data` and `redis_data` survive `docker compose down`. Only `docker compose down -v` destroys data.

### Networks

| Network | Members | Isolation |
|---------|---------|-----------|
| `frontend-network` | frontend, backend | Frontend reaches backend only |
| `backend-network` | backend, postgres, redis | Hidden from frontend entirely |

Frontend DNS has no record for `postgres` or `redis` — network isolation is architectural, not policy-based.

### Environment Configuration

All secrets in `.env` (git-ignored). Defaults set in `docker-compose.yml` via `${VAR:-default}` pattern for safe fallback:

```bash
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=<secret>
REDIS_PASSWORD=<secret>
NODE_ENV=development
JWT_SECRET=<secret>
API_BASE_URL=/api
```

`.env.example` committed — shows all required variables without exposing values.

### System Notes

**Redis memory overcommit warning** — apply once on the Arch Linux VM:

```bash
sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

**Config files must be copied** to the frontend source directory before each build:

```bash
cp docker/frontend/nginx.conf ../humor-memory-game/frontend/nginx.conf
cp docker/frontend/start.sh ../humor-memory-game/frontend/start.sh
```

---

## Key Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Node.js version | 22 (matched developer) | `uuid` package ESM compatibility |
| Frontend server | Nginx not Node.js | 20x smaller image, purpose-built for static files |
| Build strategy | Two-stage | 82% image size reduction — no dev tools in production |
| Networks | Two isolated | Frontend cannot access database — architectural enforcement |
| Shell in containers | `sh` not `bash` | Alpine Linux default — `**` glob and other bash extensions unavailable |
| `npm ci` not `npm install` | `npm ci` | Reproducible builds — exact lockfile versions every time |

---

## Quick Reference

```bash
# Start the stack
docker compose up -d

# Check service status
docker compose ps

# View logs
docker compose logs -f backend

# Rebuild a single service
docker compose build --no-cache frontend && docker compose up -d frontend

# Shell into a container
docker exec -i humor-game-backend sh

# Connect to PostgreSQL
docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game

# Connect to Redis CLI
docker exec -i humor-game-redis redis-cli -a gamepass123

# Full reset (destroys data)
docker compose down -v && docker compose build --no-cache && docker compose up -d

# Run the automated test suite
sh game_check.sh
```

---

## Project Context

This repository is Phase 2 of a structured DevOps learning path:

- **Phase 1:** Application development — [`humor-memory-game`](https://github.com/<github-username>/humor-memory-game)
- **Phase 2:** Containerisation — Docker and Docker Compose ← *this repository*
- **Phase 3:** Orchestration — Kubernetes
- **Phase 4:** Automation — CI/CD with GitHub Actions

---

*Built with persistence through 9 real issues — because real DevOps is never just `docker compose up`.*
