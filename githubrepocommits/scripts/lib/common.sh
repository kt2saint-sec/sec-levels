#!/bin/bash
# common.sh - Common Functions Library
# Purpose: Shared utility functions for sec-levels scripts
# Author: sec-levels Development Team
# OWASP-compliant security utilities with comprehensive error handling

set -euo pipefail

# =================================================================
# LOGGING FUNCTIONS (Secure, no sensitive data exposure)
# =================================================================

readonly LOG_FILE="/var/log/sec-levels/sec-levels.log"
readonly BACKUP_DIR="/var/backups/sec-levels"

log_init() {
    # Create log directory with restrictive permissions
    if [[ ! -d "$(dirname "${LOG_FILE}")" ]]; then
        sudo mkdir -p "$(dirname "${LOG_FILE}")"
        sudo chmod 750 "$(dirname "${LOG_FILE}")"
    fi

    # Create log file with restrictive permissions
    if [[ ! -f "${LOG_FILE}" ]]; then
        sudo touch "${LOG_FILE}"
        sudo chmod 600 "${LOG_FILE}"
    fi
}

log_info() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] ${message}" | sudo tee -a "${LOG_FILE}"
}

log_warn() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] ${message}" | sudo tee -a "${LOG_FILE}" >&2
}

log_error() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] ${message}" | sudo tee -a "${LOG_FILE}" >&2
}

log_success() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] ${message}" | sudo tee -a "${LOG_FILE}"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] ${message}" | sudo tee -a "${LOG_FILE}"
    fi
}

# =================================================================
# INPUT VALIDATION (OWASP: Prevent command injection)
# =================================================================

validate_profile() {
    local profile="$1"

    # Whitelist validation
    case "${profile}" in
        level1|level2|custom)
            return 0
            ;;
        *)
            log_error "Invalid profile: '${profile}'. Must be level1, level2, or custom"
            return 1
            ;;
    esac
}

validate_file_path() {
    local path="$1"

    # Prevent directory traversal
    if [[ "${path}" =~ \.\. ]]; then
        log_error "Invalid path (directory traversal detected): ${path}"
        return 1
    fi

    # Check if path is absolute
    if [[ "${path:0:1}" != "/" ]]; then
        log_error "Path must be absolute: ${path}"
        return 1
    fi

    return 0
}

validate_boolean() {
    local value="$1"
    local param_name="${2:-value}"

    case "${value}" in
        true|false|yes|no|1|0)
            return 0
            ;;
        *)
            log_error "Invalid ${param_name}: '${value}'. Must be true/false/yes/no/1/0"
            return 1
            ;;
    esac
}

sanitize_input() {
    local input="$1"
    # Remove potentially dangerous characters
    # shellcheck disable=SC2001
    echo "${input}" | sed 's/[^a-zA-Z0-9._-]//g'
}

# =================================================================
# PRIVILEGE CHECKS
# =================================================================

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_sudo_nopasswd() {
    if sudo -n true 2>/dev/null; then
        return 0
    else
        log_warn "sudo requires password (NOPASSWD not configured)"
        return 1
    fi
}

# =================================================================
# SYSTEM DETECTION
# =================================================================

check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found"
        return 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID}" != "ubuntu" ]]; then
        log_error "This script requires Ubuntu (detected: ${ID})"
        return 1
    fi

    if [[ "${VERSION_ID}" != "24.04" ]]; then
        log_warn "This script is designed for Ubuntu 24.04 (detected: ${VERSION_ID})"
        log_warn "Compatibility may vary on other versions"
    fi

    log_info "Detected: ${PRETTY_NAME}"
    return 0
}

get_kernel_version() {
    local kernel_version
    kernel_version=$(uname -r)
    echo "${kernel_version}"
}

detect_kernel_type() {
    local kernel_version
    kernel_version=$(get_kernel_version)

    # Extract major.minor version (e.g., 6.8, 6.11, 6.14)
    local kernel_major_minor
    if [[ "${kernel_version}" =~ ^([0-9]+\.[0-9]+) ]]; then
        kernel_major_minor="${BASH_REMATCH[1]}"
    else
        echo "unknown"
        return
    fi

    # Detect kernel type (GA, HWE, OEM, or generic)
    if [[ "${kernel_version}" =~ -oem$ ]]; then
        echo "${kernel_major_minor}-oem"
    elif [[ "${kernel_version}" == *"-generic" ]]; then
        # Determine if GA or HWE based on version
        case "${kernel_major_minor}" in
            6.8)
                echo "6.8-ga"
                ;;
            6.11|6.14|6.1[5-9]|6.2[0-9])
                echo "${kernel_major_minor}-hwe"
                ;;
            *)
                echo "${kernel_major_minor}-generic"
                ;;
        esac
    else
        echo "${kernel_major_minor}-generic"
    fi
}

