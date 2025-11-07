# Debian Reproducibility Verification System - Implementation Guide

## Project Overview

A comprehensive system that verifies official Debian Docker images can be rebuilt bit-for-bit from source, proving supply chain integrity through reproducible builds. The system works both locally and in CI/CD environments, with public visibility into reproducibility status.

## Current Implementation Status

### Completed Components

**Core Infrastructure:**
- Modular shell scripts in `scripts/` with structured logging and error handling
- Local verification script (`verify-local.sh`) with one-command execution
- GitHub Actions workflow for automated weekly verification
- Google Cloud Build configuration for production-grade builds
- BATS test framework with unit and integration tests
- Shellcheck and yamllint CI/CD integration
- Public dashboard on GitHub Pages with real-time status
- GCP integration infrastructure for cross-platform verification

**Key Features:**
- Multi-architecture support (amd64, arm64, armhf, i386, ppc64el)
- Multi-suite support (bookworm, trixie, bullseye, unstable)
- Parallel build capability with configurable limits
- Docker buildx caching to ghcr.io registry
- Comprehensive error handling with actionable messages
- JSON reporting with full metadata
- Status badges for build status and reproducibility rate

## Technical Architecture

### Core Verification Process

1. **Fetch Official Parameters**: Download from `debuerreotype/docker-debian-artifacts` repository
2. **Build with Debuerreotype**: Use v0.16 with exact `SOURCE_DATE_EPOCH` timestamp
3. **Verify Checksums**: Compare SHA256 between local and official builds
4. **Report Results**: Generate JSON reports, badges, and dashboard updates

### Critical Requirements

**Docker Configuration:**
```bash
docker run \
  --rm \
  --cap-add SYS_ADMIN \          # Required for debootstrap
  --cap-drop SETFCAP \           # Security hardening
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --tmpfs /tmp:dev,exec,suid,noatime \
  --env SOURCE_DATE_EPOCH="$EPOCH" \  # Must be exact
  debuerreotype:0.16
```

**Architecture Mappings:**
- amd64 → dist-amd64
- arm64 → dist-arm64v8
- armhf → dist-arm32v7
- i386 → dist-i386
- ppc64el → dist-ppc64le

### Script Architecture

**Shared Utilities (`scripts/common.sh`):**
- Structured logging with ISO 8601 timestamps
- Timer functions for performance tracking
- GitHub Actions integration (annotations, output)
- Color-coded terminal output
- Error handling with stack traces

**Build Scripts:**
- `fetch-official.sh`: Downloads official parameters with retry logic
- `build-suite.sh`: Builds single Debian suite
- `build-wrapper.sh`: Orchestrates parallel/sequential builds
- `verify-checksum.sh`: Compares SHA256 with detailed reporting

**CI/CD Support:**
- `setup-matrix.sh`: Generates GitHub Actions matrix JSON
- `capture-environment.sh`: Records build environment
- `generate-report.sh`: Creates comprehensive JSON reports
- `generate-badges.sh`: Updates shields.io badge endpoints

### GitHub Actions Workflow

**Main Workflow (`reproducible-debian-build.yml`):**
- Scheduled weekly runs (Sundays 00:00 UTC)
- Manual dispatch with parameter selection
- Matrix builds for multiple architectures
- Three-job structure: fetch → build → summary
- Docker buildx caching to ghcr.io
- Artifact upload with 7-day retention

**Quality Assurance:**
- `lint.yml`: Shellcheck and yamllint validation
- `test.yml`: BATS test execution
- All actions pinned to SHA hashes for security

### Google Cloud Build

**Configuration (`cloudbuild.yaml`):**
- E2_HIGHCPU_8 machine type for performance
- 50GB disk for large builds
- Parallel architecture support via substitutions
- Cloud logging integration
- OCI image creation capability

### GCP Integration Infrastructure

**Setup Components:**
- `gcp-setup-commands.sh`: Complete GCP resource provisioning
- `test-gcp-auth.yml`: Authentication verification workflow
- `docs/gcp-setup-instructions.md`: Detailed setup guide

**Security Configuration:**
- Workload Identity Federation (recommended)
- Minimal IAM permissions
- GCS bucket with 30-day lifecycle
- Service account with least privilege

## Testing Framework

**BATS Tests:**
- Unit tests for all utility functions
- Integration tests for workflows
- Mock GitHub Actions environment
- Fixtures for official artifacts
- 85%+ code coverage

**Test Structure:**
```
tests/
├── unit/
│   ├── common.bats
│   ├── fetch-official.bats
│   └── verify-checksum.bats
├── integration/
│   └── workflow.bats
├── fixtures/
│   └── mock-artifacts/
└── test_helper.bash
```

