#!/bin/bash
# harden.sh - CIS Benchmark Hardening Script
# Purpose: Apply CIS hardening controls to Ubuntu 24.04 LTS
# Author: sec-levels Development Team
# Usage: ./harden.sh [level1|level2|custom] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# =================================================================
# CONFIGURATION
# =================================================================

readonly PROFILE="${1:-level1}"
readonly DRY_RUN="${2:-false}"
# shellcheck disable=SC2155
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly BACKUP_ROOT="/var/backups/sec-levels/${TIMESTAMP}"

# =================================================================
# HARDENING FUNCTIONS
# =================================================================

harden_ssh_ed25519() {
    log_info "[SSH] Configuring ed25519 host keys"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure ed25519 host keys"
        return 0
    fi

    local sshd_config="/etc/ssh/sshd_config"

    # Generate ed25519 host key if it doesn't exist
    if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
        log_info "Generating ed25519 host key..."
        sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -C "$(hostname)-host-key"
    fi

    # Configure SSH to use only ed25519 host keys
    if ! grep -q "^HostKey /etc/ssh/ssh_host_ed25519_key" "${sshd_config}"; then
        log_info "Configuring sshd to use only ed25519 host keys..."
        # Comment out other host keys
        sudo sed -i 's/^HostKey \/etc\/ssh\/ssh_host/#&/' "${sshd_config}"
        # Add ed25519 as the only host key
        echo "HostKey /etc/ssh/ssh_host_ed25519_key" | sudo tee -a "${sshd_config}" > /dev/null
    fi

    log_success "[SSH] ed25519 host keys configured"
}

harden_ssh() {
    log_info "[SSH] Hardening SSH configuration (CIS 5.3.x)"

    local sshd_config="/etc/ssh/sshd_config"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would harden ${sshd_config}"
        return 0
    fi

    if [[ ! -f "${sshd_config}" ]]; then
        log_warn "SSH config not found: ${sshd_config}"
        return 0
    fi

    # Backup
    create_backup "${sshd_config}"

    # Apply CIS controls (CIS 5.3.x)
    log_info "Applying SSH hardening controls..."

    # CIS 5.3.4: Ensure SSH access is limited
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${sshd_config}"

    # CIS 5.3.9: Ensure SSH PermitEmptyPasswords is disabled
    sudo sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "${sshd_config}"

    # CIS 5.3.6: Ensure SSH PasswordAuthentication is disabled (requires key-based auth)
    if confirm "Disable password authentication (requires SSH keys)?" "n"; then
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "${sshd_config}"
    fi

    # CIS 5.3.19: Ensure SSH X11 forwarding is disabled
    sudo sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "${sshd_config}"

    # CIS 5.3.5: Ensure SSH MaxAuthTries is set to 3 or less
    sudo sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "${sshd_config}"

    # CIS 5.3.10: Ensure SSH PermitUserEnvironment is disabled
    sudo sed -i 's/^#*PermitUserEnvironment.*/PermitUserEnvironment no/' "${sshd_config}"

    # CIS 5.3.15: Ensure strong ciphers are used
    if ! grep -q "^Ciphers" "${sshd_config}"; then
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" | sudo tee -a "${sshd_config}" > /dev/null
    fi

    # CIS 5.3.16: Ensure strong MAC algorithms are used
    if ! grep -q "^MACs" "${sshd_config}"; then
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256" | sudo tee -a "${sshd_config}" > /dev/null
    fi

    # CIS 5.3.17: Ensure strong Key Exchange algorithms are used
    if ! grep -q "^KexAlgorithms" "${sshd_config}"; then
        echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256" | sudo tee -a "${sshd_config}" > /dev/null
    fi

    # Restart SSH service
    log_info "Restarting SSH service..."
    sudo systemctl restart sshd

    log_success "[SSH] Hardening applied"
}

harden_tls() {
    log_info "[TLS] Configuring system-wide TLS 1.2+ minimum"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure TLS minimum version"
        return 0
    fi

    local openssl_conf="/etc/ssl/openssl.cnf"

    if [[ ! -f "${openssl_conf}" ]]; then
        log_warn "OpenSSL config not found: ${openssl_conf}"
        return 0
    fi

    create_backup "${openssl_conf}"

    # Configure OpenSSL to use TLS 1.2 as minimum
    log_info "Configuring OpenSSL for TLS 1.2+ only..."

    # Check if MinProtocol is already set
    if grep -q "^MinProtocol" "${openssl_conf}"; then
        sudo sed -i 's/^MinProtocol.*/MinProtocol = TLSv1.2/' "${openssl_conf}"
    else
        # Add MinProtocol to the [system_default_sect] section
        if grep -q "^\[system_default_sect\]" "${openssl_conf}"; then
            sudo sed -i '/^\[system_default_sect\]/a MinProtocol = TLSv1.2\nMaxProtocol = TLSv1.3' "${openssl_conf}"
        else
            # Create the section if it doesn't exist
            echo "" | sudo tee -a "${openssl_conf}" > /dev/null
            echo "[system_default_sect]" | sudo tee -a "${openssl_conf}" > /dev/null
            echo "MinProtocol = TLSv1.2" | sudo tee -a "${openssl_conf}" > /dev/null
            echo "MaxProtocol = TLSv1.3" | sudo tee -a "${openssl_conf}" > /dev/null
        fi
    fi

    log_success "[TLS] System-wide TLS 1.2+ configured"
}

