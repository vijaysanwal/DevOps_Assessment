#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/database/docker-compose.yml"
BACKUP_DIR="${ROOT_DIR}/database/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DB_NAME="${POSTGRES_DB:-assessment}"
DB_USER="${POSTGRES_USER:-assessment}"

mkdir -p "${BACKUP_DIR}"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"

docker compose -f "${COMPOSE_FILE}" exec -T db \
  pg_dump -U "${DB_USER}" -d "${DB_NAME}" --format=custom --no-owner --no-acl \
  > "${BACKUP_FILE}"

if [[ ! -s "${BACKUP_FILE}" ]]; then
  echo "ERROR: backup file is empty: ${BACKUP_FILE}" >&2
  exit 1
fi

echo "Backup created successfully: ${BACKUP_FILE}"
