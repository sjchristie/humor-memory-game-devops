# Docker Compose

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Docker Compose  
**Previous:** [DOCKER_IMAGE_TESTS.md](DOCKER_IMAGE_TESTS.md)  
**Next:** [BUILD_AND_START.md](BUILD_AND_START.md)

---

## Table of Contents

1. [What docker-compose.yml Does](#1-what-docker-composeyml-does)
2. [Create docker-compose.yml](#2-create-docker-composeyml)
3. [Create the .env File](#3-create-the-env-file)
4. [Create the .env.example Template](#4-create-the-envexample-template)
5. [Understanding the Network Configuration](#5-understanding-the-network-configuration)
6. [Understanding the Volume Configuration](#6-understanding-the-volume-configuration)
7. [Docker Compose Checkpoint](#7-docker-compose-checkpoint)

---

## 1. What docker-compose.yml Does

`docker-compose.yml` is the orchestration file. It replaces the need to manually run individual `docker build` and `docker run` commands for each service. It defines:

- **Which services to run** — frontend, backend, postgres, redis
- **How to build each image** — which Dockerfile, which source directory
- **How services connect to each other** — networks
- **Where to persist data** — volumes
- **What environment variables each container receives**
- **Health checks** to determine when a service is ready
- **Restart policies** for self-healing containers
- **Port mappings** between the VM host and containers
- **Startup ordering** so dependent services wait for their dependencies

---

## 2. Create docker-compose.yml

```bash
cd ~/workspace/humor-memory-game-devops
```

### Annotated Version — Read First

Read this version to understand every decision before creating the file.

```yaml
# Docker Compose — Complete Application Stack
# Defines all 4 services: PostgreSQL, Redis, Backend, Frontend
# Run with: docker compose up -d

services:

  # ==========================================================================
  # SERVICE 1: PostgreSQL Database
  # ==========================================================================
  # Purpose: Persistent data storage for users, games, sessions
  # Network: backend-network only (hidden from frontend)
  # Port:    5432 (internal only — not published to host)
  # ==========================================================================

  postgres:
    image: postgres:15.2-alpine

    container_name: humor-game-postgres

    # unless-stopped: restart automatically unless explicitly stopped
    # Keeps the database running even if it crashes
    restart: unless-stopped

    environment:
      # ${VARIABLE:-default} syntax:
      # If the variable is set in .env — use it
      # If not set — use the default value after :-
      # Same pattern applied to all variables below

      POSTGRES_DB: ${DB_NAME:-humor_memory_game}
      POSTGRES_USER: ${DB_USER:-gameuser}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-gamepass123}
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"

    volumes:
      # Named volume for persistent database storage
      # Data survives container restarts and removal
      # Only destroyed by: docker compose down -v
      - postgres_data:/var/lib/postgresql/data

      # Mount the schema SQL file into the init directory
      # PostgreSQL automatically runs .sql files in initdb.d/ on first startup
      # :ro = read-only mount — container cannot modify the source file
      - ../humor-memory-game/database/combined-init.sql:/docker-entrypoint-initdb.d/01-combined-init.sql:ro

    networks:
      # Backend network only
      # frontend container has no DNS entry for postgres
      - backend-network

    healthcheck:
      # pg_isready confirms PostgreSQL is accepting connections
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-gameuser} -d ${DB_NAME:-humor_memory_game}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # ==========================================================================
  # SERVICE 2: Redis Cache
  # ==========================================================================
  # Purpose: Fast in-memory caching for sessions and leaderboards
  # Network: backend-network only (hidden from frontend)
  # Port:    6379 (internal only — not published to host)
  # ==========================================================================

  redis:
    image: redis:7.0-alpine

    container_name: humor-game-redis

    restart: unless-stopped

    # Redis is configured via command-line arguments, not environment variables
    # --appendonly yes: persist data to disk (survives restarts)
    # --requirepass:    password-protect the Redis instance
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-gamepass123}

    volumes:
      # Persist Redis append-only file to named volume
      - redis_data:/data

    networks:
      - backend-network

    healthcheck:
      # redis-cli ping returns PONG if Redis is healthy
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-gamepass123}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

  # ==========================================================================
  # SERVICE 3: Backend API
  # ==========================================================================
  # Purpose: Express.js REST API — business logic, database queries
  # Networks: backend-network AND frontend-network (bridges both)
  # Port:    3001 (published to host)
  # ==========================================================================

  backend:
    build:
      # context: where Docker looks for source files (the build context)
      # Points to developer repository backend directory
      context: ../humor-memory-game/backend/

      # dockerfile: absolute path to the Dockerfile
      # Must be absolute — Docker Compose resolves dockerfile relative to
      # context, not to docker-compose.yml
      dockerfile: /home/devops/workspace/humor-memory-game-devops/docker/backend/Dockerfile

    image: humor-memory-game-backend:latest

    container_name: humor-game-backend

    restart: unless-stopped

    environment:
      NODE_ENV: ${NODE_ENV:-development}
      PORT: ${API_PORT:-3001}

      # CRITICAL: DB_HOST must be "postgres" — NOT localhost
      # In Docker, localhost = the container's own loopback interface
      # Other containers are unreachable via localhost
      # Docker DNS resolves the service name "postgres" to the postgres container IP
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: ${DB_NAME:-humor_memory_game}
      DB_USER: ${DB_USER:-gameuser}
      DB_PASSWORD: ${DB_PASSWORD:-gamepass123}

      # Same principle: "redis" resolves to the redis container via Docker DNS
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD:-gamepass123}

      JWT_SECRET: ${JWT_SECRET:-dev-secret-key-change-in-production}
      API_BASE_URL: ${API_BASE_URL:-/api}
      CORS_ORIGIN: ${CORS_ORIGIN:-http://frontend:80}

    ports:
      # HOST:CONTAINER
      # Publishes container port 3001 to host port 3001
      # Accessible at http://192.168.30.11:3001 from local network
      - "3001:3001"

    networks:
      # On both networks — bridges frontend and backend
      - backend-network
      - frontend-network

    depends_on:
      # Backend waits for postgres and redis to be healthy before starting
      # Prevents startup failures from attempting connections too early
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  # ==========================================================================
  # SERVICE 4: Frontend
  # ==========================================================================
  # Purpose: Nginx serving static HTML/CSS/JS, proxying /api/* to backend
  # Network: frontend-network only
  # Port:    3000 (published to host — user-facing entry point)
  # ==========================================================================

  frontend:
    build:
      context: ../humor-memory-game/frontend/
      dockerfile: /home/devops/workspace/humor-memory-game-devops/docker/frontend/Dockerfile

    container_name: humor-game-frontend

    restart: unless-stopped

    environment:
      NODE_ENV: ${NODE_ENV:-development}
      API_BASE_URL: ${API_BASE_URL:-/api}

    ports:
      # User accesses: http://192.168.30.11:3000
      # Maps to Nginx on container port 80
      - "3000:80"

    networks:
      # frontend-network only
      # No DNS entry for postgres or redis on this network
      - frontend-network

    depends_on:
      backend:
        condition: service_started

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

# =============================================================================
# VOLUMES — Persistent Storage
# =============================================================================
# Named volumes are created and managed by Docker
# Data persists even if containers are stopped or removed
# Only destroyed with: docker compose down -v

volumes:
  postgres_data:
    driver: local

  redis_data:
    driver: local

# =============================================================================
# NETWORKS — Service Communication
# =============================================================================

networks:
  # Internal network for database services
  # Members: postgres, redis, backend
  # Isolated from: frontend
  backend-network:
    driver: bridge

  # Network for user-facing services
  # Members: frontend, backend
  # Isolated from: postgres, redis
  frontend-network:
    driver: bridge
```

### Production Copy — Run This Command

```bash
cat > docker-compose.yml << 'EOF'
services:

  postgres:
    image: postgres:15.2-alpine
    container_name: humor-game-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-humor_memory_game}
      POSTGRES_USER: ${DB_USER:-gameuser}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-gamepass123}
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../humor-memory-game/database/combined-init.sql:/docker-entrypoint-initdb.d/01-combined-init.sql:ro
    networks:
      - backend-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-gameuser} -d ${DB_NAME:-humor_memory_game}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7.0-alpine
    container_name: humor-game-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-gamepass123}
    volumes:
      - redis_data:/data
    networks:
      - backend-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-gamepass123}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

  backend:
    build:
      context: ../humor-memory-game/backend/
      dockerfile: /home/devops/workspace/humor-memory-game-devops/docker/backend/Dockerfile
    image: humor-memory-game-backend:latest
    container_name: humor-game-backend
    restart: unless-stopped
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      PORT: ${API_PORT:-3001}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: ${DB_NAME:-humor_memory_game}
      DB_USER: ${DB_USER:-gameuser}
      DB_PASSWORD: ${DB_PASSWORD:-gamepass123}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD:-gamepass123}
      JWT_SECRET: ${JWT_SECRET:-dev-secret-key-change-in-production}
      API_BASE_URL: ${API_BASE_URL:-/api}
      CORS_ORIGIN: ${CORS_ORIGIN:-http://frontend:80}
    ports:
      - "3001:3001"
    networks:
      - backend-network
      - frontend-network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  frontend:
    build:
      context: ../humor-memory-game/frontend/
      dockerfile: /home/devops/workspace/humor-memory-game-devops/docker/frontend/Dockerfile
    image: humor-memory-game-frontend:latest
    container_name: humor-game-frontend
    restart: unless-stopped
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      API_BASE_URL: ${API_BASE_URL:-/api}
    ports:
      - "3000:80"
    networks:
      - frontend-network
    depends_on:
      backend:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local

networks:
  backend-network:
    driver: bridge
  frontend-network:
    driver: bridge
EOF
```

Verify the file was created and YAML is valid:

```bash
cat docker-compose.yml

docker compose config
# Expected: resolved configuration output with no errors
# Any YAML syntax error or missing variable will be reported here
```

---

## 3. Create the .env File

The `.env` file contains secrets — database passwords, JWT keys, and other sensitive values. Docker Compose reads this file and injects the values into containers as environment variables.

**This file must never be committed to git.**

```bash
cd ~/workspace/humor-memory-game-devops
```

```bash
cat > .env << 'EOF'
# Environment Configuration — DEVELOPMENT ONLY
# NEVER commit this file to git

# Application
NODE_ENV=development

# Database Configuration
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=gamepass123
DB_PORT=5432

# Redis Cache Configuration
REDIS_PASSWORD=gamepass123
REDIS_PORT=6379

# Backend API Configuration
API_PORT=3001
API_BASE_URL=/api
CORS_ORIGIN=http://frontend:80

# Security — CHANGE IN PRODUCTION
# Generate with: openssl rand -base64 32
JWT_SECRET=dev-secret-key-change-in-production
SESSION_SECRET=dev-session-key-change-in-production
EOF
```

Verify:

```bash
cat .env
# Confirm all values are set — none should be empty or placeholder
```

---

## 4. Create the .env.example Template

`.env.example` is a safe template showing which variables are required without exposing real values. This file is committed to git so anyone cloning the repository knows what to configure.

```bash
cat > .env.example << 'EOF'
# Environment Configuration Template
# Copy to .env and update values for your environment
#
# IMPORTANT:
# - DO NOT COMMIT .env — it contains secrets
# - This file (.env.example) is safe to commit — no actual values

# Application Environment
NODE_ENV=development

# Database Configuration
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=change_me_in_production
DB_PORT=5432

# Redis Cache Configuration
REDIS_PASSWORD=change_me_in_production
REDIS_PORT=6379

# Backend API Configuration
API_PORT=3001
API_BASE_URL=/api
CORS_ORIGIN=http://frontend:80

# Security — MUST CHANGE IN PRODUCTION
# Generate with: openssl rand -base64 32
JWT_SECRET=change_me_in_production
SESSION_SECRET=change_me_in_production
EOF
```

Verify:

```bash
cat .env.example
```

> All git operations — staging, committing, and pushing files including `docker-compose.yml` and `.env.example` — are covered in [GIT_WORKFLOW.md](GIT_WORKFLOW.md) Section 2.

---

## 5. Understanding the Network Configuration

Two isolated bridge networks enforce security at the Docker network layer — not by policy or configuration.

```
frontend-network
├─ frontend     ← Nginx — serves static files, proxies /api/*
└─ backend      ← Express.js API

backend-network
├─ backend      ← Express.js API (member of both networks)
├─ postgres     ← PostgreSQL database
└─ redis        ← Redis cache
```

**What this enforces:**

The `frontend` container is on `frontend-network` only. It has no DNS entry for `postgres` or `redis`. A direct connection attempt from the frontend would return a DNS resolution failure — `postgres` simply does not exist on `frontend-network`.

The `backend` container is on **both** networks intentionally — it bridges the user-facing network and the database network. All data access must flow through the backend API.

**Why this matters:**

Without network isolation, a misconfigured application could theoretically bypass the backend and query the database directly. Network isolation makes this architecturally impossible — not just a policy decision.

---

## 6. Understanding the Volume Configuration

### postgres_data

```yaml
- postgres_data:/var/lib/postgresql/data
```

PostgreSQL stores all database files in `/var/lib/postgresql/data` inside the container. Without a named volume this data lives in the container's writable layer and is destroyed when the container is removed. The named volume maps this directory to Docker-managed storage on the VM host.

Data survives:
- Container restarts — `docker compose restart postgres`
- Container removal and recreation — `docker compose down` then `docker compose up -d`

> **Exception:** `docker compose down -v` removes named volumes and destroys all data. Use this only when a completely fresh database is needed — for example to re-run the init SQL from scratch.

### redis_data

```yaml
- redis_data:/data
```

Redis is primarily in-memory but writes periodic snapshots and the append-only file to `/data`. The named volume persists these files so the cache is not completely empty after a restart.

### Database Initialisation Mount

```yaml
- ../humor-memory-game/database/combined-init.sql:/docker-entrypoint-initdb.d/01-combined-init.sql:ro
```

This mounts the SQL schema file from the developer repository into a special directory inside the PostgreSQL container. PostgreSQL's official Docker image automatically executes any `.sql` files found in `/docker-entrypoint-initdb.d/` **on first startup only** — when the `postgres_data` volume is empty.

The `:ro` suffix mounts the file as read-only — the container cannot modify the source schema file.

---

## 7. Docker Compose Checkpoint

```bash
cd ~/workspace/humor-memory-game-devops

# docker-compose.yml exists
ls docker-compose.yml
# Expected: file found

# YAML syntax is valid and variables resolve correctly
docker compose config
# Expected: full resolved configuration output — no errors
# Any YAML syntax error or missing variable is reported here

# .env exists with real values
cat .env
# Expected: all variables set — none empty or placeholder

# .env is git-ignored
git check-ignore -v .env
# Expected: .gitignore:1:.env    .env

# Schema SQL file is accessible at the path referenced in docker-compose.yml
ls ../humor-memory-game/database/combined-init.sql
# Expected: file found
```

All checks passing? Proceed to building and starting the stack.

---

**Next → [BUILD_AND_START.md](BUILD_AND_START.md)**