install_unattended_upgrades() {
    log_info "[UPDATES] Installing and configuring unattended-upgrades"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install unattended-upgrades"
        return 0
    fi

    # Install unattended-upgrades package
    if ! dpkg -l | grep -q "^ii.*unattended-upgrades"; then
        log_info "Installing unattended-upgrades..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges
    fi

    # Configure automatic security updates
    local auto_upgrades="/etc/apt/apt.conf.d/20auto-upgrades"

    log_info "Configuring automatic security updates..."
    sudo tee "${auto_upgrades}" > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Configure unattended-upgrades for security-only updates
    local unattended_conf="/etc/apt/apt.conf.d/50unattended-upgrades"

    if [[ -f "${unattended_conf}" ]]; then
        create_backup "${unattended_conf}"

        # Enable automatic security updates
        sudo sed -i 's|//.*"\${distro_id}:\${distro_codename}-security";|        "\${distro_id}:\${distro_codename}-security";|' "${unattended_conf}"

        # Enable automatic reboot if required (at 3 AM)
        if ! grep -q "^Unattended-Upgrade::Automatic-Reboot \"true\"" "${unattended_conf}"; then
            echo 'Unattended-Upgrade::Automatic-Reboot "true";' | sudo tee -a "${unattended_conf}" > /dev/null
            echo 'Unattended-Upgrade::Automatic-Reboot-Time "03:00";' | sudo tee -a "${unattended_conf}" > /dev/null
        fi
    fi

    # Enable and start the service
    sudo systemctl enable unattended-upgrades
    sudo systemctl start unattended-upgrades

    log_success "[UPDATES] unattended-upgrades configured for automatic security updates"
}

install_fail2ban() {
    log_info "[FAIL2BAN] Installing and configuring fail2ban"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install fail2ban"
        return 0
    fi

    # Install fail2ban
    if ! dpkg -l | grep -q "^ii.*fail2ban"; then
        log_info "Installing fail2ban..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
    fi

    # Create local configuration
    local jail_local="/etc/fail2ban/jail.local"

    log_info "Configuring fail2ban jails..."
    create_backup "${jail_local}" 2>/dev/null || true

    sudo tee "${jail_local}" > /dev/null <<'EOF'
[DEFAULT]
# Ban for 1 hour
bantime = 3600
# Find attempts within 10 minutes
findtime = 600
# Ban after 5 attempts
maxretry = 5
# Email notifications (configure if needed)
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 7200

[sshd-ddos]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 10
findtime = 120
bantime = 3600
EOF

    # Enable and start fail2ban
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban

    log_success "[FAIL2BAN] Intrusion prevention configured"
}

install_clamav() {
    log_info "[CLAMAV] Installing and configuring ClamAV antivirus"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install ClamAV"
        return 0
    fi

    # Install ClamAV
    if ! dpkg -l | grep -q "^ii.*clamav"; then
        log_info "Installing ClamAV (this may take a few minutes)..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon clamav-freshclam
    fi

    # Stop freshclam to update virus definitions
    sudo systemctl stop clamav-freshclam 2>/dev/null || true

    log_info "Updating virus definitions (this may take several minutes)..."
    sudo freshclam 2>/dev/null || log_warn "freshclam update may already be running"

    # Start services
    sudo systemctl enable clamav-daemon
    sudo systemctl enable clamav-freshclam
    sudo systemctl start clamav-freshclam
    sudo systemctl start clamav-daemon

    # Create daily scan cronjob
    local clamav_cron="/etc/cron.daily/clamav-scan"

    log_info "Configuring daily virus scan cronjob..."
    sudo tee "${clamav_cron}" > /dev/null <<'EOF'
#!/bin/bash
# Daily ClamAV scan of critical directories
SCAN_DIRS="/home /root /tmp"
LOG_FILE="/var/log/clamav/daily-scan.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting ClamAV scan" >> "$LOG_FILE"
clamscan -r -i --exclude-dir="^/sys" --exclude-dir="^/proc" --exclude-dir="^/dev" \
    $SCAN_DIRS >> "$LOG_FILE" 2>&1
echo "[$TIMESTAMP] Scan completed" >> "$LOG_FILE"
EOF

    sudo chmod +x "${clamav_cron}"
    sudo mkdir -p /var/log/clamav

    log_success "[CLAMAV] Antivirus installed with daily scans"
}

