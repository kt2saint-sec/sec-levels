#!/bin/bash
# rollback.sh - Rollback Hardening Changes
# Purpose: Restore system configuration to pre-hardening state
# Author: sec-levels Development Team
# Usage: ./rollback.sh [backup-directory]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# =================================================================
# CONFIGURATION
# =================================================================

RESTORE_FROM_DIR="${1:-}"

# =================================================================
# ROLLBACK FUNCTIONS
# =================================================================

restore_files() {
    local backup_path="$1"

    log_info "Restoring files from: ${backup_path}"

    # Find all backed up files
    local file_count=0
    while IFS= read -r -d '' backup_file; do
        # Extract original path from backup structure
        # shellcheck disable=SC2295
        local relative_path="${backup_file#${backup_path}/}"
        local original_path="/${relative_path}"

        log_info "Restoring: ${original_path}"

        # Create parent directory if needed
        sudo mkdir -p "$(dirname "${original_path}")"

        # Restore file with original permissions
        sudo cp -a "${backup_file}" "${original_path}"

        ((file_count++))
    done < <(find "${backup_path}" -type f -print0)

    log_success "Restored ${file_count} files"
}

restore_services() {
    log_info "Restarting affected services..."

    # Restart services that may have been modified
    local services=(
        "sshd"
        "ufw"
        "apparmor"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            log_info "Restarting service: ${service}"
            sudo systemctl restart "${service}" || log_warn "Failed to restart ${service}"
        fi
    done
}

reload_sysctl() {
    log_info "Reloading sysctl parameters..."

    # Reload all sysctl configurations
    sudo sysctl --system || log_warn "Some sysctl parameters failed to reload"
}

# =================================================================
# MAIN ROLLBACK LOGIC
# =================================================================

main() {
    log_init
    require_root

    echo "=========================================="
    echo "sec-levels Rollback Utility"
    echo "=========================================="
    echo ""

    # Validate backup directory
    if [[ -z "${RESTORE_FROM_DIR}" ]]; then
        log_error "Usage: $0 <backup-directory>"
        echo ""
        echo "Available backups:"
        list_backups
        exit 1
    fi

    validate_file_path "${RESTORE_FROM_DIR}" || error_exit "Invalid backup path"

    if [[ ! -d "${RESTORE_FROM_DIR}" ]]; then
        log_error "Backup directory not found: ${RESTORE_FROM_DIR}"
        echo ""
        echo "Available backups:"
        list_backups
        exit 1
    fi

    # Display backup information
    echo "Backup directory: ${RESTORE_FROM_DIR}"
    echo "Backup created: $(basename "${RESTORE_FROM_DIR}")"
    echo ""

    # Count files to be restored
    local file_count
    file_count=$(find "${RESTORE_FROM_DIR}" -type f | wc -l)
    echo "Files to restore: ${file_count}"
    echo ""

    # Confirmation prompt
    echo "WARNING: This will restore system configuration from backup."
    echo "Current configuration will be overwritten."
    echo ""

    if ! confirm "Continue with rollback?" "n"; then
        error_exit "Rollback aborted by user"
    fi

    echo ""
    log_info "Starting rollback..."

    # Perform rollback
    restore_files "${RESTORE_FROM_DIR}"
    reload_sysctl
    restore_services

    echo ""
    echo "=========================================="
    log_success "Rollback complete!"
    echo "=========================================="
    echo ""
    echo "IMPORTANT:"
    echo "  - Review restored configuration"
    echo "  - Test system functionality"
    echo "  - Some changes may require a reboot"
    echo ""
    echo "Backup preserved at: ${RESTORE_FROM_DIR}"
    echo "=========================================="
}

# =================================================================
# EXECUTION
# =================================================================

trap 'log_error "Rollback interrupted"; exit 1' INT TERM

main "$@"
