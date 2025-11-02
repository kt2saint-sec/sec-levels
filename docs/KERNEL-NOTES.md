# Kernel Compatibility Notes - sec-levels

**Target Kernels:** Ubuntu 24.04 LTS (6.8+)
**Last Updated:** 2025-11-02

## Overview

This document tracks kernel-specific considerations for CIS hardening on Ubuntu 24.04 LTS.

---

## Kernel Versions

### Ubuntu 24.04 LTS Default Kernel

**Kernel Version:** 6.8.x
**Status:** Primary target
**Testing:** Required

### Latest LTS Kernel

**Kernel Version:** 6.11.x (or later)
**Status:** Secondary target
**Testing:** Required

---

## Kernel Parameter Compatibility

### sysctl Parameters

Parameters to validate across kernel versions:

<!-- Will be populated during implementation -->

### Deprecated Parameters

Document any parameters that are deprecated in newer kernels:

<!-- Will be populated during testing -->

### New Parameters

Document any new security parameters introduced in kernel 6.8+:

<!-- Will be populated during research -->

---

## Known Issues

### Kernel 6.8 Specific

<!-- Will be documented as discovered -->

### Kernel 6.11+ Specific

<!-- Will be documented as discovered -->

---

## Testing Matrix

| Control | Kernel 6.8 | Kernel 6.11 | Notes |
|---------|------------|-------------|-------|
| TBD     | ⏳         | ⏳          |       |

**Legend:**
- ✅ Tested and working
- ⚠️ Working with warnings
- ❌ Not working
- ⏳ Not yet tested

---

## AppArmor Compatibility

### Kernel 6.8
- AppArmor version: [TBD]
- Profile compatibility: [TBD]

### Kernel 6.11+
- AppArmor version: [TBD]
- Profile compatibility: [TBD]

---

## Audit System (auditd)

### Kernel 6.8
- Audit version: [TBD]
- Rule compatibility: [TBD]

### Kernel 6.11+
- Audit version: [TBD]
- Rule compatibility: [TBD]

---

## Module Loading

### Blacklisted Modules

Document kernel modules that should be blacklisted:

<!-- Will be populated from CIS requirements -->

### Module Signing

Document module signing requirements:

<!-- Will be populated during implementation -->

---

## Boot Parameters

### Required Boot Parameters

Document required kernel boot parameters:

<!-- Will be populated from CIS requirements -->

### Deprecated Boot Parameters

Document deprecated parameters to avoid:

<!-- Will be populated during testing -->

---

## References

- [Ubuntu 24.04 Release Notes](https://wiki.ubuntu.com/NobleNumbat/ReleaseNotes)
- [Linux Kernel 6.8 Release Notes](https://kernelnewbies.org/Linux_6.8)
- Kernel documentation: `/usr/share/doc/linux-doc-*/`

---

_This document will be updated as kernel testing progresses._