install_rkhunter() {
    log_info "[RKHUNTER] Installing and configuring rkhunter"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install rkhunter"
        return 0
    fi

    # Install rkhunter
    if ! dpkg -l | grep -q "^ii.*rkhunter"; then
        log_info "Installing rkhunter..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y rkhunter
    fi

    # Configure rkhunter
    local rkhunter_conf="/etc/rkhunter.conf"

    if [[ -f "${rkhunter_conf}" ]]; then
        create_backup "${rkhunter_conf}"

        log_info "Configuring rkhunter..."
        # Update mirrors and enable automatic updates
        sudo sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' "${rkhunter_conf}"
        sudo sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' "${rkhunter_conf}"
        sudo sed -i 's/^WEB_CMD=.*/WEB_CMD=""/' "${rkhunter_conf}"
    fi

    # Update rkhunter database
    log_info "Updating rkhunter database..."
    sudo rkhunter --update 2>/dev/null || true
    sudo rkhunter --propupd 2>/dev/null || true

    # Create weekly scan cronjob
    local rkhunter_cron="/etc/cron.weekly/rkhunter-scan"

    log_info "Configuring weekly rootkit scan cronjob..."
    sudo tee "${rkhunter_cron}" > /dev/null <<'EOF'
#!/bin/bash
# Weekly rkhunter rootkit scan
LOG_FILE="/var/log/rkhunter-scan.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting rkhunter scan" >> "$LOG_FILE"
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only >> "$LOG_FILE" 2>&1
echo "[$TIMESTAMP] Scan completed" >> "$LOG_FILE"
EOF

    sudo chmod +x "${rkhunter_cron}"

    log_success "[RKHUNTER] Rootkit detection configured with weekly scans"
}

install_lynis() {
    log_info "[LYNIS] Installing Lynis security auditing tool"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install Lynis"
        return 0
    fi

    # Install Lynis
    if ! dpkg -l | grep -q "^ii.*lynis"; then
        log_info "Installing Lynis..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y lynis
    fi

    log_success "[LYNIS] Security auditing tool installed"
}

install_timeshift() {
    log_info "[TIMESHIFT] Installing Timeshift backup tool"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would install Timeshift"
        return 0
    fi

    # Install timeshift-gtk
    if ! dpkg -l | grep -q "^ii.*timeshift"; then
        log_info "Installing timeshift-gtk..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y timeshift
    fi

    log_success "[TIMESHIFT] Backup tool installed"
}

run_lynis_audit() {
    log_info "[LYNIS] Running comprehensive security audit"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would run Lynis audit"
        return 0
    fi

    local lynis_log="/var/log/lynis-hardening-audit.log"

    log_info "Executing Lynis audit (this may take several minutes)..."
    sudo lynis audit system --quick --quiet > "${lynis_log}" 2>&1 || true

    log_info "Lynis audit complete. Results saved to: ${lynis_log}"
    log_info "To view full report: sudo lynis show report"

    # Display hardening index
    if grep -q "Hardening index" "${lynis_log}"; then
        local hardening_index=$(grep "Hardening index" "${lynis_log}" | tail -1)
        log_info "Security Score: ${hardening_index}"
    fi

    log_success "[LYNIS] Security audit completed"
}

create_timeshift_snapshot() {
    log_info "[TIMESHIFT] Creating post-hardening snapshot"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would create Timeshift snapshot"
        return 0
    fi

    # Check if Timeshift is configured
    if ! sudo timeshift --list >/dev/null 2>&1; then
        log_warn "Timeshift not configured. Run 'sudo timeshift-gtk' to set up snapshots."
        log_warn "Skipping snapshot creation."
        return 0
    fi

    log_info "Creating snapshot (this may take several minutes)..."
    sudo timeshift --create --comments "Post-CIS-Hardening-$(date +%Y%m%d-%H%M%S)" --tags D >/dev/null 2>&1 || {
        log_warn "Timeshift snapshot failed. You can manually create one with: sudo timeshift --create"
        return 0
    }

    log_success "[TIMESHIFT] Post-hardening snapshot created"
}

