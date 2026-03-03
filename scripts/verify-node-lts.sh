#!/usr/bin/env bash
set -euo pipefail

NODE_MAJOR="${1:-20}"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required"
  exit 1
fi

CURRENT_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [[ "$CURRENT_MAJOR" != "$NODE_MAJOR" ]]; then
  echo "Expected Node major $NODE_MAJOR, got $(node -v)"
  exit 1
fi

if ! command -v redis-server >/dev/null 2>&1; then
  echo "redis-server binary not found in PATH"
  exit 1
fi

REDIS_PORT="6380"
redis-server --port "$REDIS_PORT" --save '' --appendonly no --daemonize yes
cleanup() {
  redis-cli -p "$REDIS_PORT" shutdown >/dev/null 2>&1 || true
}
trap cleanup EXIT

export REDIS_PORT
npm install --no-audit --no-fund
npm test

node server.js --db.redis="redis://127.0.0.1:${REDIS_PORT}/8" --api.port=3100 --api.host=127.0.0.1 > /tmp/imapapi-start.log 2>&1 &
SERVER_PID=$!

for i in {1..40}; do
  if curl -sf "http://127.0.0.1:3100/v1/stats" >/dev/null; then
    break
  fi
  sleep 0.5
done

if ! curl -sf "http://127.0.0.1:3100/v1/stats" >/dev/null; then
  echo "API did not become healthy"
  cat /tmp/imapapi-start.log
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  exit 1
fi

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true

echo "Node LTS verification completed on Node $(node -v)"
