# Debian Reproducibility Verification System - Design

## Executive Summary

The system verifies that official Debian Docker images rebuild bit-for-bit from source. It demonstrates supply chain integrity through automated cross-platform verification and maintains public visibility of reproducibility status.

## System Goals

### Primary Objectives
- Verify official Debian Docker images reproduce from source
- Provide independent verification on multiple platforms
- Detect upstream changes and verify automatically
- Display real-time and historical status publicly
- Support all Debian architectures and active suites

### Design Principles
- **Deterministic**: Identical inputs produce identical outputs
- **Transparent**: All results remain publicly accessible
- **Efficient**: Verification runs only when necessary
- **Portable**: System works locally and in CI/CD environments

## Architecture

### Verification Engine

Modular shell scripts provide:
- Common utilities for logging, timing, and error handling
- Official parameter retrieval from upstream repositories
- Build orchestration for single or parallel execution
- Checksum comparison between local and official builds
- JSON report and badge generation
- Environment capture for debugging

### Build Platforms

**Local Execution**
- One command starts verification
- Automatic QEMU configuration for cross-architecture builds
- Parallel suite builds with CPU-based concurrency
- Support for Docker Community/Desktop, Colima, and OrbStack

**GitHub Actions**
- Smart verification triggered by upstream changes
- Matrix builds across architectures
- Native ARM runners for arm64/armhf
- QEMU emulation for i386/ppc64el
- Registry caching via GitHub Container Registry

**Google Cloud Build**
- Independent platform for cross-validation
- High-performance compute resources
- Artifact storage with lifecycle management
- Keyless authentication via Workload Identity Federation

### Debuerreotype Integration

The official Debian image builder requires:
- Fixed version for consistency
- `SYS_ADMIN` capability for chroot operations
- Exact `SOURCE_DATE_EPOCH` timestamp
- Snapshot.debian.org for package version locking

### Public Dashboard

**Location:** `https://sheurich.github.io/debian-repro/`

GitHub Pages hosts:
- Reproducibility status matrix
- 30-day historical trends
- Architecture breakdowns
- Status badges
- Mobile-responsive interface

**Configuration:** GitHub Pages must be configured to serve from the `/dashboard` directory on the main branch. The dashboard automatically updates after each CI run via the `update-dashboard` workflow job.

## Verification Process

### Parameter Acquisition
1. Clone architecture-specific branch from official repository
2. Extract serial number and epoch timestamp
3. Construct snapshot.debian.org URL
4. Retrieve SHA256 checksums

### Build Execution
1. Create Debuerreotype Docker image
2. Execute build with exact parameters
3. Generate rootfs tarballs

### Verification
1. Compute SHA256 of local artifacts
2. Compare with official checksums
3. Report results per suite
4. Aggregate across architectures

### Reporting
1. Generate JSON reports
2. Update status badges
3. Append historical data
4. Refresh dashboard

## Cross-Platform Strategy

### Platform Comparison

The system builds on GitHub Actions and Google Cloud Build daily. It compares checksums to verify platform-independent reproducibility.

### Architecture Support

| Architecture | GitHub Runner      | Cloud Build | Emulation |
|-------------|---------------------|-------------|-----------|
| amd64       | ubuntu-24.04        | Native      | No        |
| arm64       | ubuntu-24.04-arm    | QEMU        | No        |
| armhf       | ubuntu-24.04-arm    | QEMU        | No        |
| i386        | ubuntu-24.04 + QEMU | QEMU        | Yes       |
| ppc64el     | ubuntu-24.04 + QEMU | QEMU        | Yes       |

### Smart Verification

The system monitors official artifacts every 4 hours. It triggers builds only when detecting changes, tracking state to prevent redundant verification.

### Daily Validation

Each day the system:
1. Builds with current timestamp on both platforms
2. Compares checksums between platforms
3. Tracks platform-specific success rates
4. Updates cross-platform match percentage

## Infrastructure

### Repository Structure
```
/
├── .github/workflows/  # CI/CD workflows
├── scripts/            # Verification scripts
├── tests/              # Test suites
├── docs/               # Documentation guides
├── dashboard/          # Web dashboard (GitHub Pages)
│   ├── badges/         # Status endpoints
│   ├── data/           # Historical data
│   ├── index.html      # Dashboard interface
│   ├── script.js       # Dashboard logic
│   └── style.css       # Dashboard styling
├── cloudbuild.yaml     # Cloud Build config
└── verify-local.sh     # Local entry point
```

### Google Cloud Resources
- Service account with minimal permissions
- Workload Identity Federation for keyless auth
- Cloud Build for automated execution
- Cloud Storage with 30-day retention

### Security Model
- Keyless authentication via OIDC
- Least-privilege IAM roles
- Input validation on all parameters
- Pinned dependencies

## Quality Assurance

### Testing
- Unit tests validate individual functions
- Integration tests verify workflows
- BATS framework tests shell scripts
- CI runs tests on every change

### Code Quality
- Shellcheck analyzes scripts
- Yamllint validates YAML
- Scripts exit on undefined variables
- Structured logging maintains consistency

## Monitoring

### Metrics
- Reproducibility percentage
- Build duration by architecture
- Verification frequency
- Cross-platform match rate

### Visualization
- Public status page
- Historical trends
- Architecture status
- Badge endpoints

### Alerting
- Build failures trigger notifications
- Reproducibility degradation generates warnings
- Stale data produces alerts

## Performance

### Optimization
- Docker buildx caches layers
- Shallow git clones reduce transfer
- Parallel builds utilize CPU cores
- Tmpfs accelerates I/O operations

### Resource Management
- Architecture-specific runner selection
- High-CPU machines for Cloud Build
- 30-day data retention
- Automatic cleanup policies

## Extensibility

### Adding Architectures
1. Update architecture mappings
2. Configure runners and emulation
3. Add to matrix generation
4. Update documentation

### Adding Suites
The system automatically supports new suites when they appear in the official repository.

### Integration Points
- JSON reports enable programmatic access
- Shields.io badges provide status indicators
- GitHub Actions outputs allow workflow chaining
- GCS artifacts support external analysis

## Technical Specifications

### Docker Requirements
- Capabilities: Add `SYS_ADMIN`, drop `SETFCAP`
- Security: Unconfined seccomp and AppArmor
- Tmpfs: `/tmp:dev,exec,suid,noatime`
- Environment: `TZ=UTC`, exact `SOURCE_DATE_EPOCH`

### Critical Parameters
- `SOURCE_DATE_EPOCH` must match official timestamp exactly
- Architecture names require mapping between Debian and Docker
- Output follows structure: `{serial}/{arch}/{suite}/`
- Official checksums use flat structure per architecture

### Build Isolation
Each build runs in an isolated Docker container with specific security configuration to ensure reproducibility.

## Success Metrics

The system achieves:
- 100% reproducibility for supported combinations
- Daily cross-platform verification agreement
- 4-hour detection of upstream changes
- 10-minute local verification
- 99.9% dashboard availability

## Design Rationale

The design prioritizes:

1. **Automation** - Smart verification reduces manual intervention
2. **Transparency** - Simple formats and static dashboards
3. **Security** - Keyless authentication despite setup complexity
4. **Correctness** - Exact reproduction over speed
5. **Modularity** - Composable scripts enable flexibility

The implementation progresses toward these goals with core verification complete and advanced features in development.
