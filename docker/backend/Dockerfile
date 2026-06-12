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
