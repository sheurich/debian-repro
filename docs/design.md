# Debian Reproducibility Verification System - Design

## Executive Summary

We detect supply chain attacks by proving official Debian Docker images rebuild bit-for-bit from source. Independent cryptographic verification across multiple platforms protects millions of containers relying on Debian base images.

## System Goals

### Mission
Verify continuously that official Debian Docker images reproduce bit-for-bit from source, providing tamper-evidence for the software supply chain.

### Primary Objectives

#### Security Objectives
- **Detect** unauthorized modifications through checksum mismatches
- **Verify** cryptographically that images match their source
- **Alert** on reproducibility failures via weekly automated verification

#### Trust Objectives
- **Eliminate** single points of trust through multi-platform builds
- **Require** consensus from 2+ independent CI systems
- **Publish** all verification results publicly in real-time

#### Coverage Objectives
- **Support** Debian architectures: amd64, arm64 (default), plus armhf, i386, ppc64el (manual trigger). s390x explicitly unsupported (not in artifacts repo)
- **Cover** all active Debian suites (stable, testing, unstable, oldstable)
- **Monitor** continuously with weekly scheduled verification for default architectures

### Secondary Objectives (Planned)

#### Daily Time-Locked Builds (Future Work)
- **Produce** daily base images for immediate consumption
- **Detect** drift independent of official release cadence
- **Build** at midnight UTC with consistent epoch timestamps

#### Enhanced Verification (Future Work)
- **Cross-validate** with both Debuerreotype and mmdebstrap toolchains (planned)
- **Expand** validation through GitLab CI and standalone validators (planned)
- **Support** community-operated verification nodes (planned)

### Design Principles
- **Deterministic**: Identical inputs produce identical outputs
- **Transparent**: All results remain publicly accessible
- **Efficient**: Verify only when upstream changes
- **Portable**: Works locally and in CI/CD environments

## Threat Model

### What This System Defends Against

#### Supply Chain Attacks We Detect

*Currently Implemented:*
- **Build Process Tampering**: Detects unauthorized modifications in the official Debuerreotype build process
- **Artifacts Repository Changes**: Identifies unexpected checksum changes in `docker-debian-artifacts`
- **Single-CI Compromise**: Malicious CI platform detected via consensus failure between GitHub Actions and Google Cloud Build
- **Package Substitution**: Changes in package versions affect reproducibility of builds

*Planned (Not Yet Implemented):*
- **Registry Tampering**: Images modified between artifacts repository and Docker Hub (requires Docker Hub registry verification)
- **Toolchain Compromise**: Backdoored Debuerreotype detected via mmdebstrap cross-validation

**Current Limitation**: The `docker-debian-artifacts` repository is our single point of trust. We verify build reproducibility but do not detect tampering between this repository and Docker Hub. Registry verification is planned future work.

#### Attack Scenarios
*Currently Detected:*
1. **Build Process Compromise**: Changes to official build toolchain or parameters
2. **CI Platform Compromise**: Malicious results from single CI system caught by consensus

*Not Currently Detected (Planned):*
1. **Docker Hub Compromise**: Image tampering after publication to registry
2. **Artifacts Repository Compromise**: Requires independent Docker Hub verification
3. **Toolchain-Specific Backdoors**: Requires mmdebstrap cross-validation

### What This System Does NOT Defend Against

#### Out of Scope
- **Upstream Source Compromise**: Malicious code in legitimate Debian packages
- **Compiler Backdoors**: Ken Thompson-style compiler attacks
- **Hardware Tampering**: CPU or firmware-level modifications
- **Zero-Day Vulnerabilities**: Unpatched security flaws in legitimate software

### Detection Capabilities

#### How We Reveal Tampering (Currently Implemented)
- **Checksum Mismatch**: Modifications to artifacts repository break SHA256 verification
- **Cross-Platform Divergence**: Single CI platform compromise detected when platforms disagree
- **Temporal Anomalies**: Unexpected checksum changes in artifacts repository between verifications
- **Consensus Failure**: CI systems fail 2-of-N threshold (GitHub Actions + Google Cloud Build)

#### Planned Detection Capabilities
- **Registry Tampering Detection**: Direct Docker Hub verification to catch post-publication modifications
- **Toolchain Disagreement**: Debuerreotype and mmdebstrap produce different outputs, indicating tool-specific compromise
- **Pattern Disruption**: Selective architecture or suite tampering across multiple verification dimensions

