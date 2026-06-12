# Docker Config

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Docker Config  
**Previous:** [DOCKERFILES.md](DOCKERFILES.md)  
**Next:** [DOCKER_IMAGE_TESTS.md](DOCKER_IMAGE_TESTS.md)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Create nginx.conf](#2-create-nginxconf)
3. [Create start.sh](#3-create-startsh)
4. [Create .dockerignore Files](#4-create-dockerignore-files)
5. [Copy Supporting Files Into the Frontend Source Directory](#5-copy-supporting-files-into-the-frontend-source-directory)
6. [Docker Config Checkpoint](#6-docker-config-checkpoint)

---

## 1. Overview

This document creates the three supporting configuration files required by the frontend container, and the two `.dockerignore` files that control what gets sent to Docker during the build.

| File | Location | Purpose |
|------|----------|---------|
| `nginx.conf` | `docker/frontend/` in DevOps repo | Nginx static file serving and API reverse proxy configuration |
| `start.sh` | `docker/frontend/` in DevOps repo | Container entrypoint — injects environment variables before Nginx starts |
| `backend/.dockerignore` | `humor-memory-game/backend/` in developer repo | Excludes unnecessary files from the backend build context |
| `frontend/.dockerignore` | `humor-memory-game/frontend/` in developer repo | Excludes unnecessary files from the frontend build context |

After these files are created, the supporting files must be physically copied into the frontend source directory before building — covered in Step 5.

---

## 2. Create nginx.conf

Nginx serves as both the static file server for the frontend and a reverse proxy that forwards all `/api/*` requests to the backend container.

```bash
cd ~/workspace/humor-memory-game-devops/docker/frontend
```

### Annotated Version — Read First

```nginx
# Nginx Configuration
# Serves static files and proxies API requests to the backend
# Location in container: /etc/nginx/conf.d/default.conf

server {
    # Listen on port 80 (HTTP)
    listen 80;

    # Match all hostnames
    server_name _;

    # Root directory for static files
    root /usr/share/nginx/html;

    # Default file to serve
    index index.html;

    # ========================================================================
    # LOCATION 1: Serve static files with SPA fallback
    # ========================================================================
    location / {
        # Try files in order:
        # 1. If the file exists (e.g. style.css) — serve it directly
        # 2. If a directory exists — serve it
        # 3. Otherwise — fall back to index.html (JavaScript handles routing)
        try_files $uri $uri/ /index.html;
    }

    # ========================================================================
    # LOCATION 2: Proxy API requests to the backend
    # ========================================================================
    location /api/ {
        # Forward all /api/* requests to the backend container
        #
        # Request:  http://localhost:3000/api/games
        # Becomes:  http://backend:3001/api/games
        #
        # "backend" is the Docker Compose service name
        # Docker DNS resolves it to the backend container's internal IP
        # This only works inside a Docker Compose network — not in standalone mode
        proxy_pass http://backend:3001/api/;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ========================================================================
    # LOCATION 3: Cache static assets
    # ========================================================================
    location ~* \.(js|css|png|jpg|gif|ico|svg)$ {
        # Cache these files in the browser for 1 year
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # ========================================================================
    # Security — hide Nginx version from error pages
    # ========================================================================
    server_tokens off;
}
```

> **How Docker DNS works:** In a Docker Compose network, each service is reachable by its service name. `http://backend:3001` resolves because Docker creates a DNS entry for `backend` pointing to the backend container's internal IP. This only works when containers are on the same Docker Compose network — not in standalone `docker run` mode.

### Production Copy — Run This Command

```bash
cat > nginx.conf << 'EOF'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend:3001/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ~* \.(js|css|png|jpg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    server_tokens off;
}
EOF
```

Verify:

```bash
cat nginx.conf
```

---

## 3. Create start.sh

The `start.sh` script is the container entrypoint. It runs before Nginx starts, substituting environment variable placeholders in the compiled HTML and JavaScript files, then starting Nginx in the foreground.

```bash
cd ~/workspace/humor-memory-game-devops/docker/frontend
```

### Annotated Version — Read First

```sh
#!/bin/sh
# Frontend Startup Script
# Runs when the container starts
# Purpose: inject environment variables into static files, then start Nginx

# ========================================================================
# Environment Variable Defaults
# ========================================================================

API_BASE_URL="${API_BASE_URL:-/api}"

# Syntax: ${VARIABLE:-default_value}
# If API_BASE_URL is set in the environment — use it
# If API_BASE_URL is not set — default to /api
#
# This allows the same image to run in development and production
# without rebuilding — only the environment variable changes

# ========================================================================
# Replace placeholders in HTML files
# ========================================================================

for file in /usr/share/nginx/html/*.html; do
    if [ -f "$file" ]; then
        # Pattern: s|\${VARIABLE}|actual_value|g
        #
        # The left side uses \$ to match the LITERAL string ${VARIABLE}
        # in the HTML file — not the shell-expanded value
        #
        # The right side uses ${VARIABLE} which the shell DOES expand
        # to the actual runtime value
        #
        # Why \$ on the left?
        # Without it: s|/api|/api|g  — replaces /api with /api (no effect)
        # With it:    s|${API_BASE_URL}|/api|g  — replaces the placeholder
        #
        # Why not ** glob?
        # ** only works in bash — Alpine Linux uses sh by default
        # The for loop with *.html covers the root html directory
        # find is used below for subdirectories

        sed -i "s|\${API_BASE_URL}|${API_BASE_URL}|g" "$file"
        sed -i "s|\${NODE_ENV}|${NODE_ENV:-production}|g" "$file"
        sed -i "s|\${BUILD_TIMESTAMP}|${BUILD_TIMESTAMP:-}|g" "$file"
    fi
done

# ========================================================================
# Replace placeholders in JavaScript files
# ========================================================================

# Use find to recurse into subdirectories
# find works in all POSIX sh — unlike ** which is bash-only

find /usr/share/nginx/html -name "*.js" | while read file; do
    if [ -f "$file" ]; then
        sed -i "s|\${API_BASE_URL}|${API_BASE_URL}|g" "$file"
    fi
done

# ========================================================================
# Start Nginx in the Foreground
# ========================================================================

exec nginx -g "daemon off;"

# exec replaces the shell process with Nginx
# "daemon off;" keeps Nginx in the foreground
# Docker requires the main process to stay in the foreground —
# if Nginx daemonises, Docker sees the process exit and stops the container
```

### Production Copy — Run This Command

```bash
cat > start.sh << 'EOF'
#!/bin/sh

API_BASE_URL="${API_BASE_URL:-/api}"

for file in /usr/share/nginx/html/*.html; do
    if [ -f "$file" ]; then
        sed -i "s|\${API_BASE_URL}|${API_BASE_URL}|g" "$file"
        sed -i "s|\${NODE_ENV}|${NODE_ENV:-production}|g" "$file"
        sed -i "s|\${BUILD_TIMESTAMP}|${BUILD_TIMESTAMP:-}|g" "$file"
    fi
done

find /usr/share/nginx/html -name "*.js" | while read file; do
    if [ -f "$file" ]; then
        sed -i "s|\${API_BASE_URL}|${API_BASE_URL}|g" "$file"
    fi
done

exec nginx -g "daemon off;"
EOF
chmod +x start.sh
```

Verify:

```bash
ls -la start.sh
# Expected: -rwxr-xr-x

cat start.sh
# sed patterns must show \${API_BASE_URL} with the backslash on the left side
```

---

### 🔴 ISSUE 4 — Frontend Config Files Outside Build Context

**Where it occurred:** Frontend Docker build — `COPY nginx.conf` step

**Symptom:**

```
ERROR [frontend stage-2 3/5] COPY nginx.conf /etc/nginx/conf.d/default.conf
------
COPY failed: stat nginx.conf: file does not exist
```

**Root Cause:**
`nginx.conf` and `start.sh` are stored in the DevOps repository (`humor-memory-game-devops/docker/frontend/`). The frontend Dockerfile's build context points to the frontend source directory (`humor-memory-game/frontend/`). Docker's build daemon operates in a strict sandbox — it can only access files within the build context. It cannot reach outside that boundary, even to sibling directories on the same machine.

Symbolic links were tested as a potential solution but also failed. Docker's build daemon does not follow symlinks that point outside the build context.

**How the issue was identified:**

```bash
# Confirm nginx.conf is missing from the build context directory
ls ~/workspace/humor-memory-game/frontend/
# nginx.conf not listed — only source files present
```

**Fix:**
Physically copy the files into the build context directory before building — covered in Step 5 of this document.

**Prevention:**
Always run the copy step before building the frontend image. The copy commands are included in the `DOCKER_IMAGE_TESTS.md` pre-build checklist.

---

### 🔴 ISSUE 5 — `sed` Empty Pattern Error in start.sh

**Where it occurred:** Frontend container startup — `start.sh` execution

**Symptom:**

```
sed: no previous regexp
sed: no previous regexp
sed: no previous regexp
```

**Root Cause:**
The original `sed` substitution patterns used shell-expanded variables on both sides:

```sh
sed -i "s|${NODE_ENV}|${NODE_ENV:-production}|g" "$file"
```

When `NODE_ENV` is not set, the shell expands `${NODE_ENV}` to an empty string before `sed` sees it, giving:

```sh
sed -i "s||production|g" "$file"
```

An empty pattern in `sed` means "reuse the previous regexp". If no previous regexp exists, `sed` throws `no previous regexp` and exits with an error.

**How the issue was identified:**

```bash
docker logs test-frontend
# Output: sed: no previous regexp  (repeated three times — once per sed call)
```

**Fix:**
Escape the `$` on the left side of each pattern so the shell does not expand it. The left side must be a literal placeholder string — the right side is correctly expanded to the runtime value:

```sh
# Wrong — shell expands both sides before sed sees them
sed -i "s|${NODE_ENV}|${NODE_ENV:-production}|g" "$file"

# Correct — left side is literal, right side is expanded
sed -i "s|\${NODE_ENV}|${NODE_ENV:-production}|g" "$file"
```

**Prevention:**
In `sh` scripts, always escape `$` in `sed` patterns when the intent is to match a literal placeholder string in a file — not a shell variable value.

---

### 🔴 ISSUE 6 — `chown` Runs Before Files Are Copied (`Permission Denied`)

**Where it occurred:** Frontend container startup — `start.sh` writing to static files

**Symptom:**

```
sed: can't create temp file '/usr/share/nginx/html/scripts/game.jsXXXXXX': Permission denied
```

**Root Cause:**
The original Dockerfile ran `chown -R nginx:nginx /usr/share/nginx/html` before copying the compiled static files from the builder stage:

```dockerfile
# Wrong order
RUN chmod +x /start.sh &&     chown -R nginx:nginx /usr/share/nginx/html   ← runs on empty directory

COPY --from=builder /app/dist /usr/share/nginx/html  ← files copied as root AFTER chown
```

The `chown` set ownership on an empty directory. When `COPY --from=builder` ran next, Docker copied the files from the builder stage as `root`. When `start.sh` later tried to modify those files with `sed -i`, the `nginx` user was denied write access.

**How the issue was identified:**

```bash
# Check the Dockerfile instruction order
grep -n "COPY --from\|chown\|chmod\|USER" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Output showed COPY --from=builder AFTER the chown block
```

**Fix:**
Move `COPY --from=builder` to before the `chown` block so permissions are applied to the actual files:

```dockerfile
# Correct order
COPY --from=builder /app/dist /usr/share/nginx/html  ← copy files first

RUN chmod +x /start.sh &&     chown -R nginx:nginx /usr/share/nginx/html        ← then set ownership on real files
```

**Prevention:**
In a multi-stage Dockerfile, always copy files into a directory before running `chown` on that directory. A `chown` on an empty directory has no effect on files copied in later steps.

---

## 4. Create .dockerignore Files

`.dockerignore` files prevent unnecessary files from being sent to the Docker daemon during the build. Both files are created in the **developer repository** — alongside the source code they apply to.

### Backend .dockerignore

```bash
cat > ~/workspace/humor-memory-game/backend/.dockerignore << 'EOF'
# Dependencies — reinstalled inside the container by npm ci
node_modules/

# Development logs
npm-debug.log*
*.log

# Environment secrets
.env
.env.*

# Git history
.git/
.gitignore

# Test files
__tests__/
*.test.js
*.spec.js
coverage/

# Editor files
.vscode/
.idea/
EOF
```

### Frontend .dockerignore

```bash
cat > ~/workspace/humor-memory-game/frontend/.dockerignore << 'EOF'
# Dependencies — reinstalled inside the container
node_modules/

# Previous build output — rebuilt fresh inside the container
dist/

# Development logs
npm-debug.log*
*.log

# Environment files
.env
.env.*

# Git history
.git/
.gitignore

# Editor files
.vscode/
.idea/
EOF
```

Verify both files were created:

```bash
ls ~/workspace/humor-memory-game/backend/.dockerignore
ls ~/workspace/humor-memory-game/frontend/.dockerignore
```

---

## 5. Copy Supporting Files Into the Frontend Source Directory

`nginx.conf` and `start.sh` live in the DevOps repository but the frontend Dockerfile's build context points to the developer repository. They must be physically copied into the build context before every build:

```bash
cp ~/workspace/humor-memory-game-devops/docker/frontend/nginx.conf    ~/workspace/humor-memory-game/frontend/nginx.conf

cp ~/workspace/humor-memory-game-devops/docker/frontend/start.sh    ~/workspace/humor-memory-game/frontend/start.sh
```

Verify:

```bash
ls ~/workspace/humor-memory-game/frontend/ | grep -E "nginx|start"
# Expected: nginx.conf  start.sh
```

> **Important:** These copied files are not tracked by the developer repository's git. If you pull a fresh clone of the developer repository, you must run this copy step again before building.

---

## 6. Docker Config Checkpoint

```bash
# nginx.conf exists in DevOps repository
ls ~/workspace/humor-memory-game-devops/docker/frontend/nginx.conf

# start.sh exists in DevOps repository and is executable
ls -la ~/workspace/humor-memory-game-devops/docker/frontend/start.sh
# Expected: -rwxr-xr-x

# Verify start.sh sed patterns use escaped placeholders
grep "sed" ~/workspace/humor-memory-game-devops/docker/frontend/start.sh
# Expected: patterns show \${API_BASE_URL} with backslash on left side

# Verify frontend Dockerfile copies files before chown
grep -n "COPY --from\|chown" ~/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
# Expected: COPY --from=builder line number is LOWER than chown line numbers

# nginx.conf copied to frontend source directory
ls ~/workspace/humor-memory-game/frontend/nginx.conf

# start.sh copied to frontend source directory
ls ~/workspace/humor-memory-game/frontend/start.sh

# Both .dockerignore files exist
ls ~/workspace/humor-memory-game/backend/.dockerignore
ls ~/workspace/humor-memory-game/frontend/.dockerignore

# DevOps docker frontend directory contents
ls ~/workspace/humor-memory-game-devops/docker/frontend/
# Expected: Dockerfile  nginx.conf  start.sh
```

All checks passing? Proceed to standalone image testing.

---

**Next → [DOCKER_IMAGE_TESTS.md](DOCKER_IMAGE_TESTS.md)**
