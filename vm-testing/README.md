# VM Testing Guide - sec-levels

## Purpose

Test sec-levels hardening on a full Ubuntu 24.04 LTS virtual machine with latest kernel to validate compatibility beyond Docker containers.

## Why VM Testing?

Docker containers have limitations:
- Limited systemd functionality
- Cannot test kernel module loading
- Cannot test boot parameters
- Cannot test full disk encryption
- Cannot test GRUB hardening

VM testing validates:
- Complete system boot after hardening
- All systemd services
- Kernel module restrictions
- Boot parameter enforcement
- Full disk scenarios

## Prerequisites

### Hypervisor Options

Choose one:
- **VirtualBox** (easiest, cross-platform)
- **VMware Workstation/Fusion** (better performance)
- **KVM/QEMU** (best for Linux hosts)
- **Hyper-V** (Windows hosts)

### System Requirements

- **CPU:** 2 cores minimum
- **RAM:** 2GB minimum (4GB recommended)
- **Disk:** 20GB minimum
- **ISO:** Ubuntu 24.04 LTS Server (download from ubuntu.com)

## VM Setup Steps

### 1. Create VM

#### VirtualBox Example
```bash
VBoxManage createvm --name "sec-levels-test" --register
VBoxManage modifyvm "sec-levels-test" --memory 2048 --cpus 2
VBoxManage createhd --filename "sec-levels-test.vdi" --size 20480
VBoxManage storagectl "sec-levels-test" --name "SATA" --add sata
VBoxManage storageattach "sec-levels-test" --storagectl "SATA" --port 0 --type hdd --medium "sec-levels-test.vdi"
```

#### KVM/QEMU Example
```bash
virt-install \
  --name sec-levels-test \
  --ram 2048 \
  --disk size=20 \
  --vcpus 2 \
  --os-variant ubuntu24.04 \
  --cdrom /path/to/ubuntu-24.04-server-amd64.iso \
  --network bridge=virbr0
```

### 2. Install Ubuntu 24.04

**Installation Options:**
- Choose "Ubuntu Server (minimized)"
- Enable SSH server during installation
- Create user: `testuser` (password: `testpass`)
- Use entire disk (no LVM for simplicity)
- Install OpenSSH server

**Post-Installation:**
```bash
# Login to VM console
# Update system
sudo apt update && sudo apt upgrade -y
sudo reboot

# Verify kernel version
uname -r  # Should show 6.8.x or later
```

### 3. Configure SSH Access

From VM:
```bash
# Get VM IP address
ip addr show

# Ensure SSH is running
sudo systemctl status ssh
```

From host:
```bash
# SSH to VM (replace IP)
ssh testuser@192.168.122.10
```

### 4. Install Prerequisites

```bash
# Inside VM
sudo apt install -y git python3 python3-pip

# Clone sec-levels (adjust path as needed)
git clone /path/to/sec-levels
cd sec-levels

# Make scripts executable
chmod +x scripts/*.sh
chmod +x scripts/lib/*.sh
```

### 5. Run Initial Audit

```bash
# Create reports directory
mkdir -p reports

# Run baseline audit
sudo ./scripts/audit.sh level1 > reports/pre-hardening-audit.txt

# Review results
less reports/pre-hardening-audit.txt
```

### 6. Apply Hardening

```bash
# Apply Level 1 hardening
sudo ./scripts/harden.sh level1

# System may need reboot for some changes
sudo reboot
```

### 7. Verify Hardening

```bash
# After reboot, verify SSH still works
ssh testuser@192.168.122.10

# Run post-hardening audit
sudo ./scripts/audit.sh level1 > reports/post-hardening-audit.txt

# Compare results
diff reports/pre-hardening-audit.txt reports/post-hardening-audit.txt
```

### 8. Validate System Functionality