#### Response to Detection
When reproducibility fails, we:
1. Immediately fail the CI/CD build with detailed error logs
2. Update the public dashboard showing which images cannot be verified
3. Provide forensic data for investigation (checksums, build logs, parameters)
4. Enable rapid triage by comparing multiple platforms and architectures

### Trust Assumptions

You must trust:
- **Debian Source Packages**: We verify the build process, not package contents
- **Cryptographic Functions**: SHA256 must remain cryptographically secure
- **Build Environment**: Our verification infrastructure must be secure
- **Artifacts Repository**: The `docker-debian-artifacts` repository is our current single point of trust (Docker Hub verification planned)

We reduce trust requirements through:
- **Multi-Perspective Consensus**: Multiple CI platforms (GitHub Actions and Google Cloud Build) must reach consensus
- **Planned: Dual-Toolchain Verification**: Both Debuerreotype and mmdebstrap must agree (future work)
- **Planned: Independent Validators**: Community-operated verification distributes trust (future work)
- **Planned: Registry Verification**: Direct Docker Hub checks to eliminate artifacts repository as single point of trust

### Why Reproducible Builds Matter for Security

Reproducible builds transform supply chain security from "trust the builder" to "verify the build." Proving official images recreate bit-for-bit from source:
- **Eliminates** silent tampering
- **Distributes** trust across multiple parties
- **Enables** independent verification at scale
- **Creates** forensic audit trails

## Trust Dependencies

This verification system requires trust in several components. Understanding these dependencies helps assess the security model and identify potential compromise vectors.

### Infrastructure Dependencies

**GitHub Actions**
- **Purpose**: Primary CI/CD platform for automated verification
- **Trust Required**: GitHub's infrastructure, runner images, action implementations
- **Mitigation**: Cross-validate results with Google Cloud Build and GitLab CI
- **Risk**: Compromised GitHub could alter build artifacts or verification results
- **Monitoring**: Multi-platform consensus detects single-platform tampering

**Google Cloud Build**
- **Purpose**: Independent verification platform for consensus validation
- **Trust Required**: GCP infrastructure, build environments, artifact storage
- **Mitigation**: Compare checksums with GitHub Actions results
- **Risk**: Compromised GCP could provide false verification results
- **Monitoring**: Consensus validator detects cross-platform disagreements

**GitLab CI**
- **Purpose**: Additional independent verification perspective
- **Trust Required**: GitLab infrastructure, runner environments, container registry
- **Mitigation**: Participate in multi-platform consensus
- **Risk**: Single CI compromise detected through consensus failure
- **Monitoring**: 2-of-N threshold requires multiple platforms to agree

**Standalone Validators**
- **Purpose**: Community-operated verification nodes outside CI systems
- **Trust Required**: Individual operators, self-hosted infrastructure
- **Mitigation**: Distributed trust model - no single operator controls verification
- **Risk**: Malicious validator could report false results (detected by consensus)
- **Monitoring**: Results aggregated with CI platforms for validation

### Build Tool Dependencies

**Debuerreotype**
- **Purpose**: Official Debian Docker image builder
- **Trust Required**: Debuerreotype maintainers, GitHub repository integrity
- **Mitigation**: Pin to specific version (v0.16), cross-validate with mmdebstrap
- **Risk**: Backdoored tool could produce compromised images
- **Monitoring**: Dual-toolchain verification detects tool-specific tampering
- **Version Control**: Git tag verification, SHA verification of cloned repository

**mmdebstrap** (Planned)
- **Purpose**: Independent debootstrap alternative for cross-validation
- **Trust Required**: mmdebstrap maintainers, package integrity
- **Mitigation**: Must produce bit-identical output to Debuerreotype
- **Risk**: Dual compromise less likely than single tool compromise
- **Monitoring**: Toolchain parity checks detect disagreements

### Data Source Dependencies

**snapshot.debian.org**
- **Purpose**: Time-locked Debian package archive for reproducible builds
- **Trust Required**: Debian infrastructure, package archive integrity
- **Mitigation**: Cryptographic verification of downloaded packages
- **Risk**: Compromised archive could serve malicious packages
- **Monitoring**: Multiple verifiers accessing same snapshots detect inconsistencies
- **Verification**: APT secure package signing, GPG verification

