#!/bin/bash
# audit.sh - CIS Benchmark Audit Script
# Purpose: Audit Ubuntu 24.04 LTS system against CIS benchmarks
# Author: sec-levels Development Team
# Usage: ./audit.sh [level1|level2|custom] [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# =================================================================
# CONFIGURATION
# =================================================================

readonly PROFILE="${1:-level1}"
readonly OUTPUT_DIR="${2:-${SCRIPT_DIR}/../reports}"
# shellcheck disable=SC2155
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# =================================================================
# OPENSCAP AUDIT
# =================================================================

run_openscap_audit() {
    log_info "Running OpenSCAP CIS audit for profile: ${PROFILE}"

    local scap_content="/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml"
    local oscap_profile="xccdf_org.ssgproject.content_profile_cis_${PROFILE}_server"
    local results_file="${OUTPUT_DIR}/audit-results-${PROFILE}-${TIMESTAMP}.xml"
    local report_file="${OUTPUT_DIR}/audit-report-${PROFILE}-${TIMESTAMP}.html"

    if [[ ! -f "${scap_content}" ]]; then
        log_error "SCAP content not found: ${scap_content}"
        log_error "Install with: sudo apt install scap-security-guide"
        return 1
    fi

    log_info "SCAP content: ${scap_content}"
    log_info "Profile: ${oscap_profile}"
    log_info "Output directory: ${OUTPUT_DIR}"

    # Run OpenSCAP evaluation
    sudo oscap xccdf eval \
        --profile "${oscap_profile}" \
        --results "${results_file}" \
        --report "${report_file}" \
        "${scap_content}" || {
            local exit_code=$?
            if [[ ${exit_code} -eq 2 ]]; then
                log_warn "OpenSCAP completed with findings (exit code 2 - expected for non-compliant systems)"
            else
                log_error "OpenSCAP failed with exit code: ${exit_code}"
                return 1
            fi
        }

    log_success "OpenSCAP audit complete"
    log_info "Results (XML): ${results_file}"
    log_info "Report (HTML): ${report_file}"

    # Display summary
    echo ""
    echo "=========================================="
    echo "AUDIT SUMMARY"
    echo "=========================================="
    echo "Profile: ${PROFILE}"
    echo "Results: ${results_file}"
    echo "HTML Report: ${report_file}"
    echo ""
    echo "To view the report, open:"
    echo "  file://${report_file}"
    echo "=========================================="
}

# =================================================================
# MANUAL AUDIT (Fallback if OpenSCAP not available)
# =================================================================

run_manual_audit() {
    log_info "Running manual CIS audit checks"

    local report_file="${OUTPUT_DIR}/manual-audit-${PROFILE}-${TIMESTAMP}.txt"

    {
        echo "=========================================="
        echo "sec-levels Manual CIS Audit"
        echo "=========================================="
        echo "Profile: ${PROFILE}"
        echo "Date: $(date)"
        echo "Kernel: $(get_kernel_version) ($(detect_kernel_type))"
        echo "=========================================="
        echo ""

        # SSH Configuration Checks
        echo "[CHECK] SSH Configuration"
        if [[ -f /etc/ssh/sshd_config ]]; then
            echo "  PermitRootLogin: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config || echo 'Not set')"
            echo "  PasswordAuthentication: $(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'Not set')"
            echo "  PermitEmptyPasswords: $(grep -E '^PermitEmptyPasswords' /etc/ssh/sshd_config || echo 'Not set')"
        else
            echo "  ERROR: /etc/ssh/sshd_config not found"
        fi
        echo ""

        # Firewall Status
        echo "[CHECK] Firewall Status"
        if command -v ufw >/dev/null 2>&1; then
            echo "  UFW Status: $(sudo ufw status | head -n1)"
        else
            echo "  UFW: Not installed"
        fi
        echo ""

        # Kernel Parameters
        echo "[CHECK] Kernel Security Parameters"
        echo "  kernel.randomize_va_space: $(sysctl -n kernel.randomize_va_space 2>/dev/null || echo 'Not set')"
        echo "  net.ipv4.tcp_syncookies: $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 'Not set')"
        echo "  net.ipv4.conf.all.send_redirects: $(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null || echo 'Not set')"
        echo ""

        # AppArmor Status
        echo "[CHECK] AppArmor Status"
        if command -v aa-status >/dev/null 2>&1; then
            sudo aa-status --enabled && echo "  AppArmor: Enabled" || echo "  AppArmor: Disabled"
        else
            echo "  AppArmor: Not installed"
        fi
        echo ""

        # File Permissions
        echo "[CHECK] Critical File Permissions"
        echo "  /etc/passwd: $(stat -c '%a %U:%G' /etc/passwd)"
        echo "  /etc/shadow: $(stat -c '%a %U:%G' /etc/shadow)"
        echo "  /etc/group: $(stat -c '%a %U:%G' /etc/group)"
        echo ""

        echo "=========================================="
        echo "Manual audit complete"
        echo "For full CIS compliance, install OpenSCAP:"
        echo "  sudo apt install libopenscap8 openscap-scanner scap-security-guide"
        echo "=========================================="

    } | sudo tee "${report_file}"

    log_success "Manual audit complete: ${report_file}"
}

# =================================================================
# MAIN AUDIT LOGIC
# =================================================================

main() {
    log_init

    echo "=========================================="
    echo "sec-levels CIS Compliance Audit"
    echo "=========================================="
    echo "Profile: ${PROFILE}"
    echo "Output: ${OUTPUT_DIR}"
    echo "=========================================="
    echo ""

    # Validate inputs
    validate_profile "${PROFILE}" || error_exit "Invalid profile: ${PROFILE}"

    # Check system compatibility
    check_ubuntu_version || log_warn "Ubuntu version compatibility warning"

    # Detect kernel
    local kernel_type
    kernel_type=$(detect_kernel_type)
    log_info "Kernel detected: $(get_kernel_version) (${kernel_type})"

    # Create output directory
    sudo mkdir -p "${OUTPUT_DIR}"

    # Run audit based on OpenSCAP availability
    if check_openscap && check_scap_content; then
        run_openscap_audit
    else
        log_warn "OpenSCAP not available, running manual audit"
        run_manual_audit
    fi

    log_success "Audit complete! Reports in: ${OUTPUT_DIR}"
}

# =================================================================
# EXECUTION
# =================================================================

trap 'log_error "Audit interrupted"; exit 1' INT TERM

main "$@"
