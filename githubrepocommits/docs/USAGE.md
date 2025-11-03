# Usage Guide - sec-levels

**Project:** CIS Hardening Automation for Ubuntu 24.04 LTS
**Last Updated:** 2025-11-02

## Quick Start

### Prerequisites

- Ubuntu 24.04 LTS server
- Root or sudo access
- Python 3 (for Ansible)
- Git

### Installation

```bash
# Clone repository
git clone <repository-url>
cd sec-levels

# Make scripts executable
chmod +x scripts/*.sh
chmod +x scripts/lib/*.sh
chmod +x docker/test-environment/*.sh
chmod +x tests/**/*.sh
```

### Basic Usage

```bash
# Run audit
sudo ./scripts/audit.sh level1

# Review audit report
cat reports/audit-*.txt

# Apply hardening
sudo ./scripts/harden.sh level1

# Verify compliance
sudo ./scripts/audit.sh level1

# Rollback if needed
sudo ./scripts/rollback.sh
```

---

## Detailed Usage

### Audit Command

```bash
./scripts/audit.sh [level1|level2|custom]
```

**Options:**
- `level1` - CIS Level 1 Server profile
- `level2` - CIS Level 2 Server profile (includes Level 1)
- `custom` - Custom security profile

**Output:**
- Console output with pass/fail status
- Detailed report in `/reports/audit-YYYYMMDD-HHMMSS.txt`

### Hardening Command

```bash
./scripts/harden.sh [level1|level2|custom] [--backup] [--dry-run]
```

**Options:**
- `--backup` - Create backup before applying changes (default)
- `--dry-run` - Show what would be changed without applying

**Output:**
- Console output showing each change
- Backup files in `/backups/YYYYMMDD-HHMMSS/`

### Rollback Command

```bash
./scripts/rollback.sh [backup-timestamp]
```

**Example:**
```bash
./scripts/rollback.sh 20251102-143022
```

---

## Ansible Usage

### Using Playbooks

```bash
# Test connection
ansible -i ansible/inventory/hosts.yml all -m ping

# Apply Level 1 hardening
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cis-level1.yml

# Apply Level 2 hardening
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cis-level2.yml

# Dry run
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cis-level1.yml --check
```

### Inventory Configuration

Edit `ansible/inventory/hosts.yml` to add target hosts:

```yaml
all:
  children:
    production:
      hosts:
        server1:
          ansible_host: 192.168.1.10
          ansible_user: admin
```

---

## Docker Testing

### Start Test Environment

```bash
cd docker/test-environment
./start-test.sh
```

### Run Tests in Container

```bash
# Access container
docker exec -it sec-levels-test-68 bash

# Inside container - run audit
sudo /scripts/audit.sh level1

# Apply hardening
sudo /scripts/harden.sh level1

# Verify
sudo /scripts/audit.sh level1
```

### Clean Up

```bash
./cleanup.sh
```

---

## VM Testing

See [vm-testing/README.md](../vm-testing/README.md) for VM testing procedures.

---

## Configuration

### Custom Profiles

Create custom profile at `config/profiles/custom.yml`:

```yaml
profile:
  name: "My Custom Profile"
  level: custom

controls:
  - id: "1.1.1"
    enabled: true
  # ... additional controls
```

### Configuration Templates

Modify templates in `config/templates/` to customize:
- SSH configuration (`sshd_config.j2`)
- Kernel parameters (`sysctl.conf.j2`)
- Firewall rules (`ufw-rules.j2`)

---

## Reports

### Report Formats

- **Text:** Human-readable audit results
- **JSON:** Machine-parseable results (coming soon)
- **HTML:** Web-viewable report (coming soon)

### Report Location

All reports are saved to `/reports/` with timestamp:
```
reports/
├── audit-20251102-140000.txt
├── audit-20251102-150000.txt
└── harden-20251102-150030.log
```

---

## Troubleshooting

### Common Issues

**Permission Denied:**
```bash
# Ensure scripts are executable
chmod +x scripts/*.sh
```

**Backup Not Found:**
```bash
# List available backups
ls -la backups/
```

**Docker Container Won't Start:**
```bash
# Check Docker status
docker ps -a

# View logs
docker logs sec-levels-test-68
```

---

## Best Practices

1. **Always run audit first** to understand current state
2. **Review audit report** before applying hardening
3. **Test in Docker/VM** before production
4. **Keep backups** of original configurations
5. **Document custom changes** in custom profile
6. **Verify after hardening** with another audit

---

## Support

For issues and questions:
- Check [ERRORS.md](ERRORS.md) for known issues
- Review [DEVELOPMENT.md](DEVELOPMENT.md) for implementation details
- Check [CIS-MAPPING.md](CIS-MAPPING.md) for control details

---

_Note: This guide will be updated as features are implemented._
