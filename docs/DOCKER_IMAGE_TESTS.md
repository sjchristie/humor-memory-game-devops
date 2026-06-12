# Docker Image Tests

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Docker Image Tests  
**Previous:** [DOCKER_CONFIG.md](DOCKER_CONFIG.md)  
**Next:** [DOCKER_COMPOSE.md](DOCKER_COMPOSE.md)

---

## Table of Contents

1. [Why Test Images Individually](#1-why-test-images-individually)
2. [Pre-Build Checklist](#2-pre-build-checklist)
3. [Test the Backend Image](#3-test-the-backend-image)
4. [Test the Frontend Image](#4-test-the-frontend-image)
5. [Clean Up Test Containers](#5-clean-up-test-containers)
6. [Image Tests Checkpoint](#6-image-tests-checkpoint)

---

## 1. Why Test Images Individually

Before moving to Docker Compose, each image is built and run in isolation. This confirms that:

- The Dockerfile instructions are syntactically correct
- The build context is correctly configured
- All `COPY` instructions can find their source files
- Dependencies install without errors
- The container starts without crashing

Running these tests now isolates Dockerfile problems from Docker Compose configuration problems. A failing `docker compose up` can have many causes — a failing standalone build has only one: the Dockerfile itself.

> **What standalone tests cannot confirm:** Full connectivity between services. The backend will log connection errors without PostgreSQL and Redis. The frontend Nginx will fail to start its proxy without the backend DNS entry. Both of these are expected in standalone mode — full connectivity is verified in the Compose phase.

---

## 2. Pre-Build Checklist

Confirm all files are in place before building:

```bash
# nginx.conf and start.sh copied to frontend source directory
ls ~/workspace/humor-memory-game/frontend/ | grep -E "nginx|start"
# Expected: nginx.conf  start.sh
# If missing — return to DOCKER_CONFIG.md Step 5

# package-lock.json present in backend source
ls ~/workspace/humor-memory-game/backend/package-lock.json
# Expected: file found
# If missing — return to DOCKERFILES.md Issue 3

# Both Dockerfiles exist
ls ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
ls ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected: both files found

# Frontend Dockerfile COPY --from=builder appears before chown
grep -n "COPY --from\|chown" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected: COPY --from=builder line number is LOWER than chown line numbers
# If not — return to DOCKER_CONFIG.md Issue 6

# start.sh sed patterns use escaped placeholders
grep "sed" ~/workspace/humor-memory-game-devops/docker/frontend/start.sh
# Expected: patterns show \${API_BASE_URL} with backslash on left side
# If not — return to DOCKER_CONFIG.md Issue 5

# Docker daemon is running
docker ps
# Must return without error
```

---

## 3. Test the Backend Image

### Build the Backend Image

```bash
docker build \
  -f ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile \
  ~/workspace/humor-memory-game/backend/ \
  -t test-backend
```

**What this command does:**

| Flag | Value | Purpose |
|------|-------|---------|
| `-f` | path to Dockerfile | Specifies the Dockerfile in the DevOps repository |
| second argument | path to source directory | Sets the build context to the developer repository backend |
| `-t` | `test-backend` | Tags the resulting image for easy reference |

**Expected build output:**

```
[+] Building 45.2s (10/10) FINISHED
 => [backend 1/5] FROM docker.io/library/node:22-alpine
 => [backend 2/5] WORKDIR /app
 => [backend 3/5] RUN apk add --no-cache curl
 => [backend 4/5] COPY package*.json ./
 => [backend 5/5] RUN npm ci --omit=dev
 => exporting to image
 => naming to docker.io/library/test-backend
Successfully built xxxxxxxxx
Successfully tagged test-backend:latest
```

### Run the Backend Container

```bash
docker run -d \
  --name test-backend \
  -p 3001:3001 \
  -e DB_HOST=localhost \
  -e DB_PORT=5432 \
  -e DB_NAME=humor_memory_game \
  -e DB_USER=gameuser \
  -e DB_PASSWORD=gamepass123 \
  -e REDIS_HOST=localhost \
  -e REDIS_PORT=6379 \
  test-backend
```

### Check the Logs

```bash
docker logs test-backend
```

**Expected output — connection errors are normal here:**

```
> humor-memory-game-backend@1.0.0 start
> node server.js

Connecting to database...
Database query error (attempt 1/3):
Retrying query in 1000ms...
Database query error (attempt 2/3):
Retrying query in 1000ms...
Database query error (attempt 3/3):
Database connection test failed:
Failed to initialize services: AggregateError [ECONNREFUSED]:
  code: 'ECONNREFUSED'
Cannot start server - services not ready
```

**Why this output confirms success:**

The container started, Node.js loaded, the application code ran, and it attempted to connect to PostgreSQL on `localhost:5432`. There is no PostgreSQL running — the connection was refused as expected. The error is an application-level connection failure, not a Docker or Dockerfile problem.

The key signals that the image is correct:

- `node server.js` ran — the `CMD` instruction worked
- The application imported all dependencies without error — `npm ci` installed them correctly
- The application attempted database connection — environment variables were received
- No `ERR_REQUIRE_ESM`, no `MODULE_NOT_FOUND`, no syntax errors

---

## 4. Test the Frontend Image

### Build the Frontend Image

```bash
docker build \
  -f ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile \
  ~/workspace/humor-memory-game/frontend/ \
  -t test-frontend
```

**Expected build output — two stages visible:**

```
[+] Building 78.4s (14/14) FINISHED
 => [frontend builder 1/4] FROM docker.io/library/node:22-alpine
 => [frontend builder 2/4] WORKDIR /app
 => [frontend builder 3/4] RUN npm ci
 => [frontend builder 4/4] RUN npm run build
 => [frontend stage-2 1/6] FROM docker.io/library/nginx:1.25-alpine
 => [frontend stage-2 2/6] COPY nginx.conf /etc/nginx/conf.d/default.conf
 => [frontend stage-2 3/6] COPY start.sh /start.sh
 => [frontend stage-2 4/6] COPY --from=builder /app/dist /usr/share/nginx/html
 => [frontend stage-2 5/6] RUN chmod +x /start.sh && chown -R nginx:nginx ...
 => [frontend stage-2 6/6] USER nginx
 => exporting to image
 => naming to docker.io/library/test-frontend
Successfully built xxxxxxxxx
Successfully tagged test-frontend:latest
```

The two-stage build is visible in the output — the `builder` stage runs first producing `dist/`, then `stage-2` copies only that output into the Nginx image.

### Run the Frontend Container

```bash
docker run -d \
  --name test-frontend \
  -p 3000:80 \
  -e API_BASE_URL=/api \
  -e NODE_ENV=development \
  test-frontend
```

### Check the Logs

```bash
docker logs test-frontend
```

**Expected output in standalone mode:**

```
2026/06/11 07:03:02 [warn] 1#1: the "user" directive makes sense only if the master process runs with super-user privileges, ignored in /etc/nginx/nginx.conf:2
nginx: [warn] the "user" directive makes sense only if the master process runs with super-user privileges, ignored in /etc/nginx/nginx.conf:2
2026/06/11 07:03:02 [emerg] 1#1: host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:12
nginx: [emerg] host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:12
```

**Why this output confirms success:**

Both messages are expected in standalone mode and do not indicate a problem with the image:

| Message | Explanation |
|---------|-------------|
| `[warn] user directive` | Nginx is running as the `nginx` user (non-root) as intended. This warning appears because the master `nginx.conf` declares a `user` directive — harmless and expected when running as non-root |
| `[emerg] host not found in upstream "backend"` | Nginx validates `proxy_pass` DNS at startup. In standalone mode there is no Docker Compose network and `backend` does not resolve. This is architectural — it cannot be avoided in standalone mode |

The absence of the following errors confirms the fixes from `DOCKER_CONFIG.md` are working correctly:

- No `sed: no previous regexp` — `start.sh` sed patterns are correct
- No `Permission denied` on static files — `COPY --from=builder` ordering is correct

> **The frontend build test is the meaningful standalone confirmation.** A clean 14-step build with no errors confirms the Dockerfile, build context, and all `COPY` instructions are correct. The container cannot run standalone due to the Nginx DNS requirement — full runtime testing requires Docker Compose.

---

## 5. Clean Up Test Containers

Remove both test containers and images before proceeding to Docker Compose:

```bash
# Stop and remove test containers
docker stop test-backend test-frontend
docker rm test-backend test-frontend

# Remove test images
docker rmi test-backend test-frontend

# Verify containers are gone
docker ps -a | grep test
# Expected: no output

# Verify images are gone
docker images | grep test
# Expected: no output
```

## 6. Image Tests Checkpoint

```bash
# Both test containers removed
docker ps -a | grep test
# Expected: no output

# Both test images removed
docker images | grep test
# Expected: no output

# Backend image confirmed correct
grep "FROM" ~/workspace/humor-memory-game-devops/docker/backend/Dockerfile
# Expected: FROM node:22-alpine

# Frontend Dockerfile confirmed correct ordering
grep -n "COPY --from\|chown" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected: COPY --from=builder line number is LOWER than chown line numbers

# nginx.conf in place in frontend source directory
ls ~/workspace/humor-memory-game/frontend/nginx.conf

# start.sh in place in frontend source directory
ls ~/workspace/humor-memory-game/frontend/start.sh
```

Both images built without Dockerfile errors? Proceed to Docker Compose.

---

**Next → [DOCKER_COMPOSE.md](DOCKER_COMPOSE.md)**
