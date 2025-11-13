# Debian Reproducibility Verification System - Design

> **Note**: This document contains the complete design specification. For focused documentation, see:
> - [architecture.md](architecture.md) - System architecture and verification process
> - [security.md](security.md) - Threat model and trust dependencies
> - [roadmap.md](roadmap.md) - Planned features and enhancements

## Executive Summary

We detect supply chain attacks by rebuilding official Debian Docker images bit-for-bit from source. Independent cryptographic verification across multiple platforms protects millions of containers.

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
- **Require** full consensus from all independent CI systems
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

> For complete threat analysis and trust dependencies, see [security.md](security.md).

### Supply Chain Attacks We Detect

*Current:*
- **Build Process Tampering**: Detects modifications in official Debuerreotype build process
- **Artifacts Repository Changes**: Identifies checksum changes in `docker-debian-artifacts`
- **Single-CI Compromise**: Consensus failure reveals malicious CI platform
- **Package Substitution**: Version changes break reproducibility

*Planned:*
- **Registry Tampering**: Direct Docker Hub verification (closes artifacts-to-registry gap)
- **Toolchain Compromise**: mmdebstrap cross-validation detects Debuerreotype backdoors

**Current Limitation**: `docker-debian-artifacts` repository is our single trust point. We verify build reproducibility but miss tampering between repository and Docker Hub.

### Attack Scenarios

*Detected:*
1. **Build Process Compromise**: Toolchain or parameter changes
2. **CI Platform Compromise**: Consensus failure reveals malicious platform

*Not Detected (Planned):*
1. **Docker Hub Compromise**: Image tampering after publication
2. **Artifacts Repository Compromise**: Needs independent Docker Hub verification
3. **Toolchain Backdoors**: Needs mmdebstrap cross-validation

### Out of Scope

- **Upstream Source Compromise**: Malicious code in legitimate packages
- **Package Compiler Backdoors**: Ken Thompson-style attacks in compilers that built Debian packages (we download pre-compiled .deb files)
- **Hardware Tampering**: CPU or firmware modifications
- **Zero-Day Vulnerabilities**: Unpatched flaws in legitimate software