```bash
# Check critical services
sudo systemctl status ssh
sudo systemctl status auditd
sudo systemctl status ufw

# Verify network connectivity
ping -c 4 8.8.8.8

# Check user can still sudo
sudo whoami

# Verify AppArmor
sudo aa-status

# Check firewall
sudo ufw status
```

## Testing Checklist

After hardening, verify:

- [ ] VM boots successfully
- [ ] SSH access works
- [ ] User can sudo
- [ ] Network connectivity functional
- [ ] Critical services running (ssh, auditd, ufw)
- [ ] AppArmor profiles loaded
- [ ] Firewall configured
- [ ] Audit logging active
- [ ] System logs show no critical errors
- [ ] Can run applications normally

## Troubleshooting

### VM Won't Boot After Hardening

1. Boot from installation ISO in rescue mode
2. Mount root filesystem
3. Run rollback script
4. Reboot

### SSH Access Lost

1. Access via VM console
2. Check SSH service: `sudo systemctl status ssh`
3. Check firewall: `sudo ufw status`
4. Review SSH config: `sudo cat /etc/ssh/sshd_config`
5. Check logs: `sudo journalctl -u ssh`

### Services Failing

```bash
# Check service status
sudo systemctl status <service-name>

# View logs
sudo journalctl -u <service-name> -n 50

# Check AppArmor denials
sudo dmesg | grep -i apparmor
```

## Rollback Procedure

If hardening causes issues:

```bash
# Run rollback script with backup timestamp
sudo ./scripts/rollback.sh <timestamp>

# Or manually restore from backup
sudo cp -r /backups/<timestamp>/* /

# Reboot
sudo reboot
```

## Snapshots (Recommended)

Before hardening, create VM snapshot:

**VirtualBox:**
```bash
VBoxManage snapshot "sec-levels-test" take "pre-hardening"
```

**KVM:**
```bash
virsh snapshot-create-as sec-levels-test pre-hardening
```

Restore if needed:
```bash
# VirtualBox
VBoxManage snapshot "sec-levels-test" restore "pre-hardening"

# KVM
virsh snapshot-revert sec-levels-test pre-hardening
```

## Kernel Version Verification

```bash
# Check current kernel
uname -r

# Check available kernels
dpkg --list | grep linux-image

# Check kernel boot parameters
cat /proc/cmdline

# Check sysctl parameters
sudo sysctl -a | grep -E 'kernel|net\.ipv4|net\.ipv6'
```

## Performance Testing

After hardening, validate performance:

```bash
# CPU test
stress-ng --cpu 2 --timeout 60s

# Memory test
stress-ng --vm 1 --vm-bytes 1G --timeout 60s

# Disk test
dd if=/dev/zero of=/tmp/testfile bs=1M count=1024
```

## Advanced Testing

### Test Kernel Module Restrictions

```bash
# Try loading restricted module
sudo modprobe <blacklisted-module>
# Should fail if properly configured
```

### Test Audit Rules

```bash
# Generate audit events
touch /tmp/audit-test
rm /tmp/audit-test

# Check audit logs
sudo ausearch -f /tmp/audit-test
```

### Test File Permissions

```bash
# Check sensitive file permissions
ls -la /etc/passwd /etc/shadow /etc/ssh/sshd_config
```

## Cleanup

When testing is complete:

**VirtualBox:**
```bash
VBoxManage controlvm "sec-levels-test" poweroff
VBoxManage unregistervm "sec-levels-test" --delete
```

**KVM:**
```bash
virsh destroy sec-levels-test
virsh undefine sec-levels-test --remove-all-storage
```

## Next Steps

After successful VM testing:
1. Document any issues found in ERRORS.md
2. Update hardening scripts if needed
3. Test on production-like systems
4. Create deployment runbook

## Notes

- Always test in isolated VM first
- Never test directly on production systems
- Keep backups of original configurations
- Document all issues and workarounds
- Verify rollback works before production use

---

_Detailed testing results will be added after VM validation phase._
