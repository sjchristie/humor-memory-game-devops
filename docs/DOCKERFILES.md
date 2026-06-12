# Dockerfiles

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Dockerfiles  
**Previous:** [GIT_WORKFLOW.md](GIT_WORKFLOW.md)  
**Next:** [DOCKER_CONFIG.md](DOCKER_CONFIG.md)

---

## Table of Contents

1. [Understanding Dockerfiles](#1-understanding-dockerfiles)
2. [Why Read the Source Code First](#2-why-read-the-source-code-first)
3. [Analyse the Backend Source Code](#3-analyse-the-backend-source-code)
4. [Analyse the Frontend Source Code](#4-analyse-the-frontend-source-code)
5. [Analyse the Database Schema](#5-analyse-the-database-schema)
6. [Create the Backend Dockerfile](#6-create-the-backend-dockerfile)
7. [Create the Frontend Dockerfile](#7-create-the-frontend-dockerfile)
8. [Dockerfiles Checkpoint](#8-dockerfiles-checkpoint)

---

## 1. Understanding Dockerfiles

A Dockerfile is a plain text file containing a sequence of instructions that tells Docker how to build an image. Each instruction adds a new layer to the image. When a container is started, it runs from that image.

### Standard Structure

```dockerfile
# 1. Define the base image — the starting filesystem
FROM node:22-alpine

# 2. Set the working directory inside the container
WORKDIR /app

# 3. Copy dependency files before source code (layer cache optimisation)
COPY package*.json ./

# 4. Install dependencies
RUN npm ci --omit=dev

# 5. Copy the application source code
COPY . .

# 6. Document the port the application listens on
EXPOSE 3000

# 7. Define the command that starts the application
CMD ["node", "server.js"]
```

### Key Instructions

| Instruction | Purpose |
|-------------|---------|
| `FROM` | Sets the base image — the foundation every other instruction builds on |
| `WORKDIR` | Sets the working directory for all subsequent instructions |
| `COPY` | Copies files from the build context into the container filesystem |
| `RUN` | Executes a command during the build — installs packages, sets permissions |
| `ENV` | Sets environment variables available at runtime |
| `EXPOSE` | Documents which port the container listens on |
| `USER` | Switches to a non-root user — reduces the attack surface |
| `HEALTHCHECK` | Defines how Docker tests whether the container is working correctly |
| `CMD` | The default command run when the container starts |

### Base Images

The `FROM` instruction points to a pre-built image hosted on Docker Hub. The choice of base image affects the final image size and what tools are available inside the container.

| Base Image | Size | Used When |
|------------|------|-----------|
| `node:22-alpine` | ~45MB | Node.js applications — minimal Alpine Linux base |
| `nginx:1.25-alpine` | ~15MB | Serving static files — no Node.js required |
| `postgres:15.2-alpine` | ~85MB | PostgreSQL database |
| `redis:7.0-alpine` | ~30MB | Redis cache |

Alpine variants are chosen throughout this project — they are significantly smaller than their full Linux equivalents, faster to pull, and have a reduced attack surface.

### Layer Caching

Docker caches each layer. If a layer's inputs have not changed since the last build, Docker reuses the cached result and skips re-executing that instruction. This is why dependencies are copied and installed before application source code — dependencies rarely change, so that layer stays cached across most rebuilds. Copying source code last means a code change only rebuilds the final layer, not the dependency installation.

---

## 2. Why Read the Source Code First

Before writing a Dockerfile, the source code must be read to extract what the application actually needs. Docker cannot infer requirements — the code must be read to determine:

- Which Node.js version is required
- What the startup command is
- Which port the application listens on
- Which external services it connects to (database, cache)
- What environment variables it expects
- What files need to be present at runtime

All this information lives in the developer repository.

---

## 3. Analyse the Backend Source Code

### Read package.json

```bash
grep -E '"(node|npm|start|main|pg|redis|dotenv|uuid)"' \
  ~/workspace/humor-memory-game/backend/package.json
```

**What to look for:**

| Field | Value | Docker Implication |
|-------|-------|--------------------|
| `engines.node` | `>=18.0.0` | Sets the minimum Node.js version for the base image |
| `scripts.start` | `node server.js` | Becomes the final `CMD` instruction |
| `main` | `server.js` | Confirms the container entry point filename |
| `dependencies: pg` | `^8.11.x` | App connects to PostgreSQL — database env vars required |
| `dependencies: redis` | `^4.6.x` | App connects to Redis — cache env vars required |
| `dependencies: dotenv` | `^16.3.x` | Reads variables from environment at runtime |
| `dependencies: uuid` | `^9.0.x` | Requires Node.js 22 — see Issue 1 below |

**Key findings from this application:**

```json
{
  "engines": { "node": ">=18.0.0" },
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0",
    "redis": "^4.6.0",
    "uuid": "^9.0.1",
    "dotenv": "^16.3.1"
  }
}
```

### Read server.js — Port and Connections

```bash
grep -n "PORT\|listen\|postgres\|redis\|DB_HOST\|REDIS" \
  ~/workspace/humor-memory-game/backend/server.js | head -30
```

**Key findings:**

| Finding | Value | Docker Implication |
|---------|-------|--------------------|
| Port | `process.env.PORT \|\| 3001` | Backend listens on port 3001 — `EXPOSE 3001` in Dockerfile |
| Bind address | `0.0.0.0` | Binds to all interfaces — required for Docker port mapping |
| Database host env var | `DB_HOST` | Must be injected via Docker Compose environment |
| Redis host env var | `REDIS_HOST` | Must be injected via Docker Compose environment |

---

## 4. Analyse the Frontend Source Code

### Read package.json

```bash
cat ~/workspace/humor-memory-game/frontend/package.json
```

**Key findings from this application:**

```json
{
  "scripts": {
    "start": "python3 -m http.server 3000 --directory src",
    "build": "npm run copy-assets",
    "copy-assets": "mkdir -p dist && cp -r public/* dist/ && cp -r src/* dist/"
  }
}
```

**What this tells us:**

| Script | Command | Docker Implication |
|--------|---------|-------------------|
| `start` | `python3 -m http.server` | Development only — not suitable for production |
| `build` | `npm run copy-assets` | Produces a `dist/` directory containing static files |
| `copy-assets` | `cp -r public/* dist/ && cp -r src/* dist/` | All static assets land in `dist/` |

The `build` command produces a `dist/` directory containing static HTML, CSS, and JS files. No Node.js runtime is needed to serve these files — Nginx serves the `dist/` directory directly.

**Docker conclusion — two-stage build:**

- Stage 1: Node.js image — runs `npm run build`, produces `dist/`
- Stage 2: Nginx image — copies `dist/` from Stage 1, serves it
- Final image contains no Node.js (82% smaller than a single-stage build)

### Confirm the Build Output Path

```bash
grep -A2 "copy-assets" ~/workspace/humor-memory-game/frontend/package.json
```

Expected:

```json
"copy-assets": "mkdir -p dist && cp -r public/* dist/ && cp -r src/* dist/"
```

The `dist/` directory will contain all files Nginx needs to serve.

---

## 5. Analyse the Database Schema

```bash
grep -E -i '^(CREATE EXTENSION|CREATE TABLE|CREATE OR REPLACE VIEW|CREATE INDEX|CREATE TRIGGER|GRANT)' \
  ~/workspace/humor-memory-game/database/combined-init.sql
```

**Key findings:**

| Object Type | Name | Purpose |
|-------------|------|---------|
| Extension | `uuid-ossp` | Enables native UUID generation for primary keys |
| Table | `users` | Player accounts and cumulative game statistics |
| Table | `games` | Game sessions, scores, and match metrics |
| Table | `game_matches` | Individual card pairings per game session |
| Table | `daily_challenges` | Date-based challenge tracking |
| View | `leaderboard` | Aggregated score rankings across all players |
| Function | `update_user_stats()` | Automated score accumulation on game completion |
| Trigger | `trigger_update_user_stats` | Fires on game completion to update user stats |
| Grants | `gameuser` permissions | Least-privilege application database user |

**Docker implication:**

The `combined-init.sql` file is mounted into the PostgreSQL container at `/docker-entrypoint-initdb.d/`. PostgreSQL's official image automatically executes any SQL files found there on first startup — this creates the complete schema without any manual steps.

```bash
# Confirm the SQL file exists and is not empty
wc -l ~/workspace/humor-memory-game/database/combined-init.sql
# Expected: several hundred lines
```

---

## 6. Create the Backend Dockerfile

All Dockerfiles are created inside the DevOps repository `docker/` directory. The build context (where Docker looks for source files) is the developer repository — configured in `docker-compose.yml` in a later phase.

```bash
cd ~/workspace/humor-memory-game-devops
```

### Annotated Version — Read First

The annotated version explains the purpose of every instruction. Read this before creating the file.

```dockerfile
# Backend Dockerfile
# Node.js Express REST API
# Layer-based build optimised for Docker cache reuse

FROM node:22-alpine

# alpine: minimal base image (~45MB vs 300MB+ for full Linux)
# Security: minimal attack surface
# Speed: faster to pull and build

WORKDIR /app

# Install curl for health checks
RUN apk add --no-cache curl

# ============================================================
# LAYER 1: Dependencies
# Cached unless package.json or package-lock.json changes
# ============================================================

COPY package*.json ./

# package*.json matches both package.json and package-lock.json
# Copying these BEFORE source code means:
# - Code changes do not invalidate this layer
# - npm ci is skipped on rebuild if dependencies are unchanged
# - Saves several minutes per rebuild

RUN npm ci --omit=dev

# npm ci: uses exact versions from package-lock.json (deterministic)
# --omit=dev: production packages only — no eslint, jest, nodemon etc.

# ============================================================
# LAYER 2: Application Code
# Rebuilt on code changes only
# ============================================================

# Switch to non-root user before copying application files
USER node

COPY --chown=node:node . .

# --chown=node:node: sets file ownership in one step
# Placed AFTER npm ci so code changes do not bust the dependency cache

# ============================================================
# LAYER 3: Runtime Configuration
# ============================================================

EXPOSE 3001

# Documents the port the application listens on
# Actual port binding is configured in docker-compose.yml

# ============================================================
# LAYER 4: Health Check
# ============================================================

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
  CMD curl -f http://localhost:3001/api/health || exit 1

# interval=30s:      check every 30 seconds
# timeout=10s:       fail if no response within 10 seconds
# retries=3:         mark unhealthy after 3 consecutive failures
# start-period=40s:  grace period on startup before checks begin

# ============================================================
# STARTUP COMMAND
# ============================================================

CMD ["npm", "start"]

# npm start runs: node server.js (from package.json scripts.start)
# Express server starts and listens on port 3001
```

### Production Copy — Run This Command

```bash
cat > docker/backend/Dockerfile << 'EOF'
# Backend Dockerfile
# Node.js Express REST API

FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache curl

# ============================================================
# LAYER 1: Dependencies
# ============================================================

COPY package*.json ./
RUN npm ci --omit=dev

# ============================================================
# LAYER 2: Application Code
# ============================================================

USER node
COPY --chown=node:node . .

# ============================================================
# LAYER 3: Runtime Configuration
# ============================================================

EXPOSE 3001

# ============================================================
# LAYER 4: Health Check
# ============================================================

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
  CMD curl -f http://localhost:3001/api/health || exit 1

# ============================================================
# STARTUP COMMAND
# ============================================================

CMD ["npm", "start"]
EOF
```

Verify the file was created:

```bash
cat docker/backend/Dockerfile
```

---

### 🔴 ISSUE 1 — Node.js Version Mismatch (`ERR_REQUIRE_ESM`)

**Where it occurred:** Backend container failed to start after first build

**Symptom:**

```
Error [ERR_REQUIRE_ESM]: require() of ES Module not supported
    at Object.<anonymous> (/app/node_modules/uuid/dist/cjs/index.js)
```

**Root Cause:**
The original Dockerfile used `FROM node:18-alpine`. The developer was running Node.js 22 locally. When `npm ci` ran inside the container, it pulled the latest version of the `uuid` package. This newer version dropped CommonJS `require()` support and moved to ES Modules only — which Node.js 18 cannot load. The developer's local environment worked because it had an older cached version of `uuid` in `node_modules`.

**How the mismatch was identified:**

```bash
# Check what Node.js version the developer is using
# Run this on the developer VM, not the DevOps VM
node --version
# Output: v22.x.x

# Check what version is in the Dockerfile
grep "FROM node" ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
# Output: FROM node:18-alpine  ← mismatch
```

**Fix:**

```bash
sed -i 's/FROM node:18-alpine/FROM node:22-alpine/' \
  ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile

grep "FROM" ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
# Expected: FROM node:22-alpine
```

**Prevention:**
Always confirm the Node.js version in use on the developer machine before writing the Dockerfile. The base image version must match the developer's environment:

```bash
# On the developer VM
node --version
# Use the matching major version in the Dockerfile
# FROM node:22-alpine
```

---

### 🔴 ISSUE 2 — Docker Build Context Misconfiguration (`COPY failed: no source files`)

**Where it occurred:** Both backend and frontend initial builds

**Symptom:**

```
ERROR [backend 2/4] COPY package.json package-lock.json ./
------
COPY failed: no source files were specified
```

**Root Cause:**
Docker's build process operates within a **build context** — the directory passed to `docker build`. Docker cannot access files outside this boundary. The Dockerfiles live in the DevOps repository but the source code lives in the developer repository. When the build context was set to the DevOps repository, the `COPY` instructions could not find the source files.

**How the issue was identified:**

```bash
# Wrong — build context is the DevOps repo, no source code visible
docker build -f docker/Dockerfile.backend .

# List what Docker can see with the wrong context
ls .
# Output: docker/  docker-compose.yml  .env  — no backend source code
```

**Fix:**
Specify the build context explicitly as the source code directory:

```bash
docker build \
  -f ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile \
  ~/workspace/humor-memory-game/backend/
```

In practice, build context is handled automatically by `docker-compose.yml` using the `context` and `dockerfile` keys — configured in the Docker Compose phase.

**Prevention:**
Always configure build context in `docker-compose.yml`:

```yaml
backend:
  build:
    context: ../humor-memory-game/backend
    dockerfile: ../humor-memory-game-devops/docker/backend/Dockerfile
```

---

### 🔴 ISSUE 3 — Missing `package-lock.json` (`npm ci` Failed)

**Where it occurred:** Backend Docker build — `RUN npm ci` step

**Symptom:**

```
npm error The `npm ci` command can only install with an existing package-lock.json
```

**Root Cause:**
`npm ci` requires a `package-lock.json` to be present. This file was not committed to the developer repository — it existed on the developer's local machine but was absent from the cloned repository on the DevOps VM.

**How the issue was identified:**

```bash
ls ~/workspace/humor-memory-game/backend/package-lock.json
# Output: No such file or directory
```

**Fix:**
The `package-lock.json` must be committed to the developer repository. On the developer VM:

```bash
cd ~/workspace/humor-memory-game/backend
npm install
git add package-lock.json
git commit -m "Add package-lock.json for reproducible builds"
git push origin main
```

Then on the DevOps VM, pull the updated repository:

```bash
cd ~/workspace/humor-memory-game
git pull origin main

ls backend/package-lock.json
# Expected: file found
```

**Prevention:**
`package-lock.json` must always be committed to the repository. It is what makes Docker builds deterministic — `npm ci` will always fail without it.

---

## 7. Create the Frontend Dockerfile

The frontend uses a **two-stage build**. Stage 1 compiles the application using Node.js. Stage 2 serves the compiled output using Nginx. The final image contains only Nginx and the compiled static files — Node.js is discarded entirely after the build stage.

```bash
cd ~/workspace/humor-memory-game-devops
```

### Annotated Version — Read First

```dockerfile
# Frontend Dockerfile
# Two-stage build: compile with Node.js, serve with Nginx
# Final image size: ~90MB (vs ~500MB single-stage)

# ============================================================
# STAGE 1: BUILD
# Compile frontend assets using Node.js
# ============================================================

FROM node:22-alpine AS builder

# AS builder: names this stage so Stage 2 can reference it

WORKDIR /app

# Copy package files first for layer cache optimisation
COPY package*.json ./

# Install all dependencies including dev tools needed for the build
# This stage is discarded after build — size does not matter here
RUN npm ci

# Copy source code and run the build
COPY . .
RUN npm run build

# Result: dist/ directory created containing all static files
# Stage 1 at this point: ~500MB (Node.js + node_modules + dist/)
# Everything except dist/ is discarded when Stage 2 begins

# ============================================================
# STAGE 2: SERVE
# Minimal Nginx runtime — no Node.js
# ============================================================

FROM nginx:1.25-alpine

# Fresh base image — ~15MB
# Does NOT inherit Node.js, node_modules, or source code from Stage 1

# Copy Nginx configuration (static serve + API reverse proxy)
# nginx.conf is created in DOCKER_CONFIG.md and copied to the build context
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy startup script (environment variable injection before Nginx starts)
# start.sh is created in DOCKER_CONFIG.md and copied to the build context
COPY start.sh /start.sh

# Copy compiled static files from Stage 1 BEFORE setting permissions
# --from=builder references the named stage above
# Files must exist before chown — chown on an empty directory has no effect
# on files copied in later steps (see Issue 6 in DOCKER_CONFIG.md)
COPY --from=builder /app/dist /usr/share/nginx/html

# Set all permissions while still running as root
# chmod and chown MUST run before USER switches to non-root
# COPY --from=builder MUST run before chown so files are owned correctly
RUN chmod +x /start.sh && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Switch to non-root user for security
USER nginx

EXPOSE 80

# Nginx serves on port 80 (internal)
# docker-compose.yml maps host port 3000 to container port 80

CMD ["/start.sh"]

# start.sh injects environment variables then starts Nginx in foreground
```

### Production Copy — Run This Command

```bash
cat > docker/frontend/Dockerfile << 'EOF'
# Frontend Dockerfile
# Two-stage build: compile with Node.js, serve with Nginx

# ============================================================
# STAGE 1: BUILD
# ============================================================

FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ============================================================
# STAGE 2: SERVE
# ============================================================

FROM nginx:1.25-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY start.sh /start.sh

COPY --from=builder /app/dist /usr/share/nginx/html

RUN chmod +x /start.sh && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 80

CMD ["/start.sh"]
EOF
```

Verify the file was created:

```bash
cat docker/frontend/Dockerfile
```

---

## 8. Dockerfiles Checkpoint

> **Important:** Do not attempt to build these images yet. The frontend Dockerfile references `nginx.conf` and `start.sh` which are created in the next phase. Building before those files exist will fail. Proceed to `DOCKER_CONFIG.md` first.

```bash
# Both Dockerfiles exist
ls ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
ls ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile

# Backend Dockerfile uses correct Node.js version
grep "FROM" ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
# Expected: FROM node:22-alpine

# Frontend Dockerfile uses two-stage build
grep "FROM" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected:
# FROM node:22-alpine AS builder
# FROM nginx:1.25-alpine

# Frontend Dockerfile COPY --from=builder appears before chown
grep -n "COPY --from\|chown" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected: COPY --from=builder line number is LOWER than chown line numbers

# package-lock.json is present in the developer repository
ls ~/workspace/humor-memory-game/backend/package-lock.json
# Expected: file found
```

All checks passing? Proceed to Docker Config to create the supporting configuration files.

---

**Next → [DOCKER_CONFIG.md](DOCKER_CONFIG.md)**
