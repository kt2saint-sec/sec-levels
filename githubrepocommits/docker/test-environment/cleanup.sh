#!/bin/bash
# cleanup.sh - Clean up Docker test environment
# Purpose: Remove sec-levels test containers and images
# Author: sec-levels Development Team

set -euo pipefail

echo "[*] Cleaning up test environment..."
cd "$(dirname "$0")/.."

# Stop and remove containers
echo "[*] Stopping containers..."
docker-compose down -v

# Remove images
echo "[*] Removing Docker images..."
docker rmi sec-levels:kernel68 sec-levels:latest 2>/dev/null || echo "[!] Images already removed or not found"

# Clean up dangling images
echo "[*] Cleaning up dangling images..."
docker image prune -f

echo "[+] Cleanup complete!"
