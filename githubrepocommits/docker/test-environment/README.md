# Docker Test Environment - sec-levels

## Purpose

Hardened Docker containers for testing CIS hardening scripts on Ubuntu 24.04 LTS with:
- Kernel 6.8 compatibility testing
- Latest LTS kernel testing
- Isolated, reproducible test environments
- SystemD support for full service testing

## Quick Start

```bash
# Build and start test environments
./start-test.sh

# Access container
docker exec -it sec-levels-test-68 bash

# Run audit
docker exec -it sec-levels-test-68 /scripts/audit.sh level1

# Clean up
./cleanup.sh
```

## Architecture

### Containers

1. **sec-levels-test-68** - Kernel 6.8 target environment
2. **sec-levels-test-latest** - Latest LTS kernel environment

### Security Features

- Non-root user (`secuser`) with sudo access
- AppArmor enforcement
- Audit daemon (auditd)
- UFW firewall
- Minimal package installation
- Health checks for SSH service
- Restrictive umask (027)

### Volume Mounts

- `/scripts` - Hardening scripts (read-only)
- `/ansible` - Ansible playbooks (read-only)
- `/config` - Configuration templates (read-only)
- `/reports` - Audit reports (read-write)

## Manual Docker Commands

```bash
# Build specific environment
docker build -f Dockerfile.kernel68 -t sec-levels:kernel68 .

# Start with docker-compose
docker-compose up -d

# Execute commands
docker exec -it sec-levels-test-68 sudo /scripts/harden.sh level1

# View logs
docker logs -f sec-levels-test-68

# Stop containers
docker-compose down

# Full cleanup (remove volumes)
docker-compose down -v
```

## Troubleshooting

### SystemD Issues

If systemd fails to start:
```bash
# Check cgroup mount
docker exec -it sec-levels-test-68 mount | grep cgroup

# Verify privileged mode
docker inspect sec-levels-test-68 | grep Privileged
```

### AppArmor Issues

If AppArmor profiles fail:
```bash
# Check host AppArmor status
sudo aa-status

# Container AppArmor status
docker exec -it sec-levels-test-68 sudo aa-status
```

### SSH Service Not Starting

```bash
# Check SSH service status
docker exec -it sec-levels-test-68 systemctl status ssh

# Manual start
docker exec -it sec-levels-test-68 sudo systemctl start ssh
```

## Security Notes

- Containers run in **privileged mode** to allow security testing
- `seccomp=unconfined` required for security modifications
- Test containers should **NOT** be exposed to untrusted networks
- Report directory may contain sensitive audit data

## Network Configuration

- Network: `test-network` (172.25.0.0/24)
- Containers can communicate with each other
- Isolated from host network by default

## Testing Workflow

Standard testing procedure in containers:

1. Run initial audit: `docker exec -it sec-levels-test-68 /scripts/audit.sh level1`
2. Review audit report: `cat reports/audit-*.txt`
3. Apply hardening: `docker exec -it sec-levels-test-68 /scripts/harden.sh level1`
4. Verify compliance: `docker exec -it sec-levels-test-68 /scripts/audit.sh level1`