**Partial Protection**: Multi-platform consensus detects platform-dependent backdoors in assembly tools (Debuerreotype). Dual-toolchain (planned) detects tool-specific backdoors. See [security.md](security.md#partial-protection-build-tool-backdoors) for details.

### Detection Methods

*Current:*
- **Checksum Mismatch**: SHA256 verification fails on artifacts repository modifications
- **Cross-Platform Divergence**: Platforms disagree, revealing compromised CI
- **Temporal Anomalies**: Unexpected checksum changes between verifications
- **Consensus Failure**: All CI systems must agree

*Planned:*
- **Registry Tampering**: Direct Docker Hub verification catches post-publication modifications
- **Toolchain Disagreement**: Debuerreotype and mmdebstrap diverge, indicating compromise
- **Pattern Disruption**: Selective tampering across architectures or suites

*Response:*
1. Fail CI/CD build with error logs
2. Update dashboard showing failed images
3. Provide forensic data (checksums, logs, parameters)
4. Enable triage across platforms and architectures

### Trust Requirements

*Required:*
- **Debian Packages**: We verify assembly, not package compilation
- **Debian Build Infrastructure**: Compilers that built packages
- **Cryptographic Functions**: SHA256 remains secure
- **Build Environment**: Verification infrastructure remains secure
- **Artifacts Repository**: `docker-debian-artifacts` (single trust point until Docker Hub verification)

*Trust Reduction:*
- **Multi-Perspective Consensus**: All CI platforms must agree
- **Planned: Dual-Toolchain**: Debuerreotype and mmdebstrap must match
- **Planned: Independent Validators**: Community verification distributes trust
- **Planned: Registry Verification**: Docker Hub checks eliminate artifacts repository dependency

### Why Reproducibility Matters

Reproducible builds shift security from "trust the builder" to "verify the build." Bit-for-bit recreation proves assembly integrity while relying on Debian's compiler security. Protects against Docker image tampering.

## Trust Dependencies

> For complete analysis of trust dependencies, see [security.md](security.md#trust-dependencies).

This system requires trust in several components. Key dependencies:

### Infrastructure

- **GitHub Actions**: Primary CI/CD, mitigated by cross-validation with GCP
- **Google Cloud Build**: Independent verification, consensus detects divergence
- **GitLab CI** (Planned): Additional perspective for consensus
- **Standalone Validators** (Planned): Community-operated nodes distribute trust

### Build Tools

- **Debuerreotype**: Official builder (v0.16), cross-validated with mmdebstrap (planned)
- **mmdebstrap** (Planned): Independent alternative for dual-toolchain verification

### Data Sources

- **snapshot.debian.org**: Time-locked package archive with cryptographic verification
- **docker-debian-artifacts**: Official build parameters and checksums (single trust point)

### Container Images

- **tonistiigi/binfmt**: QEMU registration (digest-pinned, privileged, requires confirmation)
- **multiarch/qemu-user-static**: Fallback QEMU (Linux systems)

### Registries

- **Docker Hub**: Official distribution (our system verifies integrity)
- **GHCR** (Planned): Daily builds with signed attestations

### Privileged Access

**SYS_ADMIN Capability**: Required for chroot/mount/namespace operations in Debuerreotype builds. Container isolation mitigates risks. No alternatives exist.

**Privileged Containers**: Used only for binfmt setup (brief, exits immediately, requires confirmation).

### Trust Reduction

- **Multi-Perspective Consensus**: All platforms must agree
- **Dual-Toolchain** (Planned): Debuerreotype and mmdebstrap must match
- **Digest Pinning**: Immutable SHA256 references prevent substitution
- **Transparent Operation**: Results and logs published in real-time
- **Community Validation**: Anyone can verify locally

### Irreducible Trust

1. **Debian Source Packages**: We verify builds, not package contents
2. **Cryptographic Functions**: SHA256 security
3. **Linux Kernel**: Isolation correctness
4. **CPU Architecture**: Faithful instruction execution
5. **Our Scripts**: Open source, requires review or trust

Reproducible builds shift trust from builder to verification.

## Architecture

> For complete architecture details, see [architecture.md](architecture.md).

### Verification Engine

Modular shell scripts:
- Retrieve official parameters from upstream
- Orchestrate single or parallel builds
- Compare checksums between local and official builds
- Generate JSON reports and badges

### Build Platforms

- **Local**: One-command verification with automatic QEMU, parallel builds
- **GitHub Actions**: Matrix builds, native ARM runners, QEMU emulation
- **Google Cloud Build**: Independent validation, Workload Identity Federation
- **GitLab CI** (Planned): Additional independent perspective
- **Standalone Validators** (Planned): Community-operated nodes

### Build Targets

- **Official Verification**: Rebuilds with exact timestamps, weekly runs
- **Daily Builds** (Planned): Fresh images at midnight UTC for immediate use

### Consensus Mechanism

- Full consensus required from all platforms
- Each platform builds independently with identical parameters
- Validator workflow aggregates results and creates witness evidence on failure
- Dashboard displays per-platform consensus status

**Tools:**
- `collect-results.sh`: Fetches reports from GitHub Actions and GCP
- `compare-platforms.sh`: Requires unanimous agreement, normalizes formats
- `consensus-validator.yml`: Weekly automated validation with WIF authentication

**Usage Examples**

Manual consensus validation:
```bash
# Collect results from both platforms
./scripts/collect-results.sh \
  --serial 20251020 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# Compare and validate consensus (requires full agreement)
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
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
- GitHub Actions and Google Cloud Build require full agreement
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
   - Requires full consensus from all platforms
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
- Full consensus from all CI platforms required
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
