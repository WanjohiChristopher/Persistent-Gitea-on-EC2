#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="/tmp/gitea-restore.tar.gz"

# 1. Stop the container
docker compose down

# 2. Download the backup from S3
aws s3 cp "${1}" "${ARCHIVE}"

# 3. Clear current data and restore
sudo rm -rf "$HOME/data"/*
sudo tar -xzf "${ARCHIVE}" -C "$HOME/data"

# 4. Restart the container
docker compose up -d

echo "Restore complete"