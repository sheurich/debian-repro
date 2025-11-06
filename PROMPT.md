# Debian Reproducibility Verification System - Complete Reconstruction Prompt

## Project Objective

Create a comprehensive system to verify that official Debian Docker images on Docker Hub can be rebuilt bit-for-bit from source, proving supply chain integrity through reproducible builds. The system must work both locally and in CI/CD environments, providing public visibility into reproducibility status.

## Core Requirements

### 1. Functional Requirements

**Verification Process:**
- Fetch official build parameters from `debuerreotype/docker-debian-artifacts` GitHub repository
- Build Debian rootfs tarballs using Debuerreotype v0.16 (the official tool)
- Compare SHA256 checksums between locally built and official artifacts
- Support multiple architectures: amd64, arm64, armhf, i386, ppc64el
- Support multiple Debian suites: bookworm, trixie, bullseye, unstable
- Achieve 100% bit-for-bit reproducibility when using correct parameters

**Build Requirements:**
- Use exact `SOURCE_DATE_EPOCH` timestamp from official builds (critical)
- Use snapshot.debian.org for time-locked package versions
- Run with specific Docker security capabilities (SYS_ADMIN for debootstrap)
- Handle cross-architecture builds with QEMU emulation

### 2. System Architecture

**Dual CI/CD System:**
- GitHub Actions workflow for automated weekly verification and manual triggers
- Google Cloud Build configuration for production-grade builds
- Both must support matrix builds for multiple architectures

**Modular Script Architecture:**
Create reusable shell scripts in `scripts/` directory:
- `common.sh`: Logging, timing, error handling, GitHub Actions integration
- `fetch-official.sh`: Download official parameters from artifacts repository
- `build-suite.sh`: Build single Debian suite using debuerreotype
- `build-wrapper.sh`: Orchestrate multiple suite builds (parallel/sequential)
- `verify-checksum.sh`: Compare SHA256 checksums with detailed reporting
- `setup-matrix.sh`: Generate GitHub Actions matrix JSON
- `capture-environment.sh`: Record build environment for debugging
- `generate-report.sh`: Create comprehensive JSON verification reports
- `generate-badges.sh`: Create shields.io badge endpoints

**Local Development:**
- One-command verification script (`verify-local.sh`)
- Auto-detect native architecture
- Handle macOS/Linux differences
- Clear progress reporting with timers
- Graceful error handling with actionable messages

### 3. Technical Implementation Details

**Shell Script Standards:**
- Bash with `set -Eeuo pipefail` for strict error handling
- Structured logging with ISO 8601 timestamps
- Component-based log prefixes
- Support for JSON output mode (`LOG_JSON=true`)
- Timer functions for performance tracking
- Color-coded terminal output
- GitHub Actions annotations when in CI

**Docker Configuration:**
```bash
docker run \
  --rm \
  --cap-add SYS_ADMIN \      # Required for debootstrap
  --cap-drop SETFCAP \       # Security hardening
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --tmpfs /tmp:dev,exec,suid,noatime \
  --env SOURCE_DATE_EPOCH="$EPOCH" \  # Critical for reproducibility
  debuerreotype:0.16
```

**Official Artifacts Structure:**
- Repository: `https://github.com/debuerreotype/docker-debian-artifacts`
- Branch naming: `dist-{arch}` (e.g., `dist-amd64`, `dist-arm64v8`)
- Files in each branch:
  - `serial`: Build date in YYYYMMDD format
  - `debuerreotype-epoch`: Unix timestamp for SOURCE_DATE_EPOCH
  - `{suite}/rootfs.tar.xz.sha256`: Official checksums

**Architecture Mappings:**
- amd64 → dist-amd64
- arm64 → dist-arm64v8
- armhf → dist-arm32v7
- i386 → dist-i386
- ppc64el → dist-ppc64le

### 4. Quality Assurance