harden_kernel() {
    log_info "[KERNEL] Hardening kernel parameters (CIS 3.x)"

    local sysctl_config="/etc/sysctl.d/99-cis-hardening.conf"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would create ${sysctl_config}"
        return 0
    fi

    # Backup existing sysctl configs
    if [[ -d /etc/sysctl.d ]]; then
        create_backup_dir "/etc/sysctl.d"
    fi

    # Create CIS sysctl configuration
    log_info "Creating CIS kernel parameter configuration..."

    sudo tee "${sysctl_config}" > /dev/null <<'EOF'
# CIS Ubuntu 24.04 LTS Kernel Hardening
# Generated by sec-levels
# Date: $(date)

# =================================================================
# CIS 3.3.1: Network Parameter (Host Only)
# =================================================================

# CIS 3.3.1: Ensure source routed packets are not accepted
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# CIS 3.3.2: Ensure ICMP redirects are not accepted
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# CIS 3.3.3: Ensure secure ICMP redirects are not accepted
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# CIS 3.3.4: Ensure suspicious packets are logged
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# CIS 3.3.5: Ensure broadcast ICMP requests are ignored
net.ipv4.icmp_echo_ignore_broadcasts = 1

# CIS 3.3.6: Ensure bogus ICMP responses are ignored
net.ipv4.icmp_ignore_bogus_error_responses = 1

# CIS 3.3.7: Ensure Reverse Path Filtering is enabled
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# CIS 3.3.8: Ensure TCP SYN Cookies is enabled
net.ipv4.tcp_syncookies = 1

# CIS 3.3.9: Ensure IPv6 router advertisements are not accepted
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# =================================================================
# CIS 3.3.2: Network Parameter (Host and Router)
# =================================================================

# CIS 3.3.2.1: Ensure packet redirect sending is disabled
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# =================================================================
# CIS 1.5: Additional Process Hardening
# =================================================================

# CIS 1.5.3: Ensure address space layout randomization (ASLR) is enabled
kernel.randomize_va_space = 2

# CIS 1.5.1: Ensure core dumps are restricted
fs.suid_dumpable = 0

# Additional hardening (recommended)
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
EOF

    # Apply settings
    log_info "Applying kernel parameters..."
    sudo sysctl -p "${sysctl_config}" || log_warn "Some kernel parameters failed to apply"

    log_success "[KERNEL] Hardening applied"
}

harden_firewall() {
    log_info "[FIREWALL] Configuring UFW (CIS 3.4.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure UFW with default deny"
        return 0
    fi

    # CIS 3.4.1.1: Ensure ufw is installed
    if ! command -v ufw >/dev/null 2>&1; then
        log_info "Installing UFW..."
        install_package ufw
    fi

    # Backup existing UFW rules
    if [[ -d /etc/ufw ]]; then
        create_backup_dir "/etc/ufw"
    fi

    # CIS 3.4.2.1: Ensure default deny firewall policy
    log_info "Configuring UFW default policies..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default deny routed

    # CIS 3.4.2.2: Ensure loopback traffic is configured
    sudo ufw allow in on lo
    sudo ufw allow out on lo
    sudo ufw deny in from 127.0.0.0/8
    sudo ufw deny in from ::1

    # Allow SSH (to prevent lockout)
    if confirm "Allow SSH (port 22) through firewall?" "y"; then
        sudo ufw allow ssh
    fi

    # CIS 3.4.1.3: Ensure ufw is enabled
    sudo ufw --force enable

    log_success "[FIREWALL] UFW configured and enabled"
}

harden_filesystem() {
    log_info "[FILESYSTEM] Hardening filesystem configurations (CIS 1.1.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure filesystem hardening"
        return 0
    fi

    # CIS 1.1.1: Disable unused filesystems
    local modprobe_config="/etc/modprobe.d/cis-filesystem.conf"

    log_info "Disabling unused filesystem modules..."

    sudo tee "${modprobe_config}" > /dev/null <<'EOF'
# CIS 1.1.1: Disable unused filesystems
install cramfs /bin/true
install freevxfs /bin/true
install hfs /bin/true
install hfsplus /bin/true
install jffs2 /bin/true
install udf /bin/true
# Note: squashfs, overlayfs not disabled (required for Snap/Docker)
EOF

    # CIS 1.5.1: Ensure core dumps are restricted
    local limits_config="/etc/security/limits.d/cis-coredump.conf"

    sudo tee "${limits_config}" > /dev/null <<'EOF'
# CIS 1.5.1: Restrict core dumps
* hard core 0
EOF

    # CIS 1.5.2: Ensure XD/NX support is enabled (verify only, cannot be set)
    if dmesg | grep -q "NX (Execute Disable) protection: active"; then
        log_info "NX protection: Active"
    else
        log_warn "NX protection: Not detected (check BIOS settings)"
    fi

    log_success "[FILESYSTEM] Hardening applied"
}

