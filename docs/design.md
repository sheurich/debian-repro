# Debian Reproducibility Verification System - Design

## Executive Summary

The system detects supply chain attacks by proving official Debian Docker images rebuild bit-for-bit from source. Independent cryptographic verification across multiple platforms protects millions of containers relying on Debian base images.

## System Goals

### Mission
Verify continuously that official Debian Docker images reproduce bit-for-bit from source, providing tamper-evidence for the software supply chain.

### Primary Objectives

#### Security Objectives
- **Detect** unauthorized modifications through checksum mismatches
- **Verify** cryptographically that images match their source
- **Alert** on reproducibility failures within 4 hours

#### Trust Objectives
- **Eliminate** single points of trust through multi-platform builds
- **Require** consensus from 2+ independent CI systems
- **Publish** all verification results publicly in real-time

#### Coverage Objectives
- **Support** all Debian architectures (amd64, arm64, armhf, i386, ppc64el, s390x)
- **Cover** all active Debian suites (stable, testing, unstable, oldstable)
- **Monitor** continuously with weekly scheduled verification

### Secondary Objectives

#### Daily Time-Locked Builds
- **Produce** daily base images for immediate consumption
- **Detect** drift independent of official release cadence
- **Build** at midnight UTC with consistent epoch timestamps

#### Enhanced Verification
- **Cross-validate** with both Debuerreotype and mmdebstrap toolchains
- **Expand** validation through GitLab CI and standalone validators
- **Support** community-operated verification nodes

### Design Principles
- **Deterministic**: Identical inputs produce identical outputs
- **Transparent**: All results remain publicly accessible
- **Efficient**: Verify only when upstream changes
- **Portable**: Works locally and in CI/CD environments

## Threat Model

### What This System Defends Against

#### Supply Chain Attacks We Detect
- **Compromised Build Infrastructure**: Malicious modifications during official builds
- **Registry Tampering**: Images modified between build and distribution
- **Backdoor Injection**: Unauthorized code added to base images
- **Package Substitution**: Legitimate packages replaced with malicious ones
- **Build Process Manipulation**: Build tool changes altering output
- **Toolchain Compromise**: Backdoored Debuerreotype detected via mmdebstrap
- **Single-CI Compromise**: Malicious CI platform detected via consensus failure

#### Attack Scenarios Detected
1. **Targeted Attacks**: Nation-state actors compromising specific Debian builds
2. **Insider Threats**: Malicious maintainers injecting backdoors
3. **Infrastructure Compromise**: Docker Hub or build server breaches
4. **Man-in-the-Middle**: Image substitution during distribution

### What This System Does NOT Defend Against

#### Out of Scope
- **Upstream Source Compromise**: Malicious code in legitimate Debian packages
- **Compiler Backdoors**: Ken Thompson-style compiler attacks
- **Hardware Tampering**: CPU or firmware-level modifications
- **Zero-Day Vulnerabilities**: Unpatched security flaws in legitimate software

### Detection Capabilities

#### How Tampering Is Revealed
- **Checksum Mismatch**: Modifications break SHA256 verification
- **Cross-Platform Divergence**: Tampering affects single platforms
- **Temporal Anomalies**: Unexpected changes between verifications
- **Pattern Disruption**: Selective architecture or suite tampering
- **Toolchain Disagreement**: Debuerreotype and mmdebstrap differ
- **Consensus Failure**: CI systems fail 2-of-N threshold

#### Response to Detection
When reproducibility fails, the system:
1. Immediately fails the CI/CD build with detailed error logs
2. Updates public dashboard showing which images cannot be verified
3. Provides forensic data for investigation (checksums, build logs, parameters)
4. Enables rapid triage by comparing multiple platforms and architectures

### Trust Assumptions

This system requires trust in:
- **Debian Source Packages**: We verify the build process, not package contents
- **Cryptographic Functions**: SHA256 must remain cryptographically secure
- **Build Environment**: Our verification infrastructure must be secure

This system reduces trust requirements through:
- **Dual-Toolchain Verification**: Both Debuerreotype and mmdebstrap must agree
- **Multi-Perspective Consensus**: Multiple CI platforms must reach consensus
- **Independent Validators**: Community-operated verification distributes trust

### Why Reproducible Builds Matter for Security

Reproducible builds transform supply chain security from "trust the builder" to "verify the build." Proving official images recreate bit-for-bit from source:
- **Eliminates** silent tampering
- **Distributes** trust across multiple parties
- **Enables** independent verification at scale
- **Creates** forensic audit trails

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

**GitLab CI**
- Additional independent verification perspective
- Matrix builds for parallel suite/architecture combinations
- Container registry for image storage
- Integration with self-hosted runners

**Standalone Validators**
- Independent servers outside CI systems
- Community-operated verification nodes
- Self-hosted CI runners for enhanced trust distribution
- Custom validation environments for specialized testing

### Build Targets