**Testing Framework (BATS):**
- Unit tests for all utility functions in `tests/unit/`
- Integration tests for workflows in `tests/integration/`
- Test helper utilities in `tests/test_helper.bash`
- Mock functions for GitHub Actions environment
- Fixtures for official artifacts structure

**Linting:**
- Shellcheck for all shell scripts
- yamllint for YAML files
- Automated via `.github/workflows/lint.yml`

**CI/CD Workflows:**
- `.github/workflows/reproducible-debian-build.yml`: Main verification workflow
- `.github/workflows/lint.yml`: Code quality checks
- `.github/workflows/test.yml`: BATS test execution
- All GitHub Actions must be pinned to SHA hashes for security

### 5. Monitoring & Visibility

**GitHub Pages Dashboard:**
Create public dashboard in `docs/`:
- `index.html`: Interactive dashboard with Chart.js
- `style.css`: Responsive design
- `script.js`: Dynamic data loading and visualization
- `badges/`: JSON endpoints for shields.io badges
- `data/`: Historical verification results

**Status Badges:**
- Build status (GitHub Actions native)
- Reproducibility rate (percentage of successful verifications)
- Last verified date
- Per-architecture status

**Reporting:**
- JSON reports with full metadata
- Build environment fingerprinting
- Per-suite verification results with SHA256 and timing
- Historical data aggregation

### 6. Performance Optimizations

**Docker Image Caching:**
- Use buildx with registry cache (ghcr.io)
- Cache key: `debuerreotype-{version}-{arch}`
- Expected speedup: ~5min → 30s

**Parallel Builds:**
- Support GNU parallel or background jobs
- Configurable max parallel jobs
- 2-3x speedup for multi-suite builds

**Git Optimizations:**
- Use `--depth 1` for all clones
- Cache debuerreotype repository locally

### 7. Documentation Requirements

**User Documentation:**
- `README.md`: Project overview with status badges
- `docs/local-setup.md`: Comprehensive local setup guide
- `docs/debuerreotype-guide.md`: Step-by-step Debuerreotype usage guide
- `verify-local.sh --help`: Inline help for all scripts

**Documentation Standards:**
- Clear, concise technical writing (Strunk principles)
- Code examples for all workflows
- Troubleshooting section with common issues
- Performance tips and best practices

### 8. Error Handling & Edge Cases

**Handle These Scenarios:**
- Docker daemon not running
- Network timeouts fetching artifacts
- Disk space exhaustion during builds
- Cross-architecture builds on macOS (Rosetta limitations)
- Missing QEMU for ARM emulation on x86_64
- Incorrect SOURCE_DATE_EPOCH (most common failure)
- Git authentication issues
- Partial build failures

**Error Messages Must:**
- Clearly state what failed
- Provide actionable next steps
- Show relevant logs (last 20 lines on build failure)
- Use color coding (red for errors, yellow for warnings)

### 9. Security Considerations

**Supply Chain Security:**
- Pin all GitHub Actions to SHA hashes
- Verify GPG signatures where available
- Use official debuerreotype version only
- Don't trust any external inputs without validation

**Docker Security:**
- Minimal required capabilities
- Drop unnecessary privileges
- Use security options appropriately
- Never run with --privileged

### 10. Implementation Phases

**Phase 1: Core Functionality**
1. Create modular scripts in `scripts/`
2. Implement fetch, build, verify workflow
3. Add structured logging and error handling

**Phase 2: CI/CD Integration**
1. Create GitHub Actions workflow
2. Add Google Cloud Build configuration
3. Implement matrix builds for architectures

**Phase 3: Quality & Testing**
1. Add BATS test framework
2. Implement shellcheck linting
3. Create comprehensive test coverage

**Phase 4: Monitoring & Visibility**
1. Generate status badges
2. Create GitHub Pages dashboard
3. Implement historical tracking

**Phase 5: Optimization**
1. Add Docker image caching
2. Implement parallel builds
3. Optimize git operations

