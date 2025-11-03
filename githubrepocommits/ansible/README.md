# Ansible CIS Hardening Automation

Complete Ansible automation for CIS Ubuntu 24.04 LTS hardening (Levels 1 and 2).

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Roles](#roles)
- [Playbooks](#playbooks)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

This Ansible automation implements CIS Ubuntu 24.04 LTS Benchmark v1.0.0 hardening controls:

**CIS Level 1 Coverage:**
- SSH hardening (Section 5.1)
- UFW firewall configuration (Section 4)
- Kernel parameter hardening (Sections 1.5, 3.3)
- Filesystem permissions (Section 7)
- Audit logging with auditd (Section 6.2)

**CIS Level 2 Additional Controls:**
- AppArmor mandatory access control (Section 1.3)
- Enhanced kernel restrictions
- Stricter security policies

## Prerequisites

**Control Node (where Ansible runs):**
- Ansible 2.9+ (2.15+ recommended)
- Python 3.8+
- SSH access to target hosts

**Target Hosts:**
- Ubuntu 24.04 LTS
- Python 3 installed
- sudo access configured
- SSH server running

## Installation

### Install Ansible on Control Node

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install ansible -y
```

**Using pip:**
```bash
pip3 install ansible
```

**Verify installation:**
```bash
ansible --version
```

## Quick Start

### 1. Configure Inventory

Edit `inventory/hosts.yml`:

```yaml
all:
  children:
    production:
      hosts:
        server1:
          ansible_host: 192.168.1.10
          ansible_user: admin
```

### 2. Test Connectivity

```bash
cd ~/sec-levels/ansible
ansible all -m ping
```

### 3. Run CIS Level 1 Hardening

**Dry run (check mode):**
```bash
ansible-playbook playbooks/cis-level1.yml --check --diff
```

**Apply hardening:**
```bash
ansible-playbook playbooks/cis-level1.yml
```

## Roles

### ssh-hardening

Hardens SSH configuration according to CIS 5.1.

**Controls:**
- Disable root login
- Enforce key-based authentication
- Strong ciphers, MACs, and key exchange algorithms
- Session timeouts
- Login banners

**Variables:** (see `roles/ssh-hardening/defaults/main.yml`)
```yaml
ssh_permit_root_login: "no"
ssh_password_authentication: "no"
ssh_max_auth_tries: 3
ssh_client_alive_interval: 300
```

### firewall

Configures UFW firewall with default-deny policies.

**Controls:**
- Install and enable UFW
- Default deny incoming/outgoing
- Allow SSH (port 22)
- Logging enabled

**Variables:**
```yaml
ufw_additional_rules:
  - { port: '80', proto: 'tcp', comment: 'HTTP' }
  - { port: '443', proto: 'tcp', comment: 'HTTPS' }
```

### kernel-hardening

Applies kernel security parameters via sysctl.

**Controls:**
- Disable IP forwarding
- Enable SYN cookies
- Disable ICMP redirects
- ASLR enabled (randomize_va_space=2)
- Ptrace restrictions
- Disable uncommon filesystems
- Disable network protocols (DCCP, SCTP, RDS, TIPC)

**Variables:** (see `roles/kernel-hardening/defaults/main.yml`)
```yaml
kernel_kexec_disabled: 0      # Set to 1 for Level 2
kernel_bpf_jit_harden: 2
```

### filesystem

Configures filesystem permissions and mount options.

**Controls:**
- Restrictive permissions on /etc/passwd, /etc/shadow, etc.
- GRUB configuration permissions
- Find world-writable files (audit only)
- Sticky bit on world-writable directories

**Variables:**
```yaml
configure_tmp_partition: false  # Set to true if /tmp is separate partition
```

### audit-logging

Configures auditd with comprehensive audit rules.

**Controls:**
- 20+ audit rules covering:
  - Time changes
  - User/group modifications
  - Network configuration
  - Login/logout events
  - File permission changes
  - Privileged command execution
  - Kernel module loading

**Variables:**
```yaml
auditd_max_log_file: 8
auditd_space_left_action: email
auditd_max_log_file_action: keep_logs
```

## Playbooks

### cis-level1.yml

Applies CIS Level 1 Server hardening using individual Ansible roles.

**Usage:**
```bash
# Full hardening
ansible-playbook playbooks/cis-level1.yml

# Specific role only
ansible-playbook playbooks/cis-level1.yml --tags ssh

# Skip specific role
ansible-playbook playbooks/cis-level1.yml --skip-tags firewall

# Limit to specific host
ansible-playbook playbooks/cis-level1.yml --limit server1
```

### cis-level1-v3.yml ⭐ NEW

Applies **v3.0 enhanced CIS Level 1 hardening** using the consolidated hardening script.

**Target Compliance**: 73-75% CIS Level 1 Workstation

**v3.0 Enhancements:**
- Package management (remove insecure clients: ftp, telnet, ldap-utils)
- AIDE file integrity monitoring
- Time synchronization (systemd-timesyncd)
- GNOME desktop hardening (screen lock, banner, autorun)
- Access control (cron.allow, at.allow)
- File permissions (cron dirs, sticky bit)
- Sudo security (pty, logging, re-authentication)
- Enhanced security tools: fail2ban, ClamAV, AIDE, rkhunter, Lynis, Timeshift

**Usage:**
```bash
# Full v3.0 hardening (remote hosts)
ansible-playbook playbooks/cis-level1-v3.yml

# Dry-run mode (test without changes)
ansible-playbook playbooks/cis-level1-v3.yml -e "dry_run=true"

# Limit to specific hosts
ansible-playbook playbooks/cis-level1-v3.yml --limit production

# Skip reboot reminder
ansible-playbook playbooks/cis-level1-v3.yml --skip-tags always
```

**Expected Results:**
- CIS Level 1: 73-75% compliance
- Lynis Hardening Index: 73/100
- All security tools installed and configured

### local-hardening.yml ⭐ NEW

Applies v3.0 CIS hardening to **localhost** without requiring inventory configuration.

**Perfect for:**
- Personal workstations
- Single-system hardening
- Quick local deployment

**Usage:**
```bash
# Normal execution (interactive prompts)
sudo ansible-playbook playbooks/local-hardening.yml

# Dry-run mode (test without changes)
sudo ansible-playbook playbooks/local-hardening.yml -e "dry_run=true"

# Force mode (bypass kernel compatibility prompts)
sudo ansible-playbook playbooks/local-hardening.yml -e "force_mode=true"

# With automatic reboot after hardening
sudo ansible-playbook playbooks/local-hardening.yml --tags reboot

# Both dry-run and force
sudo ansible-playbook playbooks/local-hardening.yml -e "dry_run=true force_mode=true"
```

**Features:**
- No inventory configuration required
- Interactive confirmation prompts
- Automatic kernel compatibility detection
- OEM kernel support
- Force mode for automated deployment
- Optional reboot scheduling
- Comprehensive warnings and next steps

**System Requirements:**
- 4GB+ RAM (8GB+ recommended for ClamAV)
- 10GB+ free disk space
- SSD recommended (for AIDE/ClamAV performance)

### cis-level2.yml

Applies CIS Level 2 Server hardening (includes all Level 1 controls + additional).

**Additional Level 2 Controls:**
- AppArmor in enforce mode
- kexec disabled

**Usage:**
```bash
ansible-playbook playbooks/cis-level2.yml
```

**WARNING:** Level 2 is more restrictive. Ensure you have console access before applying.

## Configuration

### ansible.cfg

Configuration file location: `~/sec-levels/ansible/ansible.cfg`

**Key settings:**
- `inventory`: Default inventory file
- `gathering`: Smart fact gathering
- `fact_caching`: JSON file caching (3600s)
- `become`: Privilege escalation enabled

### Inventory Structure

```yaml
all:
  children:
    test_environments:
      hosts:
        docker-kernel68:
          ansible_host: sec-levels-test-68
          ansible_connection: docker
          ansible_user: secuser

    production:
      hosts:
        prod-server1:
          ansible_host: 192.168.1.10
          ansible_user: admin
          # Optional: override default variables
          ssh_max_auth_tries: 5
```

## Usage Examples

### Example 1: Harden Multiple Servers

```bash
# Edit inventory
vim inventory/hosts.yml

# Add servers to production group
production:
  hosts:
    web1:
      ansible_host: 10.0.1.10
    web2:
      ansible_host: 10.0.1.11
    db1:
      ansible_host: 10.0.2.10

# Run on all production servers
ansible-playbook playbooks/cis-level1.yml --limit production
```

### Example 2: Custom SSH Configuration

Create `group_vars/production.yml`:

```yaml
# Custom SSH settings for production
ssh_permit_root_login: "no"
ssh_password_authentication: "no"
ssh_max_auth_tries: 3
ssh_client_alive_interval: 300

# Allow additional firewall ports
ufw_additional_rules:
  - { port: '80', proto: 'tcp', comment: 'HTTP' }
  - { port: '443', proto: 'tcp', comment: 'HTTPS' }
  - { port: '3306', proto: 'tcp', comment: 'MySQL' }
```

Run playbook:
```bash
ansible-playbook playbooks/cis-level1.yml --limit production
```

### Example 3: Kernel Hardening Only

```bash
# Apply only kernel hardening
ansible-playbook playbooks/cis-level1.yml --tags kernel

# Or run role directly
ansible-playbook -i inventory/hosts.yml roles/kernel-hardening/tasks/main.yml
```

### Example 4: Dry Run Before Production

```bash
# Check what will change (no actual changes)
ansible-playbook playbooks/cis-level1.yml --check --diff

# Show task execution times
ANSIBLE_CALLBACK_WHITELIST=profile_tasks ansible-playbook playbooks/cis-level1.yml
```

## Testing

### Docker Test Environment

The project includes Docker test containers for safe testing:

**Start test containers:**
```bash
cd ~/sec-levels
docker compose -f docker/docker-compose.yml up -d
```

**Test in Docker container:**
```bash
ansible-playbook playbooks/cis-level1.yml --limit docker-kernel68 --check
```

**Note:** Some controls don't apply in Docker (firewall, kernel modules, auditd). The playbooks automatically detect Docker environments and skip non-applicable tasks.

### VM Testing

For full testing, use a VM:

```bash
# Setup test VM (requires libvirt/KVM)
cd ~/sec-levels/vm-testing
./vm-setup.sh

# Add VM to inventory
vim ../ansible/inventory/hosts.yml
# Add:
#   test-vm:
#     ansible_host: 192.168.122.100
#     ansible_user: ubuntu

# Test hardening
cd ../ansible
ansible-playbook playbooks/cis-level1.yml --limit test-vm --check
```

## Troubleshooting

### SSH Connection Issues After Hardening

**Problem:** Cannot SSH after applying hardening.

**Solution:**
1. Check if SSH keys are configured:
   ```bash
   ssh-copy-id user@server
   ```

2. Temporarily enable password auth for testing:
   ```yaml
   # In playbook or group_vars
   ssh_password_authentication: "yes"
   ```

3. Always test new SSH session before closing existing one.

### Firewall Blocks Services

**Problem:** UFW blocks required services.

**Solution:**
Add firewall rules before running playbook:

```yaml
# In group_vars or inventory
ufw_additional_rules:
  - { port: '80', proto: 'tcp', comment: 'HTTP' }
  - { port: '443', proto: 'tcp', comment: 'HTTPS' }
```

### Auditd Not Starting

**Problem:** auditd fails to start in containers.

**Solution:**
This is expected. Auditd requires privileged mode in Docker or host-level installation. The playbooks automatically skip auditd in Docker environments.

### Syntax Validation Errors

**Problem:** `ansible-playbook --syntax-check` fails.

**Solution:**
1. Ensure Ansible version 2.9+:
   ```bash
   ansible --version
   ```

2. Check YAML syntax:
   ```bash
   yamllint playbooks/cis-level1.yml
   ```

3. Validate specific role:
   ```bash
   ansible-playbook playbooks/cis-level1.yml --syntax-check
   ```

### Variables Not Applied

**Problem:** Custom variables not taking effect.

**Solution:**
Variable precedence (highest to lowest):
1. Extra vars (`-e` on command line)
2. Host vars
3. Group vars
4. Role defaults

Override in playbook:
```bash
ansible-playbook playbooks/cis-level1.yml -e "ssh_max_auth_tries=5"
```

## Tags Reference

**Role Tags:**
- `ssh`: SSH hardening
- `firewall`: UFW configuration
- `kernel`: Kernel parameters
- `filesystem`: File permissions
- `audit`: Audit logging

**Level Tags:**
- `level1`: Level 1 controls
- `level2`: Level 2 controls

**Examples:**
```bash
# Run only SSH and firewall
ansible-playbook playbooks/cis-level1.yml --tags ssh,firewall

# Skip audit logging
ansible-playbook playbooks/cis-level1.yml --skip-tags audit

# Run only Level 2 specific tasks
ansible-playbook playbooks/cis-level2.yml --tags level2
```

## Backups

All playbooks automatically create backups before making changes:

**Backup location:** `/root/sec-levels-backups/`

**Restore from backup:**
```bash
# List backups
ls -lh /root/sec-levels-backups/

# Restore SSH config
tar -xzf /root/sec-levels-backups/pre-hardening-1234567890.tar.gz -C /
systemctl restart ssh
```

## Additional Resources

- **CIS Benchmark:** https://www.cisecurity.org/benchmark/ubuntu_linux
- **MVladislav Reference:** https://github.com/MVladislav/ansible-cis-ubuntu-2404
- **Ansible Docs:** https://docs.ansible.com/
- **sec-levels Project:** ~/sec-levels/

## Contributing

When modifying roles:

1. Update defaults in `roles/<role>/defaults/main.yml`
2. Document variables in this README
3. Test in Docker first: `--limit docker-kernel68 --check`
4. Test in VM before production
5. Update role documentation

## License

See project LICENSE file.