**Official Verification** (Primary)
- Rebuilds official Debian Docker images with exact timestamps
- Triggered by upstream changes in `docker-debian-artifacts` repository
- Verifies bit-for-bit reproducibility against Docker Hub images
- Weekly scheduled verification runs

**Daily Time-Locked Builds** (Secondary)
- Fresh base images built at midnight UTC each day
- Tagged as `<suite>-<YYYYMMDD>-<arch>`
- Provides consumable artifacts for immediate use
- Enables faster drift detection between official releases

### Consensus Mechanism

**Multi-Perspective Validation**
- Minimum 2-of-N agreement threshold for accepting results
- Each CI platform builds independently
- Consensus reducer aggregates and validates results
- Failures trigger detailed investigation with witness evidence

**Dual-Toolchain Verification**
- Both Debuerreotype and mmdebstrap must produce identical outputs
- Toolchain parity checked within each perspective
- Cross-toolchain validation detects tool-specific compromises

### Toolchain Integration

**Debuerreotype**
- Official Debian image builder (v0.16)
- Fixed version for consistency
- `SYS_ADMIN` capability for chroot operations
- Exact `SOURCE_DATE_EPOCH` timestamp
- Snapshot.debian.org for package version locking

**mmdebstrap**
- Independent debootstrap alternative
- Produces bit-identical outputs through shared fixup process
- Same input parameters as Debuerreotype
- Provides toolchain diversity for security

### Public Dashboard

**Location:** `https://sheurich.github.io/debian-repro/`

GitHub Pages hosts:
- Reproducibility status matrix
- 30-day historical trends
- Architecture breakdowns
- Status badges
- Mobile-responsive interface

**Configuration:** GitHub Pages uses GitHub Actions as the publishing source. The `pages.yml` workflow automatically deploys the `/dashboard` directory after each update. The dashboard data updates after each CI run via the `update-dashboard` workflow job.

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

Dashboard updates after each build:

1. **Fetch build results** - Collect verification data from all architectures
2. **Verify checksums** - Compare against official Docker Hub artifacts
   - Requires official artifacts checkout BEFORE processing
   - Step ordering is critical for comparison to work
3. **Generate report** - Create JSON with reproducibility metrics
4. **Update dashboard** - Commit results to dashboard/data/
   - Includes retry logic for handling concurrent commits
   - Backs up, resets, and reapplies changes on conflicts
5. **Deploy to Pages** - Manual trigger required after push
   - GITHUB_TOKEN commits don't auto-trigger workflows
   - Run `gh workflow run pages.yml` manually

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

### Platform Consistency Validation

Each day the system validates platform consistency:
1. Builds with current timestamp on all platforms
2. Compares checksums between platforms
3. Tracks platform-specific success rates
4. Updates cross-platform match percentage

## Daily Builds

### Purpose

Daily time-locked builds serve two functions:
- **Provide** fresh base images for immediate use
- **Detect** drift independent of official releases

### Implementation

**Build Schedule**
- Triggers daily at midnight UTC
- Uses epoch timestamp for consistency
- Builds all suite/architecture combinations
- Publishing requires multi-perspective consensus

**Naming Convention**
- Format: `debian-repro:<suite>-<YYYYMMDD>-<arch>`
- Example: `debian-repro:bookworm-20251109-amd64`
- Distinguishes from official Debian images

**Verification Requirements**
- 2-of-N CI platform consensus required
- Debuerreotype and mmdebstrap must match
- Failed consensus triggers investigation only

**Publishing and Retention**
- OCI images pushed to container registry
- Retention based on usage patterns
- Signed attestations included

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

### Security Metrics
- **Tamper Detection**: < 4 hours from release
- **Supply Chain Coverage**: 100% of official images
- **Cryptographic Verification**: SHA256 for all architectures/suites
- **False Positive Rate**: 0% when uncompromised
- **Toolchain Parity**: > 99% agreement rate
- **Consensus Achievement**: > 95% reach 2-of-N threshold

### Operational Metrics
- **Multi-Platform Consensus**: > 99% agreement across CI systems
- **Daily Build Coverage**: > 95% of suite/architecture combinations
- **Verification Speed**: < 10 minutes locally
- **Dashboard Availability**: > 99.9% uptime
- **Automation Coverage**: 100% hands-free operation

### Trust Metrics
- **Independent Verification**: 2+ platforms required for consensus
- **Toolchain Diversity**: 2 independent build tools
- **Public Auditability**: < 1 minute to publish results
- **Historical Evidence**: 30 days of verification history

## Design Rationale

The design prioritizes:

1. **Supply Chain Security** - Tamper detection drives all architectural decisions
2. **Zero Trust Verification** - Independent platforms prevent single-point compromise
3. **Transparency** - Public dashboards enable community-wide supply chain monitoring
4. **Rapid Detection** - Automated verification catches attacks before widespread deployment
5. **Forensic Capability** - Detailed logs and artifacts support incident investigation

The implementation progresses toward these goals with core verification complete and advanced features in development.
