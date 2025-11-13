# Roadmap

Planned features and enhancements for debian-repro.

## Verification Enhancements

### Docker Hub Registry Verification
Direct comparison of Docker Hub images to artifacts repository to detect registry tampering.

**Status**: Not started
**Priority**: High
**Impact**: Closes trust gap between artifacts repository and Docker Hub

### Dual Toolchain Validation
Cross-verification with mmdebstrap to detect Debuerreotype-specific compromises.

**Status**: Not started
**Priority**: High
**Impact**: Removes single toolchain as point of trust

## Build Capabilities

### Daily Builds
Fresh base images at midnight UTC for immediate use and drift detection.

**Status**: Not started
**Priority**: Medium
**Impact**: Faster detection of supply chain issues

## Multi-Platform Validation

### GitLab CI Integration
Add GitLab CI as third independent validation platform.

**Status**: Not started
**Priority**: Medium
**Impact**: Strengthens consensus validation

### Standalone Validators
Independent servers and self-hosted runners for additional validation perspectives.

**Status**: Not started
**Priority**: Low
**Impact**: Further decentralizes trust
