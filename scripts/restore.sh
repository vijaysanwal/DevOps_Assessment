#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/database/docker-compose.yml"
BACKUP_DIR="${ROOT_DIR}/database/backups"
DB_USER="${POSTGRES_USER:-assessment}"
TARGET_DB="${1:-assessment_restore_$(date -u +%Y%m%dT%H%M%SZ)}"
BACKUP_FILE="${2:-}"

if [[ -z "${BACKUP_FILE}" ]]; then
  BACKUP_FILE="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
fi

if [[ -z "${BACKUP_FILE}" || ! -s "${BACKUP_FILE}" ]]; then
  echo "Usage: $0 [fresh_target_database] [backup_file]" >&2
  echo "No valid backup found in ${BACKUP_DIR}" >&2
  exit 1
fi

if [[ ! "${TARGET_DB}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
  echo "ERROR: target database name must contain only letters, numbers and underscores." >&2
  exit 1
fi

# Restore always targets a new database; never drops or overwrites the source DB.
docker compose -f "${COMPOSE_FILE}" exec -T db \
  createdb -U "${DB_USER}" "${TARGET_DB}"

cat "${BACKUP_FILE}" | docker compose -f "${COMPOSE_FILE}" exec -T db \
  pg_restore -U "${DB_USER}" -d "${TARGET_DB}" --no-owner --no-privileges

echo "Restore completed into fresh database: ${TARGET_DB}"
echo "Verify with:"
echo "docker compose -f ${COMPOSE_FILE} exec db psql -U ${DB_USER} -d ${TARGET_DB} -c \"SELECT COUNT(*) FROM hotel_bookings;\""
