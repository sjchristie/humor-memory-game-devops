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

# Copy built files BEFORE chown so permissions apply to actual files
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
