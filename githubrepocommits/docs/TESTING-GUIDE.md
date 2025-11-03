# Testing Guide: sec-levels CIS Hardening

**Version:** 3.0
**Last Updated:** November 2025
**Target Platform:** Ubuntu 24.04 LTS

---

## Table of Contents

1. [Overview](#1-overview)
2. [VM Testing Environment Setup](#2-vm-testing-environment-setup)
3. [Docker Testing Environment](#3-docker-testing-environment)
4. [Test Methodology](#4-test-methodology)
5. [Test Scenarios Covered](#5-test-scenarios-covered)
6. [Expected Results](#6-expected-results)
7. [Troubleshooting](#7-troubleshooting)
8. [Key Findings & Lessons Learned](#8-key-findings--lessons-learned)

---

## 1. Overview

### 1.1 Purpose of Testing

The sec-levels testing framework validates CIS hardening scripts on Ubuntu 24.04 LTS systems to ensure:

- **Compliance improvement**: Measurable increase in CIS benchmark adherence
- **System stability**: Services remain operational after hardening
- **Rollback capability**: Configuration changes are reversible
- **Cross-environment compatibility**: Scripts work in both VM and container environments

### 1.2 Testing Environments Available

#### VM Testing (KVM/libvirt)
**Use when testing:**
- Full system hardening (kernel parameters, boot configurations)
- Systemd service modifications
- Kernel module restrictions
- Complete disk scenarios
- GRUB bootloader changes
- AppArmor profiles requiring reboot

**Advantages:**
- Complete OS environment
- Supports snapshots for instant rollback
- Tests system boot after hardening
- Validates kernel-level security controls

#### Docker Testing
**Use when testing:**
- Script functionality without system changes
- Package installation workflows
- Configuration file syntax
- Rapid iteration during development

**Limitations:**
- Cannot test kernel parameters (shares host kernel)
- Limited systemd functionality
- No boot parameter validation
- Cannot test full disk encryption

### 1.3 What Gets Validated

All tests measure:

1. **CIS Compliance Score** (OpenSCAP): Percentage of passing controls
2. **Lynis Hardening Index**: 0-100 security posture score
3. **Service Availability**: SSH, UFW, AppArmor, auditd status
4. **Network Connectivity**: Internet access, DNS resolution
5. **System Functionality**: User authentication, sudo access
6. **Rollback Success**: Restoration to pre-hardening state

---

## 2. VM Testing Environment Setup

### 2.1 Prerequisites

#### System Requirements
- **CPU**: 2+ cores (8 recommended for faster testing)
- **RAM**: 4GB minimum (16GB recommended)
- **Disk**: 50GB free space for VM
- **Host OS**: Ubuntu 24.04 LTS (tested platform)
- **Virtualization**: AMD-V or Intel VT-x enabled in BIOS

#### Hypervisor Installation (KVM/libvirt)

```bash
# Install virtualization packages
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager \
                     virtinst virtiofsd bridge-utils

# Add user to libvirt group
sudo usermod -aG libvirt,kvm $USER

# CRITICAL: Logout and login to activate group membership
gnome-session-quit --logout
```

**After login, verify:**
```bash
# Check group membership
groups | grep -E 'libvirt|kvm'

# Test libvirt access (should work without sudo)
virsh list --all

# Check libvirtd service
systemctl status libvirtd
```

### 2.2 Network Configuration

KVM/libvirt automatically creates a NAT network:

- **Interface**: virbr0
- **Network**: 192.168.122.0/24
- **DHCP Range**: 192.168.122.2-254
- **DNS**: Provided by dnsmasq
- **Isolation**: VMs isolated from external network, can access internet

**Verify network:**
```bash
virsh net-list --all
# Expected: "default" network active

virsh net-info default
# Expected: Active, Autostart enabled
```

### 2.3 VM Creation

#### Automated Method (Recommended)

Download Ubuntu ISO:
```bash
cd ~/Downloads
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso
```

Create VM using virt-manager GUI:
```bash
virt-manager &
# File → New Virtual Machine
# Select: Local install media (ISO)
# Choose: ubuntu-24.04-desktop-amd64.iso
# OS: Ubuntu 24.04
# RAM: 16384 MB (16GB)
# CPUs: 8
# Disk: 50GB
# Name: ubuntu-cis-hardening-test
# Network: Virtual network 'default' (NAT)
```

#### CLI Method (Advanced)

```bash
virt-install \
  --name ubuntu-cis-hardening-test \
  --ram 16384 \
  --vcpus 8 \
  --disk size=50,format=qcow2 \
  --os-variant ubuntu24.04 \
  --cdrom ~/Downloads/ubuntu-24.04-desktop-amd64.iso \
  --network network=default \
  --graphics vnc,listen=0.0.0.0
```

### 2.4 Ubuntu Installation

**Installation Options:**
1. **Language**: English (or your preference)
2. **Keyboard**: English (US) or your layout
3. **Installation Type**: **Minimal installation** ✅
   - Reduces bloat for testing
   - Includes only browser and basic utilities
4. **Updates**: Install third-party software (graphics drivers)
5. **Disk Setup**: Erase disk and install (safe - VM disk only)
6. **Time Zone**: Your timezone
7. **User Account**:
   - Name: CIS Test User
   - Computer: ubuntu-cis-hardening-vm
   - Username: `testuser`
   - Password: (choose secure password)
   - Login: Require password (no auto-login)

**Post-Installation:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Verify kernel version
uname -r
# Expected: 6.8.0-XX-generic (GA kernel)

# Install testing tools
sudo apt install -y openscap-scanner scap-security-guide \
                    openssh-server git

# Enable SSH
sudo systemctl enable --now ssh
```

### 2.5 Shared Folder Setup (virtiofs)

**Why virtiofs:**
- 3-4x faster than virtio-9p (40MB/s vs 9MB/s)
- Better POSIX compliance
- Native kernel support (6.8+)
- No guest drivers needed

**Configure in virt-manager:**
1. Select VM → Hardware Details → Add Hardware
2. Filesystem:
   - **Type**: virtiofs
   - **Source path**: `/path/to/sec-levels` (host path)
   - **Target path**: `sec-levels-share` (mount tag)
3. Apply changes

**Inside VM:**
```bash
# Create mount point
sudo mkdir -p /mnt/sec-levels

# Mount shared folder
sudo mount -t virtiofs sec-levels-share /mnt/sec-levels

# Verify
ls /mnt/sec-levels
# Expected: ansible/ config/ docker/ scripts/ tests/

# Make persistent (auto-mount on boot)
echo "sec-levels-share /mnt/sec-levels virtiofs defaults 0 0" | \
    sudo tee -a /etc/fstab
```

### 2.6 SSH Access from Host

```bash
# Get VM IP address
virsh net-dhcp-leases default

# Connect via SSH (replace IP)
ssh testuser@192.168.122.XXX

# Optional: Set up passwordless SSH
ssh-keygen -t ed25519 -C "cis-testing"
ssh-copy-id testuser@192.168.122.XXX
```

### 2.7 Snapshot Strategy

**Create snapshots before major changes:**

```bash
# Baseline: Fresh installation
virsh snapshot-create-as ubuntu-cis-hardening-test \
  baseline-clean \
  "Fresh Ubuntu 24.04, fully updated"

# Pre-hardening: Before applying scripts
virsh snapshot-create-as ubuntu-cis-hardening-test \
  pre-hardening \
  "Baseline captured, ready for CIS hardening"

# Post-hardening Level 1
virsh snapshot-create-as ubuntu-cis-hardening-test \
  hardened-level1 \
  "CIS Level 1 workstation hardening applied"
```

**Revert to snapshot:**
```bash
virsh snapshot-revert ubuntu-cis-hardening-test baseline-clean
```

**List snapshots:**
```bash
virsh snapshot-list ubuntu-cis-hardening-test
```

---

## 3. Docker Testing Environment

### 3.1 Docker Setup

```bash
# Install Docker (if not already installed)
sudo apt install -y docker.io
sudo usermod -aG docker $USER
# Logout/login to activate group

# Verify Docker
docker --version
docker run hello-world
```

### 3.2 Test Container Usage

**Build test container:**
```bash
cd sec-levels/docker
docker build -t sec-levels-test .
```

**Run interactive container:**
```bash
docker run -it --rm \
  --privileged \
  --cap-add=ALL \
  -v $(pwd):/workspace \
  sec-levels-test bash
```

**Inside container:**
```bash
cd /workspace
./scripts/audit.sh level1
./scripts/harden.sh level1 --dry-run
```

### 3.3 Docker Testing Limitations

⚠️ **Cannot test in Docker:**
- Kernel parameter changes (sysctl)
- Kernel module restrictions
- Boot parameters (GRUB)
- Full systemd functionality
- AppArmor enforcement
- Disk partitioning

✅ **Can test in Docker:**
- Package installation
- Configuration file syntax
- Service configuration files
- Script logic and error handling
- Backup/restore functionality

---

## 4. Test Methodology

### 4.1 Baseline Audit Process

**1. Prepare test environment:**
```bash
# Via SSH or shared folder
cd /mnt/sec-levels

# Ensure scripts are executable
chmod +x scripts/*.sh
```

**2. Run baseline audit:**
```bash
# Create reports directory
mkdir -p ~/reports

# CIS Level 1 baseline
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_workstation \
  --results ~/reports/baseline-arf.xml \
  --report ~/reports/baseline-report.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Lynis baseline
sudo lynis audit system --quick --quiet > ~/reports/lynis-baseline.log
```

**3. Document baseline scores:**
- Note CIS compliance percentage
- Record number of pass/fail controls
- Save Lynis hardening index
- Screenshot compliance reports

### 4.2 Hardening Application

**1. Create configuration backup:**
```bash
# sec-levels scripts automatically create backups
# Located in: /var/backups/sec-levels/<timestamp>/
```

**2. Apply hardening (Level 1):**
```bash
cd /mnt/sec-levels
sudo ./scripts/harden.sh level1

# Expected output:
# - Filesystem hardening applied
# - Kernel parameters configured
# - Services disabled/enabled
# - UFW firewall configured
# - SSH hardened
# - Security tools installed
# - Backup created
```

**3. System reboot (if required):**
```bash
# Some kernel parameters require reboot
sudo reboot
```

**4. Verify SSH access after reboot:**
```bash
# From host
ssh testuser@192.168.122.XXX
```

### 4.3 Post-Hardening Validation

**1. Re-run CIS audit:**
```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_workstation \
  --results ~/reports/hardened-arf.xml \
  --report ~/reports/hardened-report.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
```

**2. Re-run Lynis audit:**
```bash
sudo lynis audit system > ~/reports/lynis-hardened.log
```

**3. Functional validation:**
```bash
# Check critical services
sudo systemctl status ssh
sudo systemctl status ufw
sudo systemctl status fail2ban
sudo systemctl status clamav-daemon

# Test network connectivity
ping -c 4 8.8.8.8
curl -I https://google.com

# Verify sudo access
sudo whoami

# Check AppArmor
sudo aa-status

# Verify firewall
sudo ufw status verbose
```

### 4.4 Comparison and Reporting

**Extract compliance scores:**
```bash
# From OpenSCAP XML results
grep -oP 'score>.*?<' ~/reports/baseline-arf.xml
grep -oP 'score>.*?<' ~/reports/hardened-arf.xml

# Calculate improvement
# Baseline: XX.XX% → Hardened: YY.YY% = +Z.ZZ% improvement
```

**Generate before/after comparison:**
- Create table comparing scores
- List controls changed from fail→pass
- Document any new failures
- Note system functionality impact

---

## 5. Test Scenarios Covered

### 5.1 CIS Level 1 Workstation Testing

**Scope:** Essential security controls for workstations

**Controls tested (~240):**
- Filesystem hardening (unused filesystems disabled)
- Kernel network parameters (IP forwarding, redirects)
- Service management (unnecessary services disabled)
- Firewall configuration (UFW)
- AppArmor enforcement
- SSH hardening (ciphers, MACs, KEX)
- File permissions (sensitive files)
- User account policies

**Expected baseline:** 60-70% compliance (fresh Ubuntu 24.04)
**Expected after hardening:** 73-78% compliance

### 5.2 CIS Level 2 Workstation Testing

**Scope:** Level 1 + additional restrictive controls

**Additional controls (~150):**
- Audit logging (auditd rules)
- Advanced kernel hardening
- Stricter network controls
- Additional file permissions
- Enhanced PAM policies
- Process accounting

**Expected baseline:** 45-55% compliance
**Expected after hardening:** 50-60% compliance

### 5.3 Enhanced Security Tools Validation

**Tools installed and validated:**

1. **fail2ban** (v1.0.2)
   - SSH intrusion prevention
   - 3 failed attempts = 2-hour ban
   - Status: `sudo fail2ban-client status sshd`

2. **ClamAV** (v1.4.3)
   - Daily malware scans (6:25 AM)
   - 8.7M virus signatures
   - Logs: `/var/log/clamav/daily-scan.log`

3. **rkhunter** (v1.4.6)
   - Weekly rootkit scans (Sundays)
   - Logs: `/var/log/rkhunter-scan.log`

4. **AIDE** (Advanced Intrusion Detection)
   - File integrity monitoring
   - Database initialization: 6-20 minutes
   - Detects unauthorized file modifications

5. **Lynis** (v3.0.9)
   - Security auditing
   - Hardening index: 72-73/100

6. **Timeshift** (v24.01.1)
   - System snapshots
   - Disaster recovery capability

**Validation tests:**
```bash
# Verify all services running
sudo systemctl status fail2ban clamav-daemon clamav-freshclam

# Check fail2ban protecting SSH
sudo fail2ban-client status sshd

# Verify ClamAV definitions updated
sudo freshclam --version

# Check AIDE database
sudo aide --check

# Run Lynis audit
sudo lynis audit system
```

### 5.4 Kernel Compatibility Testing

**Kernels tested:**

| Kernel Version | Type | CIS Level 1 Score | Notes |
|----------------|------|-------------------|-------|
| 6.8.0-87-generic | GA | 67.34% | Stable, recommended |
| 6.14.0-34-generic | HWE | 67.34% | Identical compliance |
| 6.8.0-XX-oem | OEM | 67.34% (expected) | Hardware-specific |

**Key finding:** CIS compliance is kernel-independent for Ubuntu 24.04

**Kernel selection guidance:**
- **GA (6.8.x)**: Choose for maximum stability, production systems
- **HWE (6.11+)**: Choose for new hardware support (AMD 7000, NVIDIA 4000)
- **OEM**: Choose for specific vendor hardware optimization

---

## 6. Expected Results

### 6.1 CIS Compliance Benchmarks

**v3.0 Hardening Results (Latest):**

| Measurement | Baseline | v3.0 Result | Improvement |
|-------------|----------|-------------|-------------|
| **CIS Level 1 Workstation** | 64-67% | **73.51%** | **+6-9%** |
| **CIS Level 2 Workstation** | 45-50% | **50.67%** | **+1-5%** |
| **Rules Passing** | ~224 | **293** | **+69** |
| **Rules Failing** | ~131 | **106** | **-25** |

**Historical progression:**
- **Baseline (unhardened)**: 64.86%
- **v2.0 (enhanced hardening)**: 67.34% (+2.48%)
- **v3.0 (40+ additional controls)**: 73.51% (+6.17%)

### 6.2 Lynis Hardening Index Targets

**Scoring interpretation:**
- **0-49**: Poor security posture
- **50-69**: Fair security posture
- **70-79**: Good security posture ✅ (v3.0 achieves this)
- **80-89**: Very good security posture
- **90-100**: Excellent security posture

**v3.0 Results:**
- **Hardening Index**: 73/100
- **Rating**: Good
- **Recommendations**: ~40 suggestions for further hardening

### 6.3 Performance Metrics

**Resource overhead (idle):**
- **fail2ban**: 10-15 MB RAM
- **clamav-daemon**: 250-500 MB RAM
- **clamav-freshclam**: 10 MB RAM
- **Other security tools**: Minimal (run on-demand)
- **Total idle overhead**: ~270-525 MB RAM

**Disk usage:**
- ClamAV virus definitions: ~400 MB
- Security tool packages: ~50 MB
- AIDE database: ~10-30 MB
- Configuration backups: ~10 MB

**CPU impact:**
- Idle: Negligible
- ClamAV daily scans: Moderate (10-30 minutes)
- AIDE scans: Low-moderate (20-60 minutes)

**Recommended minimum specs:**
- **CPU**: 4+ cores
- **RAM**: 8GB+ (4GB minimum)
- **Disk**: 20GB+ free space
- **Storage type**: SSD preferred (I/O intensive scans)

### 6.4 Tool-Specific Validation

**Security tool validation checklist:**

```bash
# fail2ban
sudo fail2ban-client status
# Expected: sshd jail active

# ClamAV
sudo systemctl is-active clamav-daemon clamav-freshclam
# Expected: active (both)

freshclam --version
# Expected: 1.4.3+ with 8.7M+ signatures

# rkhunter
sudo rkhunter --versioncheck
# Expected: Version 1.4.6, database updated

# AIDE
sudo aide --check
# Expected: Database initialized, files verified

# Lynis
sudo lynis show version
# Expected: 3.0.9+

# Timeshift
sudo timeshift --list
# Expected: Snapshots created (if configured)
```

---

## 7. Troubleshooting

### 7.1 VM Won't Boot After Hardening

**Symptoms:**
- VM fails to boot
- Stuck at boot screen
- Kernel panic

**Diagnosis:**
```bash
# Boot from VM console (virt-manager)
# Press 'e' at GRUB menu
# Add to kernel line: systemd.unit=rescue.target
# Press Ctrl+X to boot
```

**Recovery:**
```bash
# Mount root filesystem
mount /dev/vda1 /mnt

# Restore from backup
cp -r /mnt/var/backups/sec-levels/<timestamp>/* /mnt/

# Or: Revert to snapshot
virsh snapshot-revert ubuntu-cis-hardening-test pre-hardening

# Reboot
reboot
```

### 7.2 SSH Access Lost

**Symptoms:**
- Cannot SSH to VM
- Connection refused
- Connection timeout

**Diagnosis:**
```bash
# Access VM console via virt-manager
# Login directly

# Check SSH service
sudo systemctl status ssh

# Check SSH listening
sudo ss -tlnp | grep :22

# Check firewall
sudo ufw status
sudo iptables -L -n | grep 22
```

**Common fixes:**
```bash
# Restart SSH
sudo systemctl restart ssh

# Allow SSH through firewall
sudo ufw allow 22/tcp

# Check SSH config syntax
sudo sshd -t

# Review SSH logs
sudo journalctl -u ssh -n 50

# Temporary: Disable SSH hardening
sudo cp /var/backups/sec-levels/<timestamp>/etc/ssh/sshd_config \
          /etc/ssh/sshd_config
sudo systemctl restart ssh
```

### 7.3 Services Failing to Start

**Symptoms:**
- systemd services failed
- Services in degraded state

**Diagnosis:**
```bash
# List failed services
systemctl --failed

# Check specific service
sudo systemctl status <service-name>

# View detailed logs
sudo journalctl -u <service-name> -n 100 --no-pager

# Check AppArmor denials
sudo dmesg | grep -i apparmor
sudo aa-status
```

**Common fixes:**
```bash
# Restart service
sudo systemctl restart <service-name>

# Disable AppArmor for service (temporary)
sudo aa-complain /etc/apparmor.d/<profile>

# Check service configuration
sudo <service> --test-config

# Restore service config from backup
sudo cp /var/backups/sec-levels/<timestamp>/etc/<service>/* \
          /etc/<service>/
sudo systemctl restart <service>
```

### 7.4 Network Connectivity Issues

**Symptoms:**
- Cannot ping external hosts
- DNS resolution failing
- No internet access

**Diagnosis:**
```bash
# Check network interfaces
ip addr show

# Check default route
ip route show

# Test connectivity
ping -c 4 8.8.8.8  # IP connectivity
ping -c 4 google.com  # DNS resolution

# Check DNS configuration
cat /etc/resolv.conf

# Check firewall rules
sudo ufw status verbose
sudo iptables -L -n -v
```

**Common fixes:**
```bash
# Restart networking
sudo systemctl restart NetworkManager

# Flush DNS cache
sudo systemd-resolve --flush-caches

# Temporarily disable UFW
sudo ufw disable
# Test connectivity
# Re-enable: sudo ufw enable

# Check kernel network parameters
sudo sysctl net.ipv4.ip_forward
sudo sysctl net.ipv4.conf.all.forwarding

# Restore network config from backup
sudo cp /var/backups/sec-levels/<timestamp>/etc/netplan/* \
          /etc/netplan/
sudo netplan apply
```

### 7.5 OpenSCAP Audit Failures

**Symptoms:**
- oscap command fails
- Missing SCAP profiles
- XML parsing errors

**Diagnosis:**
```bash
# Check OpenSCAP installation
oscap --version

# List available profiles
oscap info /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Verify SCAP Security Guide
dpkg -l | grep scap-security-guide
```

**Common fixes:**
```bash
# Reinstall OpenSCAP
sudo apt install --reinstall openscap-scanner scap-security-guide

# Update SCAP content
sudo apt update && sudo apt upgrade scap-security-guide

# Run with verbose output
oscap xccdf eval --verbose \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_workstation \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Use alternative profile (if primary fails)
oscap xccdf eval --profile cis \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
```

### 7.6 Rollback Procedure

**Full system rollback:**
```bash
# Option 1: VM Snapshot (fastest)
virsh snapshot-list ubuntu-cis-hardening-test
virsh snapshot-revert ubuntu-cis-hardening-test pre-hardening

# Option 2: Configuration backup
sudo /mnt/sec-levels/scripts/rollback.sh \
  /var/backups/sec-levels/<timestamp>

# Option 3: Manual restoration
sudo cp -r /var/backups/sec-levels/<timestamp>/* /
sudo systemctl daemon-reload
sudo systemctl restart <affected-services>
sudo reboot
```

**Verify rollback success:**
```bash
# Check SSH access
ssh testuser@192.168.122.XXX

# Verify services
sudo systemctl status ssh ufw

# Re-run baseline audit
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_workstation \
  --results ~/reports/rollback-verify-arf.xml \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Compare with original baseline
# Score should match pre-hardening baseline
```

### 7.7 Shared Folder (virtiofs) Not Mounting

**Symptoms:**
- Mount fails with "wrong fs type"
- `/mnt/sec-levels` empty after mount
- Permission denied errors

**Diagnosis:**
```bash
# Check virtiofs kernel support
grep virtiofs /proc/filesystems

# Check VM XML configuration
# On host:
virsh dumpxml ubuntu-cis-hardening-test | grep filesystem -A 10

# Check mount tag
virsh dumpxml ubuntu-cis-hardening-test | grep target
```

**Common fixes:**
```bash
# Try manual mount with debug
sudo mount -t virtiofs sec-levels-share /mnt/sec-levels -o debug

# Check kernel module loaded
lsmod | grep virtiofs

# Restart VM
virsh shutdown ubuntu-cis-hardening-test
virsh start ubuntu-cis-hardening-test

# Verify virtiofsd running on host
ps aux | grep virtiofsd

# Alternative: Use 9p (fallback)
# Edit VM XML, change filesystem type to 9p
# Inside VM:
sudo mount -t 9p -o trans=virtio sec-levels-share /mnt/sec-levels
```

---

## 8. Key Findings & Lessons Learned

### 8.1 What Worked Well

**VM Testing Environment:**
- ✅ **KVM/libvirt stability**: Zero hypervisor conflicts with Docker Desktop
- ✅ **virtiofs performance**: 3x faster than VirtualBox shared folders (40MB/s)
- ✅ **Snapshot workflow**: Instant rollback enabled fearless testing
- ✅ **NAT networking**: Simple, isolated, SSH-accessible
- ✅ **Automation scripts**: Reduced setup time from 2+ hours to 30 minutes

**Hardening Scripts:**
- ✅ **Incremental improvements**: v2.0 (67.34%) → v3.0 (73.51%) = +6.17%
- ✅ **System stability**: No service disruptions across 10+ test runs
- ✅ **Rollback reliability**: 100% success rate restoring from backups
- ✅ **SSH accessibility maintained**: Never lost remote access during testing
- ✅ **Enhanced security tools**: All 6 tools installed successfully

**Compliance Testing:**
- ✅ **OpenSCAP reliability**: Consistent results across kernel versions
- ✅ **Lynis validation**: Hardening index 72-73/100 = "Good" rating
- ✅ **Kernel independence**: GA/HWE/OEM kernels achieve identical scores

### 8.2 What to Watch Out For

**Environment Pitfalls:**
- ⚠️ **Group membership activation**: Requires full logout/login (not `newgrp`)
- ⚠️ **ISO version mismatches**: Ubuntu 24.04.1 vs 24.04.3 kernel differences
- ⚠️ **Disk space underestimation**: 50GB minimum for VM + snapshots
- ⚠️ **SSD recommended**: HDD-based VMs slow during AIDE/ClamAV scans

**Hardening Challenges:**
- ⚠️ **PAM complexity**: Biggest remaining gap (~15-20% potential improvement)
- ⚠️ **GNOME dconf persistence**: System-level settings require `/etc/dconf/db/`
- ⚠️ **IPv6 forwarding**: Failed to disable in some kernel configurations
- ⚠️ **Sudo timing**: Must apply sudo security LAST to avoid breaking script
- ⚠️ **Docker firewall bypass**: UFW rules bypassed by Docker iptables changes

**Testing Gotchas:**
- ⚠️ **AIDE initialization time**: 6-60 minutes depending on disk I/O
- ⚠️ **ClamAV memory usage**: 500MB RAM when active
- ⚠️ **OpenSCAP rule variance**: Total evaluated rules changed (355→396) between tests
- ⚠️ **SSH hardening limits**: Maintained password auth for testing (not CIS-compliant)

### 8.3 Best Practices Discovered

**Setup Phase:**
1. **Always use minimal Ubuntu installation** - Reduces testing noise
2. **Create baseline snapshot immediately** - Before any modifications
3. **Document VM credentials** - Password, username, IP address
4. **Verify SSH before hardening** - Ensure fallback access method
5. **Use shared folders, not SCP** - Faster workflow, no file sync issues

**Testing Phase:**
1. **Snapshot before each test run** - Enable instant rollback
2. **Test SSH after every major change** - Catch lockouts early
3. **Run Lynis + OpenSCAP together** - Cross-validate results
4. **Compare to baseline, not previous run** - Measure total improvement
5. **Document ALL changes** - Failed experiments inform future work

**Hardening Phase:**
1. **Apply controls incrementally** - Easier to isolate issues
2. **Test services after each section** - Catch breakage immediately
3. **Keep console access available** - Don't rely solely on SSH
4. **Backup before experimenting** - One-way changes need rollback plan
5. **Verify UFW after Docker usage** - Check for bypass rules

**Documentation Phase:**
1. **Screenshot compliance scores** - HTML reports for visual comparison
2. **Save both ARF XML and HTML** - XML for automation, HTML for review
3. **Note environmental differences** - Kernel version, resources, timing
4. **Record command sequences** - Enables reproducible testing
5. **Document workarounds** - Future troubleshooting reference

### 8.4 Performance Optimization Lessons

**VM Resource Allocation:**
- **8 CPUs ideal**: Faster than 4, no benefit beyond 8 for testing
- **16GB RAM sweet spot**: Enough for ClamAV + system, not wasteful
- **QCOW2 thin provisioning**: Saves disk space without performance penalty
- **SSD-backed storage**: 3-5x faster AIDE/ClamAV scans vs HDD

**Security Tool Configuration:**
- **ClamAV scheduled scans**: Run at 6:25 AM (low-usage time)
- **rkhunter weekly**: Sundays preferred (low-impact)
- **fail2ban default jails**: Sufficient, custom jails add complexity
- **Timeshift snapshots**: Manually triggered (avoid cron overhead)

### 8.5 Key Technical Insights

**Kernel Compatibility:**
- CIS compliance is **kernel-version independent** for Ubuntu 24.04
- Choose kernel based on **hardware needs**, not security compliance
- GA kernel (6.8) = stability, HWE kernel (6.11+) = new hardware support

**Compliance Ceiling:**
- **73.51% achievable** with v3.0 scripts (40+ additional controls)
- **78-82% estimated** with full PAM implementation (~15-20% gain)
- **85-90% realistic max** without organizational policy enforcement
- **95%+ unrealistic** for workstation (server controls not applicable)

**Security Trade-offs:**
- **IPv6 left enabled**: Gaming/Docker compatibility > attack surface reduction
- **SSH password auth allowed**: Testing access > full CIS compliance
- **Minimal PAM complexity**: Usability > maximum password requirements
- **Automated updates enabled**: Timely patching > manual control

**Tool Effectiveness:**
- **fail2ban**: High value, low overhead (intrusion prevention)
- **ClamAV**: Moderate value, high overhead (malware detection)
- **rkhunter**: Moderate value, zero overhead (rootkit detection)
- **AIDE**: High value, moderate overhead (file integrity)
- **Lynis**: High value, zero overhead (compliance validation)
- **Timeshift**: Critical value, zero overhead (disaster recovery)

### 8.6 Recommendations for Future Testing

**Environment Improvements:**
1. Automate VM creation script (reduce manual GUI steps)
2. Create golden image with pre-installed testing tools
3. Implement parallel testing (multiple VMs, different configurations)
4. Add CI/CD integration for automated testing on git push

**Script Enhancements:**
1. Implement full PAM configuration (password complexity, lockout)
2. Add system-level GNOME dconf settings (persistent)
3. Create Level 2 hardening variant (audit rules, stricter controls)
4. Add compliance reporting automation (before/after comparison)

**Documentation Additions:**
1. Video walkthrough of VM setup and testing workflow
2. Troubleshooting decision tree (symptom → diagnosis → fix)
3. Compliance matrix (control → script section → verification)
4. Performance tuning guide (low-spec vs high-spec recommendations)

---

## Appendix: Quick Reference

### A. Essential Commands

**VM Management:**
```bash
virsh list --all                    # List all VMs
virsh start <vm-name>               # Start VM
virsh shutdown <vm-name>            # Graceful shutdown
virsh snapshot-list <vm-name>       # List snapshots
virsh snapshot-revert <vm-name> <snapshot>  # Revert
virsh net-dhcp-leases default       # Get VM IP
```

**Testing Workflow:**
```bash
# Baseline audit
sudo oscap xccdf eval --profile cis_level1_workstation \
  --results baseline-arf.xml --report baseline.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Apply hardening
sudo ./scripts/harden.sh level1

# Post-hardening audit
sudo oscap xccdf eval --profile cis_level1_workstation \
  --results hardened-arf.xml --report hardened.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Lynis audit
sudo lynis audit system
```

**Service Checks:**
```bash
sudo systemctl status ssh ufw fail2ban clamav-daemon
sudo ufw status verbose
sudo aa-status
sudo fail2ban-client status sshd
```

### B. File Locations

**Configuration Files:**
- SSH: `/etc/ssh/sshd_config`
- UFW: `/etc/ufw/`
- sysctl: `/etc/sysctl.d/`
- fail2ban: `/etc/fail2ban/jail.local`
- AppArmor: `/etc/apparmor.d/`

**Logs:**
- ClamAV: `/var/log/clamav/daily-scan.log`
- rkhunter: `/var/log/rkhunter-scan.log`
- Lynis: `/var/log/lynis.log`
- fail2ban: `/var/log/fail2ban.log`
- System audit: `/var/log/audit/audit.log`

**Backups:**
- Configuration backups: `/var/backups/sec-levels/<timestamp>/`

### C. Success Criteria

**Minimum acceptable results:**
- ✅ CIS Level 1: 70%+ compliance
- ✅ Lynis: 70+ hardening index
- ✅ SSH access maintained
- ✅ All critical services running
- ✅ Network connectivity functional
- ✅ Rollback tested and successful

---

**Document Version:** 3.0
**Last Validated:** November 2025
**Platform:** Ubuntu 24.04.03 LTS
**Kernel Compatibility:** 6.8.x - 6.14.x tested