**Phase 6: Documentation**
1. Write comprehensive README
2. Create local development guide
3. Add inline help to all scripts

## Success Criteria

The implementation is complete when:
1. Local verification works on macOS and Linux with one command
2. CI/CD runs weekly and verifies all supported architectures
3. Public dashboard shows current reproducibility status
4. All scripts have tests with >80% coverage
5. Documentation enables new users to verify in <5 minutes
6. Build failures provide clear, actionable error messages
7. Performance allows full verification in <10 minutes locally
8. Code passes shellcheck and yamllint without warnings

## Key Technical Decisions

1. **Use shell scripts** (not Python/Go) for simplicity and portability
2. **Debuerreotype v0.16** is the only supported version
3. **GitHub Actions + Cloud Build** for redundancy
4. **BATS for testing** due to shell script focus
5. **Static GitHub Pages** for dashboard (no backend needed)
6. **JSON for data interchange** between components
7. **GNU parallel optional** (fallback to sequential)

## Critical Implementation Notes

1. **SOURCE_DATE_EPOCH must be exact** - even 1 second off breaks reproducibility
2. **Architecture names differ** between Docker (arm64v8) and Debian (arm64)
3. **macOS Rosetta breaks amd64 builds** on ARM Macs - detect and warn
4. **Relative paths break** when scripts change directories - use absolute paths
5. **Git clone exit codes** can be masked by pipes - handle carefully
6. **Docker requires SYS_ADMIN** capability for debootstrap mount operations
7. **Build output is nested**: `output/{serial}/{arch}/{suite}/rootfs.tar.xz`
8. **Official structure is flat**: `{suite}/rootfs.tar.xz.sha256`

## Expected Project Structure

```
debian-repro/
├── .github/
│   └── workflows/
│       ├── reproducible-debian-build.yml  # Main workflow
│       ├── lint.yml                       # Shellcheck + yamllint
│       └── test.yml                       # BATS tests
├── scripts/
│   ├── common.sh                          # Shared utilities
│   ├── fetch-official.sh                  # Get official params
│   ├── build-suite.sh                     # Build single suite
│   ├── build-wrapper.sh                   # Build orchestration
│   ├── verify-checksum.sh                 # SHA256 comparison
│   ├── setup-matrix.sh                    # GHA matrix generation
│   ├── capture-environment.sh             # Environment recording
│   ├── generate-report.sh                 # JSON reports
│   └── generate-badges.sh                 # Badge generation
├── tests/
│   ├── unit/                              # Unit tests
│   ├── integration/                       # Integration tests
│   ├── fixtures/                          # Test data
│   ├── test_helper.bash                   # Test utilities
│   └── run-tests.sh                       # Test runner
├── docs/
│   ├── index.html                         # Dashboard
│   ├── style.css                          # Dashboard styling
│   ├── script.js                          # Dashboard logic
│   ├── badges/                            # Badge JSONs
│   └── data/                              # Historical data
├── cloudbuild.yaml                        # Google Cloud Build
├── verify-local.sh                        # One-command local verification
├── README.md                              # Project documentation
└── .gitignore                             # Exclude artifacts

# Generated/downloaded (gitignored):
├── debuerreotype/                         # Cloned tool
├── output/                                # Build artifacts
├── official-*/                            # Official parameters
└── results/                               # Verification results
```

## Validation

To validate the implementation:
1. Run `./verify-local.sh` - should complete successfully
2. Check `./tests/run-tests.sh` - all tests pass
3. Run `shellcheck scripts/*.sh` - no warnings
4. Verify reproducibility rate is 100% for supported suites
5. Dashboard at `docs/index.html` displays correctly
6. GitHub Actions workflow runs without errors
7. Cross-reference SHA256 with Docker Hub official images

This system proves Debian's commitment to reproducible builds and supply chain security through automated, transparent verification.