is_kernel_compatible() {
    local kernel_version
    kernel_version=$(get_kernel_version)

    local kernel_type
    kernel_type=$(detect_kernel_type)

    # Extract major.minor for numeric comparison
    local kernel_major_minor
    if [[ "${kernel_version}" =~ ^([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"

        # Check if kernel is in supported range (6.8 through 6.14+)
        if [[ "${major}" -eq 6 ]] && [[ "${minor}" -ge 8 ]] && [[ "${minor}" -le 20 ]]; then
            log_info "Detected compatible kernel: ${kernel_version} (${kernel_type})"
            return 0
        fi
    fi

    # Kernel outside tested range - warn and prompt user
    log_warn "=================================="
    log_warn "UNTESTED KERNEL DETECTED"
    log_warn "=================================="
    log_warn "Kernel: ${kernel_version}"
    log_warn "Type: ${kernel_type}"
    log_warn ""
    log_warn "This script has been tested on:"
    log_warn "  - Ubuntu 24.04 LTS (Noble)"
    log_warn "  - Kernel versions 6.8.x through 6.14.x"
    log_warn "  - GA, HWE, and OEM kernels"
    log_warn ""
    log_warn "Your kernel is outside the tested range."
    log_warn "The script may work, but compatibility is not guaranteed."
    log_warn "=================================="

    # Prompt user to continue
    if [[ "${FORCE:-false}" != "true" ]]; then
        local response
        read -r -p "Continue anyway? (y/N) " response
        case "${response}" in
            [yY][eE][sS]|[yY])
                log_warn "User chose to proceed with untested kernel"
                return 0
                ;;
            *)
                log_error "Aborted by user"
                return 1
                ;;
        esac
    else
        log_warn "FORCE mode enabled, proceeding with untested kernel"
        return 0
    fi
}

# =================================================================
# BACKUP MANAGEMENT
# =================================================================

create_backup() {
    local file_to_backup="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${BACKUP_DIR}/${timestamp}"

    if [[ ! -f "${file_to_backup}" ]]; then
        log_warn "File does not exist, skipping backup: ${file_to_backup}"
        return 0
    fi

    sudo mkdir -p "${backup_path}"

    # Preserve full path structure in backup
    local relative_path="${file_to_backup#/}"
    local backup_file="${backup_path}/${relative_path}"
    sudo mkdir -p "$(dirname "${backup_file}")"
    sudo cp -a "${file_to_backup}" "${backup_file}"

    log_info "Backed up: ${file_to_backup} → ${backup_file}"
    echo "${backup_path}"
}

create_backup_dir() {
    local dir_to_backup="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${BACKUP_DIR}/${timestamp}"

    if [[ ! -d "${dir_to_backup}" ]]; then
        log_warn "Directory does not exist, skipping backup: ${dir_to_backup}"
        return 0
    fi

    sudo mkdir -p "${backup_path}"

    # Preserve full path structure in backup
    local relative_path="${dir_to_backup#/}"
    local backup_dir="${backup_path}/${relative_path}"
    sudo mkdir -p "$(dirname "${backup_dir}")"
    sudo cp -a "${dir_to_backup}" "${backup_dir}"

    log_info "Backed up directory: ${dir_to_backup} → ${backup_dir}"
    echo "${backup_path}"
}

list_backups() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        echo "No backups found"
        return 1
    fi

    echo "Available backups:"
    # shellcheck disable=SC2012
    ls -1td "${BACKUP_DIR}"/*/ 2>/dev/null | while read -r backup; do
        local timestamp
        timestamp=$(basename "${backup}")
        echo "  ${timestamp}"
    done
}

# =================================================================
# OPENSCAP DETECTION
# =================================================================

check_openscap() {
    if command -v oscap >/dev/null 2>&1; then
        log_info "OpenSCAP found: $(oscap --version | head -n1)"
        return 0
    else
        log_warn "OpenSCAP not found. Install with: sudo apt install libopenscap8 openscap-scanner scap-security-guide"
        return 1
    fi
}

check_scap_content() {
    local scap_content="/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml"

    if [[ -f "${scap_content}" ]]; then
        log_info "SCAP content found: ${scap_content}"
        return 0
    else
        log_warn "SCAP content not found: ${scap_content}"
        log_warn "Install with: sudo apt install scap-security-guide"
        return 1
    fi
}

# =================================================================
# FILE OPERATIONS (SECURE)
# =================================================================

safe_append_line() {
    local file="$1"
    local line="$2"

    validate_file_path "${file}" || return 1

    # Check if line already exists
    if sudo grep -qF "${line}" "${file}" 2>/dev/null; then
        log_debug "Line already exists in ${file}: ${line}"
        return 0
    fi

    # Append line
    echo "${line}" | sudo tee -a "${file}" > /dev/null
    log_debug "Appended to ${file}: ${line}"
}

safe_replace_line() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    validate_file_path "${file}" || return 1

    if [[ ! -f "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi

    # Create backup
    create_backup "${file}"

    # Replace line
    sudo sed -i "s|${pattern}|${replacement}|g" "${file}"
    log_debug "Replaced in ${file}: ${pattern} → ${replacement}"
}

# =================================================================
# SERVICE MANAGEMENT
# =================================================================

disable_service() {
    local service="$1"

    if systemctl is-enabled "${service}" >/dev/null 2>&1; then
        log_info "Disabling service: ${service}"
        sudo systemctl stop "${service}" || log_warn "Failed to stop ${service}"
        sudo systemctl disable "${service}" || log_warn "Failed to disable ${service}"
        sudo systemctl mask "${service}" || log_warn "Failed to mask ${service}"
    else
        log_debug "Service already disabled: ${service}"
    fi
}

enable_service() {
    local service="$1"

    log_info "Enabling service: ${service}"
    sudo systemctl unmask "${service}" 2>/dev/null || true
    sudo systemctl enable "${service}"
    sudo systemctl start "${service}"
}

is_service_running() {
    local service="$1"
    systemctl is-active --quiet "${service}"
}

# =================================================================
# PACKAGE MANAGEMENT
# =================================================================

install_package() {
    local package="$1"

    if dpkg -l | grep -q "^ii  ${package} "; then
        log_debug "Package already installed: ${package}"
        return 0
    fi

    log_info "Installing package: ${package}"
    sudo apt-get update -qq
    sudo apt-get install -y "${package}"
}

remove_package() {
    local package="$1"

    if ! dpkg -l | grep -q "^ii  ${package} "; then
        log_debug "Package not installed: ${package}"
        return 0
    fi

    log_info "Removing package: ${package}"
    sudo apt-get remove -y "${package}"
    sudo apt-get purge -y "${package}"
}

# =================================================================
# COLOR OUTPUT (Optional - only if terminal supports)
# =================================================================

if [[ -t 1 ]]; then
    # shellcheck disable=SC2034
    readonly RED='\033[0;31m'
    # shellcheck disable=SC2034
    readonly GREEN='\033[0;32m'
    # shellcheck disable=SC2034
    readonly YELLOW='\033[0;33m'
    # shellcheck disable=SC2034
    readonly BLUE='\033[0;34m'
    # shellcheck disable=SC2034
    readonly NC='\033[0m' # No Color
else
    # shellcheck disable=SC2034
    readonly RED=''
    # shellcheck disable=SC2034
    readonly GREEN=''
    # shellcheck disable=SC2034
    readonly YELLOW=''
    # shellcheck disable=SC2034
    readonly BLUE=''
    # shellcheck disable=SC2034
    readonly NC=''
fi

# =================================================================
# ERROR HANDLING
# =================================================================

error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "${message}"
    exit "${exit_code}"
}

# =================================================================
# CONFIRMATION PROMPTS
# =================================================================

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi

    local response
    if [[ "${default}" == "y" ]]; then
        read -r -p "${prompt} [Y/n] " response
        response="${response:-y}"
    else
        read -r -p "${prompt} [y/N] " response
        response="${response:-n}"
    fi

    case "${response}" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =================================================================
# EXPORTS
# =================================================================

# Export functions for use in other scripts
export -f log_init log_info log_warn log_error log_success log_debug
export -f validate_profile validate_file_path validate_boolean sanitize_input
export -f require_root check_sudo_nopasswd
export -f check_ubuntu_version get_kernel_version detect_kernel_type is_kernel_compatible
export -f create_backup create_backup_dir list_backups
export -f check_openscap check_scap_content
export -f safe_append_line safe_replace_line
export -f disable_service enable_service is_service_running
export -f install_package remove_package
export -f error_exit confirm