**debuerreotype/docker-debian-artifacts**
- **Purpose**: Official source of build parameters and reference checksums
- **Trust Required**: Debian Docker team, GitHub repository integrity
- **Mitigation**: Repository is read-only for us; any tampering fails verification
- **Risk**: Compromised repository could provide incorrect reference checksums
- **Monitoring**: Historical tracking detects unexpected parameter changes
- **Validation**: Smart verification system tracks serial numbers and epoch timestamps

### Container Image Dependencies

**tonistiigi/binfmt**
- **Purpose**: QEMU registration for cross-architecture emulation
- **Trust Required**: Docker official images, Tõnis Tiigi (maintainer)
- **Image Reference**: `tonistiigi/binfmt@sha256:e06789462ac7e2e096b53bfd9e607412426850227afeb1d0f5dfa48a731e0ba5`
- **Mitigation**: Digest pinning prevents tag substitution attacks
- **Risk**: Runs with `--privileged` flag - malicious image could compromise host
- **Security Measures**:
  - User confirmation required before execution (bypass with `SKIP_CONFIRM=true` for CI)
  - Container runs with `--rm` flag and exits immediately
  - Only executed for cross-architecture builds, not for verification itself
  - Periodic digest updates required (manual process to review changes)
- **Alternatives**: System-level QEMU installation, native-architecture builds only

**multiarch/qemu-user-static**
- **Purpose**: Fallback QEMU registration for Linux systems
- **Trust Required**: Multiarch project maintainers, Docker Hub
- **Image Reference**: `multiarch/qemu-user-static@sha256:7ebfd8bcb1f9d95a85e876ef9edc06e84e8a0d7f355a96e8069e1b13eb98c66b`
- **Mitigation**: Digest pinning, used only as fallback on Linux
- **Risk**: Same privileged access concerns as tonistiigi/binfmt
- **Security Measures**: Same as tonistiigi/binfmt

### Registry Dependencies

**Docker Hub**
- **Purpose**: Official Debian image distribution, reference artifact source
- **Trust Required**: Docker Inc., registry infrastructure
- **Mitigation**: Verification system proves images match source code
- **Risk**: Compromised registry detected through checksum mismatches
- **Monitoring**: Our entire system exists to verify Docker Hub integrity

**GitHub Container Registry (GHCR)**
- **Purpose**: Storage for daily time-locked builds (planned)
- **Trust Required**: GitHub infrastructure, attestation signing
- **Mitigation**: Signed attestations, consensus requirement before publishing
- **Risk**: Registry compromise detected through signature verification
- **Monitoring**: Published only after multi-platform consensus

### Privileged Capabilities Requirements

**Why SYS_ADMIN Capability Is Required**

The `SYS_ADMIN` capability is necessary for Debuerreotype's core operations:

1. **chroot Operations**
   - Required to change root directory for isolated filesystem operations
   - Debuerreotype builds Debian rootfs using chroot to create clean environments
   - Without SYS_ADMIN, chroot() system call fails with EPERM

2. **Mount Operations**
   - Required to mount proc, sys, dev filesystems within build environment
   - Necessary for debootstrap to function correctly
   - Enables proper package installation and configuration

3. **Namespace Operations**
   - Required for creating isolated build environments
   - Prevents build artifacts from affecting host system
   - Ensures reproducibility through environment isolation

**Security Configuration**

Docker container security settings for builds:
```bash
docker run \
  --cap-add SYS_ADMIN \     # Required for chroot/mount operations
  --cap-drop SETFCAP \      # Drop unnecessary capability
  --security-opt seccomp=unconfined \    # Allow mount/chroot syscalls
  --security-opt apparmor=unconfined \   # Allow filesystem operations
  --tmpfs /tmp:dev,exec,suid,noatime \   # Fast temporary storage
  ...
```

**Capability Risk Assessment**

- **SYS_ADMIN**: Powerful capability but required for legitimate build operations
- **Mitigation**: Container isolation, read-only host mounts where possible
- **Scope**: Applied only to build containers, not to privileged helper containers
- **Alternatives**: None - chroot is fundamental to debootstrap/Debuerreotype

**Privileged vs Capabilities**

- **Privileged containers** (--privileged): Used only for binfmt/QEMU setup
  - Modifies host kernel settings (binfmt_misc)
  - Runs briefly and exits immediately
  - Requires user confirmation in interactive mode

- **Capability grants** (--cap-add): Used for builds themselves
  - Limited to specific capabilities (SYS_ADMIN)
  - Drops unnecessary capabilities (SETFCAP)
  - Isolated within container namespace

### Trust Reduction Strategies

