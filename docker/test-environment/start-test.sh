#!/bin/bash
# start-test.sh - Build and start hardened Docker test environments
# Purpose: Initialize sec-levels testing containers with security hardening
# Author: sec-levels Development Team

set -euo pipefail

echo "[*] Building hardened Docker test environments..."
cd "$(dirname "$0")/.."

# Build images with security scanning
echo "[*] Building kernel 6.8 test environment..."
docker build -f Dockerfile.kernel68 -t sec-levels:kernel68 .

echo "[*] Building latest kernel test environment..."
docker build -f Dockerfile.latest -t sec-levels:latest .

# Security scan images (if Docker Scout or Trivy available)
if command -v docker >/dev/null 2>&1 && docker scout version >/dev/null 2>&1; then
    echo "[*] Scanning images for vulnerabilities..."
    docker scout cves sec-levels:kernel68 || true
    docker scout cves sec-levels:latest || true
elif command -v trivy >/dev/null 2>&1; then
    echo "[*] Scanning images with Trivy..."
    trivy image sec-levels:kernel68 || true
    trivy image sec-levels:latest || true
else
    echo "[!] No vulnerability scanner found (install docker-scout or trivy for security scanning)"
fi

# Start containers
echo "[*] Starting test containers..."
docker-compose up -d

# Wait for containers to be healthy
echo "[*] Waiting for containers to be ready..."
sleep 10

# Verify containers are running
echo "[*] Container status:"
docker ps | grep sec-levels || echo "[!] Warning: No sec-levels containers running"

echo ""
echo "[+] Test environment ready!"
echo "    Kernel 6.8 container: sec-levels-test-68"
echo "    Latest kernel container: sec-levels-test-latest"
echo ""
echo "Access containers:"
echo "  docker exec -it sec-levels-test-68 bash"
echo "  docker exec -it sec-levels-test-latest bash"
echo ""
echo "Run tests:"
echo "  docker exec -it sec-levels-test-68 /scripts/audit.sh level1"
echo ""
echo "View logs:"
echo "  docker logs sec-levels-test-68"
echo "  docker logs sec-levels-test-latest"
