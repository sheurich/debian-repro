# Roadmap

Planned features and investigated alternatives.

## Planned

### Docker Hub Registry Verification

Direct comparison of Docker Hub images to artifacts repository checksums.

**Status**: Not started
**Priority**: High
**Impact**: Closes trust gap between artifacts repository and registry

### Daily Builds

Fresh base images at midnight UTC for immediate use and drift detection.

**Status**: Not started
**Priority**: Medium
**Impact**: Faster detection of supply chain issues

### GitLab CI Integration

Add GitLab CI as third independent validation platform.

**Status**: Not started
**Priority**: Medium
**Impact**: Strengthens consensus with additional platform diversity

### Standalone Validators

Community-operated verification nodes for geographic and organizational diversity.

**Status**: Not started
**Priority**: Low
**Impact**: Further decentralizes trust

## Investigated (Not Viable)

### Dual-Toolchain Verification (mmdebstrap)

Cross-verification with mmdebstrap to detect Debuerreotype-specific backdoors.

**Status**: Investigated, not viable
**Finding**: mmdebstrap cannot produce outputs matching Debuerreotype checksums. The tools make incompatible decisions about filesystem ordering and metadata that cannot be reconciled.

**Alternative**: Focus on platform diversity (additional CI systems, community validators) rather than toolchain diversity.