**Multi-Perspective Consensus**
- Minimum 2-of-N agreement required for accepting results
- Single compromised CI platform detected through consensus failure
- Independent infrastructure reduces single point of failure

**Dual-Toolchain Verification** (Planned)
- Both Debuerreotype and mmdebstrap must produce identical output
- Compromising both tools independently is significantly harder
- Toolchain disagreement triggers immediate investigation

**Digest Pinning**
- Helper containers referenced by immutable SHA256 digests
- Prevents tag substitution attacks
- Requires manual review before digest updates

**Transparent Operation**
- All verification results published in real-time
- Build logs and artifacts available for audit
- Dashboard shows per-platform verification status

**Community Validation**
- Anyone can run verification locally
- Independent validators contribute to consensus
- Distributed trust model prevents central authority compromise

### What You Still Must Trust

Despite mitigation strategies, fundamental trust requirements remain:

1. **Debian Source Packages**: We verify the build process, not package contents
2. **Cryptographic Functions**: SHA256 must remain cryptographically secure
3. **Linux Kernel**: Host kernel must correctly implement isolation
4. **CPU Architecture**: Processor must execute instructions faithfully
5. **Our Verification Scripts**: Open source, but you must review or trust maintainers

The system reduces trust requirements but cannot eliminate them entirely. Reproducible builds shift trust from "the official builder" to "mathematics and independent verification."

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
- Each CI platform builds independently with identical parameters
- Consensus validator workflow aggregates and validates results
- Failures trigger detailed investigation with witness evidence
- Dashboard displays consensus status with platform-level visibility

**Implementation**

*Result Collection* (`scripts/collect-results.sh`)
- Fetches verification reports from GitHub Actions and Google Cloud Build
- Supports GitHub Pages dashboard data and GCS bucket artifacts
- Retrieves results by serial number for specific build comparisons
- Multi-platform collection in single run (fixed in commit 3ba3cbf)
- Exit code 0 on success, non-zero on failures
- Automatic retry and error handling for network failures

*Consensus Validation* (`scripts/compare-platforms.sh`)
- Compares checksums across platforms for each suite/architecture combination
- Determines consensus based on configurable threshold (default: 2 platforms)
- Generates detailed comparison reports with platform-specific results
- Creates witness evidence for disagreements requiring investigation
- Supports both strict mode (all must match) and majority consensus
- Automatic format normalization (fixed in commit 3ba3cbf):
  - GitHub nested format: `.architectures.{arch}.suites.{suite}`
  - GCP array format: `.results[]`
- Exit code 0 when consensus achieved, non-zero on disagreement

*Automated Validation* (`.github/workflows/consensus-validator.yml`)
- Runs weekly after build completion or on-demand via workflow dispatch
- Uses Workload Identity Federation for secure GCP authentication
- Collects results from all configured platforms automatically
- Validates consensus and updates dashboard with agreement status
- Commits consensus reports to repository for historical tracking
- Fails build when consensus cannot be achieved

**Usage Examples**

Manual consensus validation:
```bash
# Collect results from both platforms
./scripts/collect-results.sh \
  --serial 20251020 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# Compare and validate consensus
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --threshold 2 \
  --output consensus-report.json
```

Automated via workflow:
```bash
# Trigger for specific serial
gh workflow run consensus-validator.yml -f serial=20251020

# View results
gh run watch
```

**Status**: Fully operational consensus validation across 2 independent platforms (November 2025)
- GitHub Actions and Google Cloud Build require 2-of-2 agreement
- Tested with 8 suite/architecture combinations
- Achieved 100% consensus in testing
- Both collection and comparison scripts exit with proper codes and generate valid JSON reports

**Dual-Toolchain Verification (Planned)**
- Both Debuerreotype and mmdebstrap must produce identical outputs
- Toolchain parity checked within each perspective
- Cross-toolchain validation detects tool-specific compromises
- *Status: Future work - mmdebstrap integration not yet implemented*

### Toolchain Integration

**Debuerreotype**
- Official Debian image builder (v0.16)
- Fixed version for consistency
- `SYS_ADMIN` capability for chroot operations
- Exact `SOURCE_DATE_EPOCH` timestamp
- Snapshot.debian.org for package version locking

**mmdebstrap (Planned)**
- Independent debootstrap alternative
- Produces bit-identical outputs through shared fixup process
- Same input parameters as Debuerreotype
- Provides toolchain diversity for security
- *Status: Future work - not yet integrated*

### Public Dashboard

**Location:** `https://sheurich.github.io/debian-repro/`

