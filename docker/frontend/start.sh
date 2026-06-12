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
