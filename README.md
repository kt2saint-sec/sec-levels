# sec-levels - CIS Hardening Automation for Ubuntu 24.04 LTS

**Status:** Under Active Development

## Project Overview

Automated CIS (Center for Internet Security) benchmark hardening for Ubuntu 24.04 LTS with support for kernel 6.8+ compatibility.

## Features (Planned)

- CIS Level 1 and Level 2 compliance automation
- Kernel 6.8+ compatibility validation
- Automated audit reporting
- Rollback capabilities
- Ansible playbook integration
- Docker-based testing environments

## Quick Start

```bash
# Clone repository
git clone <repository-url>
cd sec-levels

# Run audit
sudo ./scripts/audit.sh level1

# Apply hardening
sudo ./scripts/harden.sh level1

# Verify compliance
sudo ./scripts/audit.sh level1
```

## Documentation

- [Development Journal](docs/DEVELOPMENT.md)
- [Usage Guide](docs/USAGE.md)
- [CIS Control Mapping](docs/CIS-MAPPING.md)
- [Error Tracking](docs/ERRORS.md)

## Testing

See [docker/test-environment/README.md](docker/test-environment/README.md) for Docker testing.
See [vm-testing/README.md](vm-testing/README.md) for VM testing.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Author

Security Levels Development Team
