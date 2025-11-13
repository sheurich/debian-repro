# System Architecture

System design, verification process, and technical specifications for debian-repro.

## Overview

We detect supply chain attacks by proving official Debian Docker images rebuild bit-for-bit from source. Independent cryptographic verification across multiple platforms protects millions of containers relying on Debian base images.

## System Goals

### Mission
Verify continuously that official Debian Docker images reproduce bit-for-bit from source, providing tamper-evidence for the software supply chain.

### Primary Objectives

**Security Objectives**
- **Detect** unauthorized modifications through checksum mismatches
- **Verify** cryptographically that images match their source
- **Alert** on reproducibility failures via weekly automated verification

**Trust Objectives**
- **Eliminate** single points of trust through multi-platform builds
- **Require** full consensus from all independent CI systems
- **Publish** all verification results publicly in real-time

**Coverage Objectives**
- **Support** Debian architectures: amd64, arm64 (default), plus armhf, i386, ppc64el (manual trigger). s390x explicitly unsupported (not in artifacts repo)
- **Cover** all active Debian suites (stable, testing, unstable, oldstable)
- **Monitor** continuously with weekly scheduled verification for default architectures

### Design Principles
- **Deterministic**: Identical inputs produce identical outputs
- **Transparent**: All results remain publicly accessible
- **Efficient**: Verify only when upstream changes
- **Portable**: Works locally and in CI/CD environments

## Verification Engine

Modular shell scripts:
- Retrieve official parameters from upstream
- Orchestrate single or parallel builds
- Compare checksums between local and official builds
- Generate JSON reports and badges

## Build Platforms

### Local Execution
- One command starts verification
- Configures QEMU automatically for cross-architecture builds
- Runs parallel builds with CPU-based concurrency
- Supports Docker Community/Desktop, Colima, OrbStack

### GitHub Actions
- Triggers on upstream changes
- Matrix builds across architectures
- Native ARM runners for arm64/armhf
- QEMU emulation for i386/ppc64el
- Caches via GitHub Container Registry

### Google Cloud Build
- Independent validation platform
- High-performance compute
- Artifact storage with lifecycle management
- Workload Identity Federation authentication

## Build Targets

**Official Verification** (Primary)
- Rebuilds official Debian Docker images with exact timestamps
- Triggered by upstream changes in `docker-debian-artifacts` repository
- Verifies bit-for-bit reproducibility against Docker Hub images
- Weekly scheduled verification runs

## Consensus Mechanism

### Multi-Perspective Validation
- Full consensus required from all platforms
- Each CI platform builds independently with identical parameters
- Consensus validator workflow aggregates and validates results
- Failures trigger detailed investigation with witness evidence
- Dashboard displays consensus status with platform-level visibility

### Implementation

**Result Collection** (`scripts/collect-results.sh`): Fetches reports from GitHub Actions and GCP. Supports GitHub Pages and GCS bucket artifacts. Retrieves by serial number. Automatic retry on failures.

**Consensus Validation** (`scripts/compare-platforms.sh`): Compares checksums across platforms per suite/architecture. Requires unanimous agreement. Generates reports and witness evidence. Normalizes GitHub nested and GCP array formats automatically.

**Automated Validation** (`consensus-validator.yml`): Runs weekly or on-demand. Uses Workload Identity Federation for GCP authentication. Collects from all platforms, validates consensus, updates dashboard, commits reports.

### Usage Examples

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

## Toolchain Integration

### Debuerreotype
- Official Debian image builder (v0.16 pinned)
- Requires `SYS_ADMIN` for chroot operations
- Uses exact `SOURCE_DATE_EPOCH` timestamp
- Locks package versions via snapshot.debian.org

### mmdebstrap (Planned)
- Independent debootstrap alternative
- Produces bit-identical outputs via shared fixup process
- Uses same input parameters as Debuerreotype
- Provides toolchain diversity

## Public Dashboard

**Location:** `https://sheurich.github.io/debian-repro/`

GitHub Pages hosts:
- Reproducibility status matrix
- 30-day historical trends
- Architecture breakdowns
- Status badges
- Mobile-responsive interface

**Configuration**: `pages.yml` workflow deploys `/dashboard` directory. `update-dashboard` job updates data after each CI run.

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
- Unit tests validate functions
- Integration tests verify workflows
- BATS tests shell scripts
- CI runs tests on every change

### Code Quality
- Shellcheck analyzes scripts
- Yamllint validates YAML
- Scripts exit on undefined variables
- Structured logging

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
- Reproducibility degradation triggers warnings
- Stale data triggers alerts

## Performance

### Optimization
- Docker buildx caches layers
- Shallow git clones reduce transfer
- Parallel builds use CPU cores
- Tmpfs accelerates I/O

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
- **Platform Consensus**: 100% agreement required between all platforms