GitHub Pages hosts:
- Reproducibility status matrix
- 30-day historical trends
- Architecture breakdowns
- Status badges
- Mobile-responsive interface

**Configuration:** GitHub Pages uses GitHub Actions as the publishing source. The `pages.yml` workflow automatically deploys the `/dashboard` directory after each update. The `update-dashboard` workflow job updates the dashboard data after each CI run.

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

### Consensus Validation

After individual platform builds complete:

1. **Collect Results** - Gather verification reports from all platforms
   - GitHub Actions (dashboard data or workflow artifacts)
   - Google Cloud Build (GCS bucket artifacts)
   - Normalizes format differences automatically

2. **Compare Checksums** - Validate agreement across platforms
   - Groups results by suite/architecture combination
   - Applies consensus threshold (default: 2-of-N)
   - Generates detailed comparison report

3. **Update Dashboard** - Publish consensus status
   - Consensus rate per suite/architecture
   - Platform-specific verification status
   - Historical consensus trends

4. **Investigation** - On consensus failure
   - Witness evidence with per-platform checksums
   - Build logs from all platforms
   - Environment capture for debugging

## Cross-Platform Strategy

### Platform Comparison

We build on GitHub Actions and Google Cloud Build daily, comparing checksums to verify platform-independent reproducibility.

### Architecture Support

| Architecture | GitHub Runner      | Cloud Build | Emulation |
|-------------|---------------------|-------------|-----------|
| amd64       | ubuntu-24.04        | Native      | No        |
| arm64       | ubuntu-24.04-arm    | QEMU        | No        |
| armhf       | ubuntu-24.04-arm    | QEMU        | No        |
| i386        | ubuntu-24.04 + QEMU | QEMU        | Yes       |
| ppc64el     | ubuntu-24.04 + QEMU | QEMU        | Yes       |

### Smart Verification

We run weekly automated verification on Sundays at 00:00 UTC, with manual triggers available for on-demand verification.

### Platform Consistency Validation

Weekly automated verification validates platform consistency:
1. Build with current timestamp on all platforms
2. Compare checksums between platforms
3. Track platform-specific success rates
4. Update cross-platform match percentage

## Daily Builds (Future Work)

### Purpose

Daily time-locked builds serve two functions:
- **Provide** fresh base images for immediate use
- **Detect** drift independent of official releases

### Implementation (Planned)

**Build Schedule**
- Triggers daily at midnight UTC
- Uses epoch timestamp for consistency
- Builds all suite/architecture combinations
- Publishing requires multi-perspective consensus

**Naming Convention**
- Format: `debian-repro:<suite>-<YYYYMMDD>-<arch>`
- Example: `debian-repro:bookworm-20251109-amd64`
- Distinguishes from official Debian images

**Verification Requirements (Planned)**
- 2-of-N CI platform consensus required
- Debuerreotype and mmdebstrap must match (when dual toolchain is implemented)
- Failed consensus triggers investigation only

**Publishing and Retention**
- OCI images pushed to container registry
- Retention based on usage patterns
- Signed attestations included

*Status: Not yet implemented - weekly verification currently in place*

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
New suites automatically work when they appear in the official repository.

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
- **Tamper Detection**: Weekly automated verification (Sundays at 00:00 UTC)
- **Supply Chain Coverage**: 100% of official images
- **Cryptographic Verification**: SHA256 for all architectures/suites
- **False Positive Rate**: 0% when uncompromised
- **Toolchain Parity**: > 99% agreement rate (Planned - mmdebstrap not yet integrated)
- **Consensus Achievement**: 100% in November 2025 testing (Active: 2-of-2 agreement between GitHub Actions and Google Cloud Build)

### Operational Metrics
- **Multi-Platform Consensus**: > 99% agreement across CI systems (Active: GitHub Actions + Google Cloud Build)
- **Cross-Platform Collection**: Successfully collects from multiple platforms in single run
- **Format Compatibility**: Handles both nested and array JSON formats automatically
- **Daily Build Coverage**: > 95% of suite/architecture combinations
- **Verification Speed**: < 10 minutes locally
- **Dashboard Availability**: > 99.9% uptime
- **Automation Coverage**: 100% hands-free operation

### Trust Metrics
- **Independent Verification**: 2 platforms currently providing consensus (GitHub Actions and Google Cloud Build)
- **Toolchain Diversity**: 2 independent build tools (Planned - currently Debuerreotype only)
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
