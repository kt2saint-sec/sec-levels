# CIS Benchmark Control Mapping - sec-levels

**Benchmark:** CIS Ubuntu 24.04 LTS Benchmark
**Version:** [To be determined from research]
**Profile:** Level 1 Server + Level 2 Server
**Last Updated:** 2025-11-02

## Overview

This document maps CIS benchmark controls to implementation status and file locations.

**Legend:**
- ✅ Implemented and tested
- 🚧 In progress
- ⏸️ Deferred (manual control or low priority)
- ❌ Not applicable
- 📋 Researched but not implemented

---

## Control Categories

### 1. Initial Setup
_Controls related to filesystem configuration, software updates, and bootloader_

<!-- Will be populated after research phase -->

### 2. Services
_Controls related to service configuration and hardening_

<!-- Will be populated after research phase -->

### 3. Network Configuration
_Controls related to network parameters and firewall_

<!-- Will be populated after research phase -->

### 4. Logging and Auditing
_Controls related to logging, auditing, and monitoring_

<!-- Will be populated after research phase -->

### 5. Access, Authentication and Authorization
_Controls related to user accounts, sudo, SSH, and PAM_

<!-- Will be populated after research phase -->

### 6. System Maintenance
_Controls related to system updates and file integrity_

<!-- Will be populated after research phase -->

---

## Implementation Priority

### High Priority (Security Critical)
- SSH hardening
- Firewall configuration
- Kernel parameters
- Audit logging
- File permissions

### Medium Priority (Important)
- Service configuration
- User account policies
- Network parameters
- System updates

### Low Priority (Nice-to-have)
- Additional logging
- Advanced audit rules
- Optional security features

---

## Kernel 6.8+ Compatibility Notes

This section will document any kernel-specific considerations:

<!-- Will be populated during implementation -->

---

## Automation Status

### Fully Automated Controls
<!-- List of controls that can be fully automated -->

### Partially Automated Controls
<!-- List of controls requiring some manual steps -->

### Manual Controls
<!-- List of controls that cannot be automated -->

---

## File Location Map

Control implementations are organized as follows:

- **Bash Scripts:** `/scripts/lib/checks.sh`
- **Ansible Tasks:** `/ansible/roles/*/tasks/main.yml`
- **Configuration Templates:** `/config/templates/`
- **Profile Definitions:** `/config/profiles/`

---

_This document will be updated as controls are researched and implemented._