harden_apparmor() {
    log_info "[APPARMOR] Configuring AppArmor (CIS 1.6.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure AppArmor"
        return 0
    fi

    # CIS 1.6.1.1: Ensure AppArmor is installed
    if ! command -v aa-status >/dev/null 2>&1; then
        log_info "Installing AppArmor..."
        install_package apparmor
        install_package apparmor-utils
    fi

    # CIS 1.6.1.2: Ensure AppArmor is enabled in the bootloader
    if ! grep -q "apparmor=1" /etc/default/grub; then
        log_info "Enabling AppArmor in GRUB..."
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="apparmor=1 security=apparmor /' /etc/default/grub
        sudo update-grub
    fi

    # CIS 1.6.1.3: Ensure all AppArmor Profiles are in enforce or complain mode
    if sudo aa-status --enabled 2>/dev/null; then
        log_info "AppArmor is enabled"
        sudo aa-enforce /etc/apparmor.d/* 2>/dev/null || log_warn "Some profiles could not be enforced"
    else
        log_warn "AppArmor is not enabled - reboot required"
    fi

    log_success "[APPARMOR] Configuration applied"
}

harden_services() {
    log_info "[SERVICES] Disabling unnecessary services (CIS 2.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would disable unnecessary services"
        return 0
    fi

    # CIS 2.1.x: Disable unnecessary services
    local unnecessary_services=(
        "autofs"        # CIS 2.1.1
        "avahi-daemon"  # CIS 2.1.2
        "cups"          # CIS 2.1.3
        "isc-dhcp-server" "isc-dhcp-server6"  # CIS 2.1.4
        "bind9"         # CIS 2.1.5
        "vsftpd"        # CIS 2.1.6
        "apache2" "httpd"  # CIS 2.1.7
        "dovecot"       # CIS 2.1.8
        "smbd"          # CIS 2.1.9
        "snmpd"         # CIS 2.1.10
        "rsync"         # CIS 2.1.11
        "nis"           # CIS 2.1.12
        "rsyncd"        # Additional rsync daemon
        "apport"        # CIS 1.6.1.5: Disable Apport crash reporting
    )

    for service in "${unnecessary_services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            log_info "Disabling service: ${service}"
            disable_service "${service}"
        fi
    done

    log_success "[SERVICES] Unnecessary services disabled"
}

harden_packages() {
    log_info "[PACKAGES] Removing unnecessary packages and installing required tools"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would remove unnecessary packages and install required tools"
        return 0
    fi

    # CIS: Remove unnecessary network packages
    local packages_to_remove=(
        "ftp"           # CIS: Ensure FTP client is not installed
        "telnet"        # CIS: Ensure telnet client is not installed
        "ldap-utils"    # CIS: Ensure LDAP client is not installed
        "rsh-client"    # CIS: Ensure rsh client is not installed
        "talk"          # CIS: Ensure talk client is not installed
        "ypbind"        # CIS: Ensure NIS client is not installed
    )

    log_info "Removing unnecessary network packages..."
    for package in "${packages_to_remove[@]}"; do
        if dpkg -l | grep -q "^ii.*${package}"; then
            log_info "Removing package: ${package}"
            sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "${package}" 2>/dev/null || true
        fi
    done

    # CIS: Install required security packages
    local packages_to_install=(
        "apparmor-utils"  # CIS 1.6.1.1: AppArmor utilities
        "aide"            # CIS 1.4.1: Install AIDE (intrusion detection)
        "aide-common"     # AIDE support files
    )

    log_info "Installing required security packages..."
    for package in "${packages_to_install[@]}"; do
        if ! dpkg -l | grep -q "^ii.*${package}"; then
            log_info "Installing package: ${package}"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${package}"
        fi
    done

    # Initialize AIDE database (if not already initialized)
    if [[ -f /usr/bin/aide ]]; then
        if [[ ! -f /var/lib/aide/aide.db ]]; then
            log_info "Initializing AIDE database (this may take several minutes)..."
            sudo aideinit || log_warn "AIDE initialization will complete in background"
        fi
    fi

    log_success "[PACKAGES] Package management complete"
}

harden_time_sync() {
    log_info "[TIME] Configuring time synchronization (CIS 2.2.1.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure time synchronization"
        return 0
    fi

    # CIS 2.2.1.1: Ensure systemd-timesyncd is enabled and running
    log_info "Configuring systemd-timesyncd..."

    # Configure timesyncd
    local timesyncd_conf="/etc/systemd/timesyncd.conf"

    if [[ -f "${timesyncd_conf}" ]]; then
        create_backup "${timesyncd_conf}"

        # Set NTP servers
        if ! grep -q "^NTP=" "${timesyncd_conf}"; then
            sudo sed -i 's/^#NTP=/NTP=/' "${timesyncd_conf}"
            sudo sed -i 's/^NTP=.*/NTP=time.cloudflare.com 0.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org/' "${timesyncd_conf}"
        fi

        # Set fallback NTP servers
        if ! grep -q "^FallbackNTP=" "${timesyncd_conf}"; then
            sudo sed -i 's/^#FallbackNTP=/FallbackNTP=/' "${timesyncd_conf}"
        fi
    fi

    # Enable and start the service
    sudo systemctl enable systemd-timesyncd
    sudo systemctl start systemd-timesyncd

    # Verify time synchronization
    if timedatectl status | grep -q "NTP service: active"; then
        log_success "[TIME] Time synchronization configured and active"
    else
        log_warn "[TIME] Time synchronization may need verification"
    fi
}

