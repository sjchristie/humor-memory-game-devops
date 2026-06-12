# Build and Start

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Build and Start  
**Previous:** [DOCKER_COMPOSE.md](DOCKER_COMPOSE.md)  
**Next:** [VERIFICATION.md](VERIFICATION.md)

---

## Table of Contents

1. [Pre-Build Checklist](#1-pre-build-checklist)
2. [Build All Images](#2-build-all-images)
3. [Reading Build Output](#3-reading-build-output)
4. [Start the Stack](#4-start-the-stack)
5. [Monitor Service Startup](#5-monitor-service-startup)
6. [Check Service Health](#6-check-service-health)
7. [Common Service Management Commands](#7-common-service-management-commands)
8. [Build and Start Checkpoint](#8-build-and-start-checkpoint)

---

## 1. Pre-Build Checklist

Run through this before building to avoid common failures:

```bash
cd ~/workspace/humor-memory-game-devops

# .env is present and has real values
cat .env
# DB_PASSWORD must not be empty or a placeholder

# docker-compose.yml syntax is valid
docker compose config
# Must output resolved configuration without errors

# nginx.conf and start.sh are in the frontend source directory
ls ~/workspace/humor-memory-game/frontend/ | grep -E "nginx|start"
# Expected: nginx.conf  start.sh
# If missing — return to DOCKER_CONFIG.md Step 5

# package-lock.json exists in backend source
ls ~/workspace/humor-memory-game/backend/package-lock.json
# Expected: file found
# If missing — return to DOCKERFILES.md Issue 3

# Docker daemon is running
docker ps
# Must return without error
```

---

## 2. Build All Images

The `--no-cache` flag forces Docker to rebuild every layer from scratch, pulling the latest dependencies and avoiding any cached state from previous builds. Always use `--no-cache` for an initial build or when troubleshooting.

```bash
cd ~/workspace/humor-memory-game-devops

docker compose build --no-cache
```

This command:

1. Reads `docker-compose.yml` to find the two services with `build:` sections — `frontend` and `backend`
2. Sends the build context for each to the Docker daemon
3. Executes each Dockerfile instruction in sequence
4. Tags the resulting images with the names defined in `docker-compose.yml`

`postgres` and `redis` have no `build:` section — they use pre-built images pulled directly from Docker Hub when the stack starts.

> **Deprecation warning:** On Arch Linux the legacy Docker builder may display the following at the start of the build — this is expected and does not affect the build:
> ```
> DEPRECATED: The legacy builder is deprecated and will be removed in a future release.
>             Install the buildx component to build images with BuildKit:
>             https://docs.docker.com/go/buildx/
> ```

---

## 3. Reading Build Output

Build output is verbose. Here is what to look for.

### Successful Backend Build — Expected Output

```
Sending build context to Docker daemon  404.6kB
Step 1/10 : FROM node:22-alpine
Step 2/10 : WORKDIR /app
Step 3/10 : RUN apk add --no-cache curl
Step 4/10 : COPY package*.json ./
Step 5/10 : RUN npm ci --omit=dev
Step 6/10 : USER node
Step 7/10 : COPY --chown=node:node . .
Step 8/10 : EXPOSE 3001
Step 9/10 : HEALTHCHECK ...
Step 10/10 : CMD ["npm", "start"]
Successfully built xxxxxxxxx
Successfully tagged humor-memory-game-backend:latest
```

### Successful Frontend Build — Expected Output

```
Sending build context to Docker daemon  137.6kB
Step 1/14 : FROM node:22-alpine AS builder
Step 2/14 : WORKDIR /app
Step 3/14 : COPY package*.json ./
Step 4/14 : RUN npm ci
Step 5/14 : COPY . .
Step 6/14 : RUN npm run build
Step 7/14 : FROM nginx:1.25-alpine
Step 8/14 : COPY nginx.conf /etc/nginx/conf.d/default.conf
Step 9/14 : COPY start.sh /start.sh
Step 10/14 : COPY --from=builder /app/dist /usr/share/nginx/html
Step 11/14 : RUN chmod +x /start.sh && chown -R nginx:nginx ...
Step 12/14 : USER nginx
Step 13/14 : EXPOSE 80
Step 14/14 : CMD ["/start.sh"]
Successfully built xxxxxxxxx
Successfully tagged humor-memory-game-frontend:latest
```

### Warning Signs in Build Output

| Output | What It Means |
|--------|---------------|
| `Using cache` on a step | Docker used a cached layer — fine on subsequent builds, use `--no-cache` if suspecting stale cache |
| `npm warn deprecated` | Non-fatal — a package dependency is outdated, not an error |
| `ERROR` | Fatal — build failed, read the line immediately after for the specific error |
| `exit code: 1` | A command inside the Dockerfile returned a failure exit code |
| `permission denied` | Likely a `chown` ordering issue — see DOCKER_CONFIG.md Issue 6 |

### If the Build Fails

Docker always identifies which step failed. Read the error message at that step carefully:

```bash
# Rebuild a single service to see errors more clearly
docker compose build --no-cache backend 2>&1 | tail -30
docker compose build --no-cache frontend 2>&1 | tail -30
```

---

## 4. Start the Stack

Once both images are built successfully, start all four services:

```bash
cd ~/workspace/humor-memory-game-devops

docker compose up -d
```

The `-d` flag runs containers in **detached mode** (background). Without it, all container logs stream to the terminal and `Ctrl+C` stops the containers.

**What happens when this command runs:**

1. Docker Compose reads `docker-compose.yml`
2. Creates the two Docker networks (`frontend-network`, `backend-network`)
3. Creates the two named volumes (`postgres_data`, `redis_data`) if they do not exist
4. Pulls `postgres:15.2-alpine` and `redis:7.0-alpine` from Docker Hub (first time only)
5. Starts containers in dependency order:
   - PostgreSQL and Redis start first
   - Backend waits until PostgreSQL and Redis pass their health checks
   - Frontend waits until backend passes its health check

**Expected output:**

```
[+] Running 8/8
 ✔ Network humor-memory-game-devops_frontend-network  Created
 ✔ Network humor-memory-game-devops_backend-network   Created
 ✔ Volume "humor-memory-game-devops_postgres_data"    Created
 ✔ Volume "humor-memory-game-devops_redis_data"       Created
 ✔ Container humor-game-postgres                      Started
 ✔ Container humor-game-redis                         Started
 ✔ Container humor-game-backend                       Started
 ✔ Container humor-game-frontend                      Started
```

---

### 🔴 ISSUE 7 — Docker Compose Working Directory Error

**Where it occurred:** Running `docker compose` commands from the wrong directory

**Symptom:**

```
no configuration file provided: not found
```

Or:

```
open /home/devops/workspace/humor-memory-game/backend/docker-compose.yml: no such file or directory
```

**Root Cause:**
`docker compose` looks for a `docker-compose.yml` file in the **current working directory**. Running `docker compose` from any other directory — a subdirectory, home directory, or the developer repository — causes this error because no `docker-compose.yml` exists there.

**How the issue was identified:**

```bash
pwd
# Output: /home/devops/workspace/humor-memory-game/backend
# Wrong — this is the developer repo, not the DevOps repo

cd ~/workspace/humor-memory-game-devops
pwd
# Output: /home/devops/workspace/humor-memory-game-devops  ← correct
```

**Fix:**
Always `cd` to the DevOps repository before running any `docker compose` command:

```bash
cd ~/workspace/humor-memory-game-devops
docker compose up -d
docker compose ps
docker compose logs -f
```

**Additional fix — `docker compose exec` intercepted by entrypoint:**

In some cases `docker compose exec` is intercepted by the container's `start.sh` entrypoint and fails unexpectedly. Use `docker exec` directly with the container name instead:

```bash
# If this fails:
docker compose exec backend sh

# Use this instead:
docker exec -i humor-game-backend sh
```

**Prevention:**
Add a shell alias to always navigate to the correct directory:

```bash
# Add to ~/.bashrc
alias dcgame='cd ~/workspace/humor-memory-game-devops && docker compose'

# Then use:
dcgame ps
dcgame logs -f backend
dcgame down
```

---

## 5. Monitor Service Startup

After starting, services take time to become healthy. Monitor logs while they initialise:

```bash
# Watch all service logs in real time
# Ctrl+C stops watching — does NOT stop containers
docker compose logs -f

# Watch a single service
docker compose logs -f backend
docker compose logs -f postgres
```

### What Healthy Startup Looks Like

**PostgreSQL:**

```
humor-game-postgres  | PostgreSQL init process complete; ready for start up.
humor-game-postgres  | database system is ready to accept connections
```

**Redis:**

```
humor-game-redis  | Ready to accept connections
```

**Backend:**

```
humor-game-backend  | Server running on port 3001
humor-game-backend  | Database connected successfully
humor-game-backend  | Redis connected successfully
```

**Frontend (Nginx):**

Nginx starts cleanly with no errors when the full Compose network is running and `backend` resolves via Docker DNS:

```
humor-game-frontend  | /docker-entrypoint.sh: Configuration complete; ready for start up
```

> The exact Nginx startup message may vary by version. The key confirmation is the absence of `[emerg]` errors — particularly the `host not found in upstream "backend"` error that appears in standalone mode. In Compose mode, `backend` resolves correctly and Nginx starts successfully.

---

## 6. Check Service Health

After a minute or two, check that all services are healthy:

```bash
docker compose ps
```

**Expected output — all services healthy:**

```
NAME                   IMAGE                              STATUS          PORTS
humor-game-backend     humor-memory-game-backend:latest   Up (healthy)    0.0.0.0:3001->3001/tcp
humor-game-frontend    humor-memory-game-frontend:latest  Up (healthy)    0.0.0.0:3000->3000/tcp
humor-game-postgres    postgres:15.2-alpine               Up (healthy)    5432/tcp
humor-game-redis       redis:7.0-alpine                   Up (healthy)    6379/tcp
```

### Understanding Status Values

| Status | Meaning |
|--------|---------|
| `Up (healthy)` | Container is running and passing its health check |
| `Up` | Container is running but health check has not yet completed |
| `Up (unhealthy)` | Container is running but failing its health check — check logs |
| `Restarting` | Container is crash-looping — check logs immediately |
| `Exited` | Container has stopped — check logs for the exit reason |

### If a Service is Restarting or Unhealthy

```bash
# View logs for the failing service
docker compose logs backend

# View only the last 50 lines
docker compose logs --tail=50 backend

# View logs with timestamps
docker compose logs -t backend
```

The error is almost always in the last few lines of the log output.

---

## 7. Common Service Management Commands

```bash
# View current status of all services
docker compose ps

# Restart a single service without rebuilding
docker compose restart backend

# Stop all services (containers stopped, volumes preserved)
docker compose stop

# Stop and remove containers and networks (volumes preserved)
docker compose down

# Stop and remove containers, networks, AND volumes (wipes database)
docker compose down -v

# Rebuild and restart a single service
docker compose build --no-cache backend && docker compose up -d backend

# Execute a shell inside a running container
docker exec -i humor-game-backend sh
docker exec -i humor-game-postgres sh

# Connect to PostgreSQL inside its container
docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game

# Connect to Redis CLI inside its container
docker exec -i humor-game-redis redis-cli -a gamepass123

# View resource usage for all containers
docker stats
```

---

## 8. Build and Start Checkpoint

```bash
cd ~/workspace/humor-memory-game-devops

# All four services running
docker compose ps
# Expected: all four containers present
# humor-game-backend   — Up (healthy)
# humor-game-frontend  — Up (healthy)
# humor-game-postgres  — Up (healthy)
# humor-game-redis     — Up (healthy)

# Backend logs show successful connections
docker compose logs backend | grep -E "running|connected|error|Error"
# Expected: "running on port 3001", "Database connected", "Redis connected"
# No error lines

# PostgreSQL ready
docker compose logs postgres | grep "ready to accept"
# Expected: "database system is ready to accept connections"

# Redis ready
docker compose logs redis | grep "Ready"
# Expected: "Ready to accept connections"

# Frontend reachable
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Expected: 200

# Backend API reachable
curl -s http://localhost:3001/api/health
# Expected: JSON response — {"status":"ok"} or similar
```

All checks passing? Proceed to full end-to-end verification.

---

**Next → [VERIFICATION.md](VERIFICATION.md)**
