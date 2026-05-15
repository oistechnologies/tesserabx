#!/usr/bin/env bash
# =============================================================================
# TesseraBX app container entrypoint.
#
# Run order:
#   1. Apply pending database migrations.
#   2. Hand off to the Ortus run.sh which starts the server.
#
# Worker and scheduler containers share this image but skip migrations
# (they don't own the schema; they consume it). They override CMD in
# compose.yaml to invoke `${BUILD_DIR}/run.sh` directly.
#
# compose.yaml's `depends_on: db: condition: service_healthy` makes
# this safe to run unconditionally: the database is already accepting
# connections by the time we get here.
# =============================================================================

set -euo pipefail

echo "[tesserabx-app] entrypoint $(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "${APP_DIR:-/app}"

MIGRATIONS_DIR="${APP_DIR:-/app}/resources/database/migrations"

if [ -d "${MIGRATIONS_DIR}" ] && [ -n "$(find "${MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.cfc' 2>/dev/null)" ]; then
    echo "[tesserabx-app] ensuring migration tracker table exists..."
    box migrate install 2>&1 | grep -v "already installed" || true

    echo "[tesserabx-app] running pending database migrations..."
    box migrate up --force
else
    echo "[tesserabx-app] no migration files at ${MIGRATIONS_DIR} - skipping"
fi

echo "[tesserabx-app] starting server via ${BUILD_DIR}/run.sh..."
exec "${BUILD_DIR}/run.sh"
