#!/bin/bash
# report-generator.sh - Audit Report Generator
# Purpose: Generate formatted audit reports from scan results
# Author: sec-levels Development Team
# Usage: ./report-generator.sh [audit-file] [format]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# =================================================================
# CONFIGURATION
# =================================================================

readonly AUDIT_FILE="${1:-}"
readonly OUTPUT_FORMAT="${2:-markdown}"

# =================================================================
# REPORT GENERATION FUNCTIONS
# =================================================================

generate_markdown_report() {
    local audit_file="$1"
    local output_file="${audit_file%.xml}.md"

    log_info "Generating Markdown report from ${audit_file}"

    if [[ ! -f "${audit_file}" ]]; then
        log_error "Audit file not found: ${audit_file}"
        return 1
    fi

    # Check if xmllint is available
    if ! command -v xmllint >/dev/null 2>&1; then
        log_warn "xmllint not found. Install with: sudo apt install libxml2-utils"
        generate_simple_markdown "${audit_file}" "${output_file}"
        return 0
    fi

    # Parse XML and generate Markdown
    {
        echo "# CIS Compliance Audit Report"
        echo ""
        echo "**Generated:** $(date)"
        echo "**Audit File:** $(basename "${audit_file}")"
        echo ""
        echo "---"
        echo ""

        # Extract basic information from XML
        echo "## Summary"
        echo ""

        # Count pass/fail results
        local pass_count
        local fail_count
        local total_count

        pass_count=$(xmllint --xpath "count(//rule-result[@result='pass'])" "${audit_file}" 2>/dev/null || echo "0")
        fail_count=$(xmllint --xpath "count(//rule-result[@result='fail'])" "${audit_file}" 2>/dev/null || echo "0")
        total_count=$(xmllint --xpath "count(//rule-result)" "${audit_file}" 2>/dev/null || echo "0")

        echo "- **Total Checks:** ${total_count}"
        echo "- **Passed:** ${pass_count}"
        echo "- **Failed:** ${fail_count}"

        if [[ ${total_count} -gt 0 ]]; then
            local compliance_pct
            compliance_pct=$(awk "BEGIN {printf \"%.1f\", (${pass_count}/${total_count})*100}")
            echo "- **Compliance Rate:** ${compliance_pct}%"
        fi

        echo ""
        echo "---"
        echo ""

        echo "## Details"
        echo ""
        echo "For detailed results, open the HTML report:"
        echo ""
        echo "\`\`\`"
        echo "${audit_file%.xml}.html"
        echo "\`\`\`"
        echo ""

    } > "${output_file}"

    log_success "Markdown report generated: ${output_file}"
    echo "${output_file}"
}

generate_simple_markdown() {
    local audit_file="$1"
    local output_file="$2"

    log_info "Generating simple Markdown report (xmllint not available)"

    {
        echo "# CIS Compliance Audit Report"
        echo ""
        echo "**Generated:** $(date)"
        echo "**Audit File:** $(basename "${audit_file}")"
        echo ""
        echo "---"
        echo ""
        echo "## Summary"
        echo ""
        echo "XML parsing tools not available. Install libxml2-utils for detailed reports:"
        echo ""
        echo "\`\`\`bash"
        echo "sudo apt install libxml2-utils"
        echo "\`\`\`"
        echo ""
        echo "## Raw Audit Data"
        echo ""
        echo "View the HTML report for detailed results:"
        echo ""
        echo "\`\`\`"
        echo "${audit_file%.xml}.html"
        echo "\`\`\`"
        echo ""
    } > "${output_file}"

    log_success "Simple Markdown report generated: ${output_file}"
}