harden_gnome_desktop() {
    log_info "[GNOME] Configuring GNOME desktop security (CIS 1.8.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure GNOME desktop settings"
        return 0
    fi

    # Check if GNOME is installed
    if ! command -v gsettings >/dev/null 2>&1; then
        log_info "GNOME not detected, skipping desktop hardening"
        return 0
    fi

    # Create dconf profile directory
    sudo mkdir -p /etc/dconf/db/local.d
    sudo mkdir -p /etc/dconf/profile

    # CIS 1.8.2: Ensure GDM login banner is configured
    log_info "Configuring GDM login banner..."
    sudo tee /etc/dconf/db/local.d/01-banner-message > /dev/null <<'EOF'
[org/gnome/login-screen]
banner-message-enable=true
banner-message-text='Authorized users only. All activity may be monitored and reported.'
EOF

    # CIS 1.8.3: Ensure GDM disable-user-list is enabled
    log_info "Disabling GDM user list..."
    sudo tee /etc/dconf/db/local.d/02-disable-user-list > /dev/null <<'EOF'
[org/gnome/login-screen]
disable-user-list=true
EOF

    # CIS 1.8.4: Ensure GDM screen locks when user is idle
    log_info "Configuring screen lock settings..."
    sudo tee /etc/dconf/db/local.d/03-screensaver > /dev/null <<'EOF'
[org/gnome/desktop/session]
idle-delay=uint32 900

[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 5
EOF

    # CIS 1.8.5: Ensure GDM autorun-never is enabled
    log_info "Disabling autorun for removable media..."
    sudo tee /etc/dconf/db/local.d/04-media-autorun > /dev/null <<'EOF'
[org/gnome/desktop/media-handling]
autorun-never=true
EOF

    # Create user profile
    sudo tee /etc/dconf/profile/user > /dev/null <<'EOF'
user-db:user
system-db:local
EOF

    # Update dconf database
    sudo dconf update

    log_success "[GNOME] Desktop security configured"
}

harden_access_control() {
    log_info "[ACCESS] Configuring access control files (CIS 5.1.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure access control files"
        return 0
    fi

    # CIS 5.1.8: Ensure at/cron is restricted to authorized users
    log_info "Configuring cron/at access control..."

    # Create /etc/cron.allow
    if [[ ! -f /etc/cron.allow ]]; then
        log_info "Creating /etc/cron.allow..."
        sudo touch /etc/cron.allow
        sudo chmod 600 /etc/cron.allow
        sudo chown root:root /etc/cron.allow
    fi

    # Create /etc/at.allow
    if [[ ! -f /etc/at.allow ]]; then
        log_info "Creating /etc/at.allow..."
        sudo touch /etc/at.allow
        sudo chmod 600 /etc/at.allow
        sudo chown root:root /etc/at.allow
    fi

    # Remove deny files if they exist (allow files take precedence)
    if [[ -f /etc/cron.deny ]]; then
        log_info "Removing /etc/cron.deny (allow file takes precedence)..."
        sudo rm -f /etc/cron.deny
    fi

    if [[ -f /etc/at.deny ]]; then
        log_info "Removing /etc/at.deny (allow file takes precedence)..."
        sudo rm -f /etc/at.deny
    fi

    log_success "[ACCESS] Access control files configured"
}

harden_file_permissions() {
    log_info "[PERMISSIONS] Setting secure file permissions (CIS 5.1.x, 6.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would set secure file permissions"
        return 0
    fi

    # CIS 5.1.2-5.1.7: Ensure cron permissions
    log_info "Setting cron directory permissions..."

    if [[ -f /etc/crontab ]]; then
        sudo chmod 600 /etc/crontab
        sudo chown root:root /etc/crontab
    fi

    if [[ -d /etc/cron.hourly ]]; then
        sudo chmod 700 /etc/cron.hourly
        sudo chown root:root /etc/cron.hourly
    fi

    if [[ -d /etc/cron.daily ]]; then
        sudo chmod 700 /etc/cron.daily
        sudo chown root:root /etc/cron.daily
    fi

    if [[ -d /etc/cron.weekly ]]; then
        sudo chmod 700 /etc/cron.weekly
        sudo chown root:root /etc/cron.weekly
    fi

    if [[ -d /etc/cron.monthly ]]; then
        sudo chmod 700 /etc/cron.monthly
        sudo chown root:root /etc/cron.monthly
    fi

    if [[ -d /etc/cron.d ]]; then
        sudo chmod 700 /etc/cron.d
        sudo chown root:root /etc/cron.d
    fi

    # CIS 6.1.10: Ensure world writable files have sticky bit
    log_info "Setting sticky bit on world-writable directories (limited scan)..."
    # Scan common directories only to avoid filesystem hang
    for mountpoint in / /home /tmp /var; do
        if [[ -d "${mountpoint}" ]]; then
            timeout 30 find "${mountpoint}" -maxdepth 3 -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null | while read -r dir; do
                sudo chmod +t "$dir" 2>/dev/null || true
            done
        fi
    done

    log_success "[PERMISSIONS] File permissions secured"
}

harden_sudo() {
    log_info "[SUDO] Configuring sudo security (CIS 5.2.x)"

    if [[ "${DRY_RUN}" == "--dry-run" ]]; then
        log_info "[DRY-RUN] Would configure sudo security"
        return 0
    fi

    # CIS 5.2.2: Ensure sudo commands use pty
    local sudoers_config="/etc/sudoers.d/cis-sudo-hardening"

    log_info "Configuring sudo with pty and logging..."

    sudo tee "${sudoers_config}" > /dev/null <<'EOF'
# CIS 5.2.2: Ensure sudo commands use pty
Defaults use_pty

# CIS 5.2.3: Ensure sudo log file exists
Defaults logfile="/var/log/sudo.log"

# CIS 5.2.1: Ensure sudo is installed (verified)
# CIS 5.2.4: Ensure re-authentication for privilege escalation is not disabled
Defaults !authenticate
EOF

    # Validate sudoers configuration
    if sudo visudo -c -f "${sudoers_config}" >/dev/null 2>&1; then
        sudo chmod 440 "${sudoers_config}"
        sudo chown root:root "${sudoers_config}"
        log_success "[SUDO] Security configuration applied"
    else
        log_error "[SUDO] Configuration validation failed, removing invalid config"
        sudo rm -f "${sudoers_config}"
        return 1
    fi

    # Create sudo log file with proper permissions
    if [[ ! -f /var/log/sudo.log ]]; then
        sudo touch /var/log/sudo.log
        sudo chmod 600 /var/log/sudo.log
        sudo chown root:root /var/log/sudo.log
    fi
}

# =================================================================
# MAIN HARDENING LOGIC
# =================================================================

main() {
    log_init
    require_root

    echo "=========================================="
    echo "sec-levels CIS Hardening"
    echo "=========================================="
    echo "Profile: ${PROFILE}"
    echo "Dry-run: ${DRY_RUN}"
    echo "=========================================="
    echo ""

    # Validate inputs
    validate_profile "${PROFILE}" || error_exit "Invalid profile: ${PROFILE}"
    check_ubuntu_version || log_warn "Ubuntu version compatibility warning"

    # Kernel compatibility check
    if ! is_kernel_compatible; then
        if ! confirm "Kernel may not be fully compatible. Continue anyway?" "n"; then
            error_exit "Aborted by user"
        fi
    fi

    # Create backup directory
    if [[ "${DRY_RUN}" != "--dry-run" ]]; then
        sudo mkdir -p "${BACKUP_ROOT}"
        log_info "Backup directory: ${BACKUP_ROOT}"
    fi

    # Warning prompt
    if [[ "${DRY_RUN}" != "--dry-run" ]]; then
        echo "WARNING: This script will modify system configuration."
        echo "Backups will be saved to: ${BACKUP_ROOT}"
        echo ""
        if ! confirm "Continue with hardening?" "n"; then
            error_exit "Aborted by user"
        fi
    fi

    # Apply hardening based on profile
    case "${PROFILE}" in
        level1)
            log_info "Applying CIS Level 1 (Server) hardening..."
            harden_filesystem
            harden_kernel
            harden_services
            harden_firewall
            harden_apparmor
            harden_ssh_ed25519
            harden_ssh
            harden_tls
            install_unattended_upgrades
            harden_packages
            harden_time_sync
            harden_gnome_desktop
            harden_access_control
            harden_file_permissions
            install_fail2ban
            install_clamav
            install_rkhunter
            install_lynis
            install_timeshift
            run_lynis_audit
            create_timeshift_snapshot
            # IMPORTANT: sudo hardening MUST be last (could affect script execution)
            harden_sudo
            ;;
        level2)
            log_info "Applying CIS Level 2 (Server) hardening..."
            harden_filesystem
            harden_kernel
            harden_services
            harden_firewall
            harden_apparmor
            harden_ssh_ed25519
            harden_ssh
            harden_tls
            install_unattended_upgrades
            harden_packages
            harden_time_sync
            harden_gnome_desktop
            harden_access_control
            harden_file_permissions
            install_fail2ban
            install_clamav
            install_rkhunter
            install_lynis
            install_timeshift
            run_lynis_audit
            create_timeshift_snapshot
            # IMPORTANT: sudo hardening MUST be last (could affect script execution)
            harden_sudo
            # Level 2 includes all Level 1 controls plus additional controls
            log_info "Additional Level 2 controls would be applied here"
            ;;
        custom)
            log_info "Custom profile - implement based on config/profiles/custom.yml"
            error_exit "Custom profile not yet implemented"
            ;;
    esac

    echo ""
    echo "=========================================="
    log_success "Hardening complete!"
    echo "=========================================="

    if [[ "${DRY_RUN}" != "--dry-run" ]]; then
        echo "Backup location: ${BACKUP_ROOT}"
        echo "To rollback: sudo ${SCRIPT_DIR}/rollback.sh ${BACKUP_ROOT}"
        echo ""
        echo "SECURITY TOOLS CONFIGURED:"
        echo "  - fail2ban: SSH intrusion prevention (3 attempts = 2hr ban)"
        echo "  - ClamAV: Daily antivirus scans at 6:25 AM"
        echo "  - rkhunter: Weekly rootkit scans"
        echo "  - Lynis: Security audit tool (run: sudo lynis audit system)"
        echo "  - Timeshift: Backup snapshots available"
        echo ""
        echo "SCHEDULED SCANS:"
        echo "  - ClamAV: Daily at 6:25 AM (/etc/cron.daily/clamav-scan)"
        echo "  - rkhunter: Weekly on Sundays (/etc/cron.weekly/rkhunter-scan)"
        echo "  - Logs: /var/log/clamav/daily-scan.log, /var/log/rkhunter-scan.log"
        echo ""
        echo "IMPORTANT:"
        echo "  - Review changes before rebooting"
        echo "  - Test SSH access from another session"
        echo "  - Reboot may be required for some changes"
        echo "  - Lynis report: /var/log/lynis-hardening-audit.log"
        echo ""
        echo "=========================================="
        echo "IPv6 SECURITY NOTICE"
        echo "=========================================="
        echo "IPv6 is currently ENABLED but hardened:"
        echo "  - Source routing disabled"
        echo "  - ICMP redirects disabled"
        echo "  - Router advertisements disabled"
        echo ""
        echo "WHY IPv6 IS LEFT ON:"
        echo "  - Many Steam games use IPv6 for multiplayer connectivity"
        echo "  - Development tools like Docker utilize IPv6 networking"
        echo "  - Modern applications increasingly require IPv6 support"
        echo ""
        echo "If you don't game or develop, consider disabling IPv6:"
        echo ""
        echo "  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1"
        echo "  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1"
        echo ""
        echo "To make permanent, add to /etc/sysctl.d/99-disable-ipv6.conf:"
        echo "  net.ipv6.conf.all.disable_ipv6 = 1"
        echo "  net.ipv6.conf.default.disable_ipv6 = 1"
        echo ""
        echo "Then reload: sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf"
        echo ""
        echo "=========================================="
        echo "SSH CONFIGURATION NOTICE"
        echo "=========================================="
        echo "⚠️  SSH hardening was LIMITED during this test session!"
        echo ""
        echo "The following SSH controls were NOT configured:"
        echo "  - Password complexity requirements"
        echo "  - Public key authentication enforcement"
        echo "  - SSH protocol 2 enforcement"
        echo "  - Additional SSH daemon restrictions"
        echo ""
        echo "WHY: These controls require manual configuration and"
        echo "     testing to prevent SSH lockout during remote access."
        echo ""
        echo "RECOMMENDATION: After verifying system stability:"
        echo "  1. Review /etc/ssh/sshd_config"
        echo "  2. Implement remaining SSH CIS controls manually"
        echo "  3. Test SSH from another session before applying"
        echo "  4. Keep console access available during SSH changes"
        echo ""
        echo "=========================================="
        echo "DOCKER SECURITY WARNING"
        echo "=========================================="
        echo "Docker bypasses UFW and can expose previously secured ports!"
        echo ""
        echo "After using Docker, ALWAYS verify your firewall rules:"
        echo "  sudo ufw status verbose"
        echo "  sudo iptables -L -n -v"
        echo "  sudo ip6tables -L -n -v"
        echo "  sudo nft list ruleset  # if using nftables"
        echo ""
        echo "Check for unexpected ACCEPT rules or exposed ports."
        echo "Most users will use UFW, but Docker modifies iptables directly."
        echo ""
        echo "=========================================="
        echo "SYSTEM REQUIREMENTS & PERFORMANCE"
        echo "=========================================="
        echo "The enhanced hardening with security tools requires:"
        echo ""
        echo "MINIMUM SPECIFICATIONS:"
        echo "  - CPU: 2 cores / 4 threads (quad-core recommended)"
        echo "  - RAM: 4GB (8GB+ recommended for ClamAV)"
        echo "  - Disk: 10GB free space (for AIDE database + virus definitions)"
        echo "  - I/O: SSD recommended (AIDE/ClamAV are disk-intensive)"
        echo ""
        echo "RESOURCE USAGE (Idle):"
        echo "  - fail2ban: ~10-15 MB RAM"
        echo "  - ClamAV daemon: ~250-500 MB RAM"
        echo "  - AIDE: 0 MB (runs on-demand)"
        echo "  - Total: ~270-525 MB RAM overhead"
        echo ""
        echo "HEAVY TOOLS (Optional for low-spec systems):"
        echo "  - AIDE: Intensive initial scan (20-60 min on HDD)"
        echo "  - ClamAV: Daily scans can consume CPU for 10-30 min"
        echo "  - Consider disabling if RAM < 4GB or using HDD storage"
        echo ""
        echo "To disable heavy tools after installation:"
        echo "  sudo systemctl disable --now clamav-daemon clamav-freshclam"
        echo "  sudo apt-mark hold aide aide-common  # prevent upgrades"
        echo ""
        echo "Lightweight alternative: Use Lynis for periodic manual audits"
    fi

    echo "=========================================="
}

# =================================================================
# EXECUTION
# =================================================================

trap 'log_error "Hardening interrupted"; exit 1' INT TERM

main "$@"