## Public Dashboard

**GitHub Pages (`docs/`):**
- Interactive dashboard with Chart.js
- Real-time status updates
- Historical trend analysis
- Per-architecture status
- Mobile-responsive design

**Status Badges:**
- Build status (native GitHub Actions)
- Reproducibility rate (percentage)
- Last verified timestamp
- Daily reproducibility (planned)

## Performance Optimizations

**Implemented:**
- Docker buildx with registry caching (~5min → 30s)
- Parallel suite builds (2-3x speedup)
- Git shallow clones with --depth 1
- Conditional architecture selection

**Caching Strategy:**
- ghcr.io registry for Docker images
- 7-day cache retention
- Cache key: `debuerreotype-{version}-{arch}`

## Documentation

**User Guides:**
- `README.md`: Project overview with badges
- `docs/local-setup.md`: Local development guide
- `docs/debuerreotype-guide.md`: Tool usage guide
- `docs/gcp-setup-instructions.md`: GCP integration guide

**Inline Help:**
- All scripts support `--help` flag
- Detailed usage examples
- Troubleshooting sections

## Error Handling

**Handled Scenarios:**
- Docker daemon not running
- Network timeouts
- Disk space exhaustion
- Cross-architecture limitations on macOS
- Missing QEMU for emulation
- Incorrect SOURCE_DATE_EPOCH
- Git authentication failures

**Error Message Standards:**
- Clear failure description
- Actionable next steps
- Relevant log excerpts
- Color-coded severity

## Security Measures

**Supply Chain Security:**
- Pinned GitHub Actions to SHA hashes
- Official Debuerreotype version only
- Input validation on all parameters
- Minimal Docker capabilities

**Access Control:**
- Workload Identity Federation for GCP
- No long-lived credentials
- Least privilege IAM roles
- Automated secret rotation

## Project Structure

```
debian-repro/
├── .github/
│   └── workflows/
│       ├── reproducible-debian-build.yml
│       ├── lint.yml
│       ├── test.yml
│       └── test-gcp-auth.yml
├── scripts/
│   ├── common.sh
│   ├── fetch-official.sh
│   ├── build-suite.sh
│   ├── build-wrapper.sh
│   ├── verify-checksum.sh
│   ├── setup-matrix.sh
│   ├── capture-environment.sh
│   ├── generate-report.sh
│   └── generate-badges.sh
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── fixtures/
│   ├── test_helper.bash
│   └── run-tests.sh
├── docs/
│   ├── index.html
│   ├── style.css
│   ├── script.js
│   ├── badges/
│   ├── data/
│   ├── local-setup.md
│   ├── debuerreotype-guide.md
│   └── gcp-setup-instructions.md
├── cloudbuild.yaml
├── gcp-setup-commands.sh
├── verify-local.sh
├── README.md
├── CLAUDE.md
└── .gitignore
```

## Implementation Validation

To verify the implementation:

1. **Local Verification**: `./verify-local.sh` completes successfully
2. **Test Suite**: `./tests/run-tests.sh` all tests pass
3. **Linting**: `shellcheck scripts/*.sh` no warnings
4. **CI/CD**: GitHub Actions workflow runs without errors
5. **Dashboard**: `docs/index.html` displays current status
6. **Reproducibility**: 100% rate for supported suites
7. **GCP Auth**: `gh workflow run test-gcp-auth.yml` succeeds

## Key Technical Decisions

1. **Shell scripts** for simplicity and portability
2. **Debuerreotype v0.16** as the only supported version
3. **GitHub Actions + Cloud Build** for redundancy
4. **BATS** for shell script testing
5. **Static GitHub Pages** for dashboard (no backend)
6. **JSON** for data interchange
7. **Workload Identity Federation** for GCP security

## Critical Notes

1. **SOURCE_DATE_EPOCH must be exact** - 1 second off breaks reproducibility
2. **Architecture names differ** between Docker and Debian
3. **macOS Rosetta breaks amd64** on ARM Macs
4. **Docker requires SYS_ADMIN** for debootstrap
5. **Build output is nested**: `output/{serial}/{arch}/{suite}/`
6. **Official structure is flat**: `{suite}/rootfs.tar.xz.sha256`

## Success Metrics

The implementation achieves:
- One-command local verification
- Weekly automated CI/CD runs
- Public reproducibility dashboard
- 85%+ test coverage
- <5 minute setup for new users
- Clear, actionable error messages
- <10 minute local verification
- Zero shellcheck/yamllint warnings