generate_json_report() {
    local audit_file="$1"
    local output_file="${audit_file%.xml}.json"

    log_info "Generating JSON report from ${audit_file}"

    if [[ ! -f "${audit_file}" ]]; then
        log_error "Audit file not found: ${audit_file}"
        return 1
    fi

    # Check if xmllint and jq are available
    if ! command -v xmllint >/dev/null 2>&1; then
        log_error "xmllint not found. Install with: sudo apt install libxml2-utils"
        return 1
    fi

    # Generate basic JSON structure
    {
        echo "{"
        echo "  \"generated\": \"$(date -Iseconds)\","
        echo "  \"audit_file\": \"$(basename "${audit_file}")\","
        echo "  \"summary\": {"
        echo "    \"total_checks\": $(xmllint --xpath "count(//rule-result)" "${audit_file}" 2>/dev/null || echo "0"),"
        echo "    \"passed\": $(xmllint --xpath "count(//rule-result[@result='pass'])" "${audit_file}" 2>/dev/null || echo "0"),"
        echo "    \"failed\": $(xmllint --xpath "count(//rule-result[@result='fail'])" "${audit_file}" 2>/dev/null || echo "0")"
        echo "  },"
        echo "  \"note\": \"Full report available in HTML format\""
        echo "}"
    } > "${output_file}"

    log_success "JSON report generated: ${output_file}"
    echo "${output_file}"
}

generate_text_summary() {
    local audit_file="$1"
    local output_file="${audit_file%.xml}.txt"

    log_info "Generating text summary from ${audit_file}"

    if [[ ! -f "${audit_file}" ]]; then
        log_error "Audit file not found: ${audit_file}"
        return 1
    fi

    {
        echo "=========================================="
        echo "CIS Compliance Audit Report"
        echo "=========================================="
        echo ""
        echo "Generated: $(date)"
        echo "Audit File: $(basename "${audit_file}")"
        echo ""

        if command -v xmllint >/dev/null 2>&1; then
            echo "Summary:"
            echo "  Total Checks: $(xmllint --xpath "count(//rule-result)" "${audit_file}" 2>/dev/null || echo "0")"
            echo "  Passed: $(xmllint --xpath "count(//rule-result[@result='pass'])" "${audit_file}" 2>/dev/null || echo "0")"
            echo "  Failed: $(xmllint --xpath "count(//rule-result[@result='fail'])" "${audit_file}" 2>/dev/null || echo "0")"
        else
            echo "Install libxml2-utils for detailed summaries"
        fi

        echo ""
        echo "=========================================="
        echo "For detailed results, view the HTML report:"
        echo "${audit_file%.xml}.html"
        echo "=========================================="

    } > "${output_file}"

    log_success "Text summary generated: ${output_file}"
    echo "${output_file}"
}

# =================================================================
# MAIN LOGIC
# =================================================================

main() {
    log_init

    echo "=========================================="
    echo "sec-levels Report Generator"
    echo "=========================================="
    echo ""

    # Validate inputs
    if [[ -z "${AUDIT_FILE}" ]]; then
        log_error "Usage: $0 <audit-file> [format]"
        echo ""
        echo "Formats: markdown (default), json, text"
        echo ""
        echo "Example:"
        echo "  $0 /path/to/audit-results.xml markdown"
        exit 1
    fi

    if [[ ! -f "${AUDIT_FILE}" ]]; then
        log_error "Audit file not found: ${AUDIT_FILE}"
        exit 1
    fi

    log_info "Input file: ${AUDIT_FILE}"
    log_info "Output format: ${OUTPUT_FORMAT}"
    echo ""

    # Generate report based on format
    case "${OUTPUT_FORMAT}" in
        markdown|md)
            generate_markdown_report "${AUDIT_FILE}"
            ;;
        json)
            generate_json_report "${AUDIT_FILE}"
            ;;
        text|txt)
            generate_text_summary "${AUDIT_FILE}"
            ;;
        html)
            log_info "HTML report already generated by OpenSCAP: ${AUDIT_FILE%.xml}.html"
            ;;
        *)
            log_error "Unsupported format: ${OUTPUT_FORMAT}"
            echo "Supported formats: markdown, json, text, html"
            exit 1
            ;;
    esac

    echo ""
    log_success "Report generation complete!"
}

# =================================================================
# EXECUTION
# =================================================================

trap 'log_error "Report generation interrupted"; exit 1' INT TERM

main "$@"
