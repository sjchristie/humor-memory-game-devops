# Humor Memory Game — Docker Deployment Overview

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Environment:** Arch Linux VM (`ops-box-01`) · SSH access  
**Stack:** Node.js · Express · PostgreSQL · Redis · Nginx · Docker  
**Date:** May 2026

---

## Table of Contents

1. [What This Document Set Covers](#1-what-this-document-set-covers)
2. [The Two-Repository Pattern](#2-the-two-repository-pattern)
3. [Application Architecture](#3-application-architecture)
4. [Services Summary](#4-services-summary)
5. [Document Structure](#5-document-structure)
6. [Issues Encountered](#6-issues-encountered)
7. [Quick Reference — Key Commands](#7-quick-reference--key-commands)
8. [Prerequisites Checklist](#8-prerequisites-checklist)

---

## 1. What This Document Set Covers

This guide documents the complete end-to-end process of taking a full-stack web application that runs in a developer environment (`npm start`) and deploying it using Docker and Docker Compose on a separate DevOps VM.

It covers:

- Every command run, in chronological order
- Every issue encountered, where it occurred, why it happened, and exactly how it was fixed
- Architecture decisions and why each technology was chosen
- Verification steps to confirm everything is working

---

## 2. The Two-Repository Pattern

This deployment uses two separate repositories — an enterprise best practice that keeps application source code and infrastructure concerns cleanly separated:

```
Developer Repository (humor-memory-game)
├─ backend/              ← Node.js / Express API source code
├─ frontend/             ← Static HTML / CSS / JS source code
├─ database/             ← PostgreSQL schema SQL
└─ package.json files

DevOps Repository (humor-memory-game-devops)
├─ docker/
│  ├─ backend/
│  │  └─ Dockerfile
│  └─ frontend/
│     ├─ Dockerfile
│     ├─ nginx.conf
│     └─ start.sh
├─ docker-compose.yml
├─ .env                  ← git-ignored, secrets only
├─ .env.example          ← safe template, committed
├─ game_check.sh         ← automated 25-test suite
└─ .gitignore
```

The developer repository is **cloned and never modified**. All Docker infrastructure lives in the DevOps repository.

---

## 3. Application Architecture

```
User's Browser (http://ops-box-01:3000)
        │
        ▼
  ┌─────────────┐
  │    Nginx    │  ← Serves static frontend files
  │  (Frontend) │  ← Proxies /api/* requests to backend
  └──────┬──────┘
         │ frontend-network
         ▼
  ┌─────────────┐
  │  Express.js │  ← REST API, business logic
  │  (Backend)  │  ← Queries PostgreSQL, caches with Redis
  └──────┬──────┘
         │ backend-network
    ┌────┴────┐
    ▼         ▼
┌───────┐  ┌───────┐
│Postgres│  │ Redis │  Internal only — not exposed to host
│  :5432 │  │ :6379 │  Frontend has NO route to these services
└───────┘  └───────┘
```

**Network isolation:** The frontend container has no DNS entry for `postgres` or `redis`. It cannot reach them regardless of application behaviour — isolation is enforced at the Docker network layer, not by policy or configuration.

The backend container sits on **both** networks. This is intentional — it bridges the frontend-facing network and the database network. All data access is forced through the backend API.

---

## 4. Services Summary

| Service | Base Image | Port (External) | Purpose |
|---------|-----------|-----------------|---------|
| frontend | `nginx:1.25.0-alpine` | 3000 | Serves static files, proxies `/api/*` |
| backend | `node:22-alpine` | 3001 | REST API |
| postgres | `postgres:15.2-alpine` | internal only | Primary database |
| redis | `redis:7.0-alpine` | internal only | Session cache, leaderboard |

---

## 5. Document Structure

| Document | What It Covers |
|----------|----------------|
| `DOCKER_OVERVIEW.md` | Architecture, issue index, quick reference — start here |
| `ENVIRONMENT_SETUP.md` | SSH into VM, install Docker, configure Docker without sudo, workspace and directory structure |
| `GIT_WORKFLOW.md` | Section 1 — Git and GitHub setup, clone developer repo, create DevOps repo. Section 2 — Stage, commit, push, verify on GitHub |
| `DOCKERFILES.md` | Analyse source code, write backend and frontend Dockerfiles, Issues 1–3 |
| `DOCKER_CONFIG.md` | Write `nginx.conf`, `start.sh`, `.dockerignore` files, Issues 4–6 |
| `DOCKER_IMAGE_TESTS.md` | Build and test images individually before Compose |
| `DOCKER_COMPOSE.md` | Write `docker-compose.yml`, configure `.env`, network and volume setup |
| `BUILD_AND_START.md` | Build all images, start the stack, monitor services, Issue 7 |
| `VERIFICATION.md` | 25-test automated suite, full end-to-end verification, Issues 8–9 |

---

## 6. Issues Encountered

Nine issues were encountered across build, startup, and runtime during the real deployment. All are documented inline at the exact step where they occurred.

| #   | Issue                                                   | Document             | Root Cause Summary                                                                                                    |
| --- | ------------------------------------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| 1   | `ERR_REQUIRE_ESM` — server would not start              | `DOCKERFILES.md`     | Node.js version mismatch — `node:18` in Dockerfile vs `node:22` in dev environment                                    |
| 2   | `COPY failed: no source files`                          | `DOCKERFILES.md`     | Build context pointed to the DevOps repo — source code in the developer repo was invisible                            |
| 3   | `npm ci` failed — lockfile not found                    | `DOCKERFILES.md`     | `package-lock.json` not committed to the developer repository                                                         |
| 4   | `COPY nginx.conf: file does not exist`                  | `DOCKER_CONFIG.md`   | Config files in the DevOps repo unreachable from the frontend build context — symlinks don't cross context boundaries |
| 5   | `sed: no previous regexp`                               | `DOCKER_CONFIG.md`   | Empty pattern in `sed` substitution — shell expanded unset variable to empty string before `sed` saw it               |
| 6   | `Permission denied` on static files                     | `DOCKER_CONFIG.md`   | `chown` ran before `COPY --from=builder` — files copied after `chown` were owned by root                              |
| 7   | `no configuration file provided: not found`             | `BUILD_AND_START.md` | `docker compose` commands run from the wrong directory                                                                |
| 8   | `invalid input syntax for type uuid: "daily-challenge"` | `VERIFICATION.md`    | Express route ordering — dynamic `/:gameId` matched before the specific `/daily-challenge` route                      |

> **Note:** Issues related to the `daily_challenges` database schema are tracked in the developer repository documentation, as they are application-level concerns rather than Docker infrastructure issues.

**Root cause pattern:** All issues trace back to environment drift — the gap between a developer's accumulated local setup and a clean container environment.

Full details for each issue — symptom, root cause, exact fix, and prevention — are documented inline in the relevant document.

---

## 7. Quick Reference — Key Commands

All `docker compose` commands must be run from the DevOps repository root:

```bash
cd ~/workspace/humor-memory-game-devops
```

```bash
# Build all images from scratch
docker compose build --no-cache

# Start the full stack (detached)
docker compose up -d

# Check all service status
docker compose ps

# View logs for a specific service
docker compose logs -f backend

# Stop everything (containers stopped, volumes preserved)
docker compose down

# Stop and remove volumes (wipes database — use with caution)
docker compose down -v

# Restart a single service
docker compose restart backend

# Rebuild and restart a single service
docker compose build --no-cache backend && docker compose up -d backend

# Execute a shell inside a running container
docker exec -i humor-game-backend sh

# Connect to PostgreSQL inside its container
docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game

# Connect to Redis CLI inside its container
docker exec -i humor-game-redis redis-cli

# View resource usage for all containers
docker stats

# Run the full automated test suite
sh game_check.sh
```

---

## 8. Prerequisites Checklist

Before starting the environment setup, confirm:

- [ ] Arch Linux VM (`ops-box-01`) is running and accessible via SSH
- [ ] You have `sudo` access on the VM
- [ ] GitHub account exists
- [ ] Developer repository URL is known (`<github-username>/humor-memory-game`)
- [ ] DevOps repository URL is known (`<github-username>/humor-memory-game-devops`)

---

**Start here → [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md)**
