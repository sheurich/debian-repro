# Debian Reproducibility Verification

![Build Status](https://github.com/sheurich/debian-repro/actions/workflows/reproducible-debian-build.yml/badge.svg)
![Lint Status](https://github.com/sheurich/debian-repro/actions/workflows/lint.yml/badge.svg)
![Reproducibility Rate](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json)
![Last Verified](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/last-verified.json)

## Project Purpose

We detect supply chain attacks against official Debian Docker images by rebuilding from source and comparing cryptographic checksums. Bit-for-bit reproduction proves images remain untampered.

## Project Goals

### Primary Goal
**Verify supply chain integrity** of official Debian Docker images through independent reproducible builds, detecting tampering and unauthorized modifications.

### How We Achieve This
- **Rebuild** images from source using the official toolchain (Debuerreotype)
- **Compare** SHA256 checksums across multiple platforms
- **Detect** changes within hours through automated verification
- **Publish** real-time verification status at https://sheurich.github.io/debian-repro/
- **Require** consensus from multiple independent CI systems and validators

### Additional Capabilities
- **Daily Builds**: Fresh base images at midnight UTC for immediate use and drift detection
- **Dual Toolchains**: Debuerreotype and mmdebstrap must produce identical outputs
- **Consensus Required**: 2+ independent CI systems must agree before accepting results

### Why This Matters
Software supply chain attacks threaten millions of containers built on Debian base images. This project proves cryptographically that official images match their source code. No single party requires trust. Reproducibility failures signal compromise or toolchain issues requiring immediate investigation.

## Architecture

**Multi-Perspective CI System:**
- **Google Cloud Build** (`cloudbuild.yaml`)
- **GitHub Actions** (`.github/workflows/reproducible-debian-build.yml`)
- **GitLab CI** (`.gitlab-ci.yml`)
- **Standalone Validators** - Independent servers and self-hosted runners

**Verification Toolchains:**
- **Debuerreotype v0.16** - Official Docker Hub Debian image builder
- **mmdebstrap** - Independent toolchain for cross-validation
- Verification passes only when both tools produce identical outputs

**Verification Method:**
- Fetch official build parameters from `debuerreotype/docker-debian-artifacts` repository
- Build using identical timestamp (`SOURCE_DATE_EPOCH`)
- Compare SHA256 checksums between local build and official artifacts
- Fail builds when checksums differ

## Quick Start

### Local Verification

Runs on macOS and Linux with **automatic** multi-architecture support.

```bash
# Clone and run
git clone https://github.com/sheurich/debian-repro.git
cd debian-repro
./verify-local.sh

# Cross-architecture builds (auto-setup if needed)
./verify-local.sh --arch amd64   # Build AMD64 on Apple Silicon Mac
./verify-local.sh --arch arm64   # Build ARM64 on Intel Mac

# Parallel multi-suite builds
./verify-local.sh --parallel --suites "bookworm trixie bullseye"

# Parallel cross-architecture builds (auto-setup!)
./verify-local.sh --parallel --suites "bookworm trixie bullseye" --arch amd64
```

**The script automatically configures cross-architecture emulation** when needed, detecting missing architectures and installing binfmt support via QEMU.

See **[docs/local-setup.md](docs/local-setup.md)** for setup details and troubleshooting.

## Common Commands

### Triggering Builds

**GitHub Actions (manual):**
```bash
gh workflow run reproducible-debian-build.yml \
  -f suites='bookworm trixie' \
  -f architectures='amd64,arm64' \
  -f verify_only=true
```

**Google Cloud Build:**
```bash
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SUITE=bookworm,_ARCHITECTURES="amd64 arm64"
```

### Local Development (requires Debuerreotype clone)

**Fetch official parameters:**
```bash
git clone --depth 1 --branch dist-amd64 \
  https://github.com/debuerreotype/docker-debian-artifacts.git official-amd64
cat official-amd64/serial
cat official-amd64/debuerreotype-epoch
```

**Build rootfs:**
```bash
./docker-run.sh ./examples/debian.sh \
  --arch amd64 output bookworm 2025-10-20T00:00:00Z
```

**Verify checksums:**
```bash
# Your local build (debuerreotype creates nested structure)
cat output/20251020/amd64/bookworm/rootfs.tar.xz.sha256

# Official build (flat structure in dist-* branch)
curl -sL https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts/dist-amd64/bookworm/rootfs.tar.xz.sha256

# Or compare directly
sha256sum output/20251020/amd64/bookworm/rootfs.tar.xz
```

### Consensus Validation

**Cross-platform verification:**
```bash
# Collect results from all platforms for a serial
./scripts/collect-results.sh \
  --serial 20251020 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# Validate consensus (requires 2+ platforms to agree)
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --threshold 2 \
  --output consensus-report.json
```

**Automated consensus check:**
```bash
# Trigger consensus validator workflow
gh workflow run consensus-validator.yml -f serial=20251020

# Watch progress
gh run watch

# View consensus report in artifacts
gh run download <run-id> -n consensus-report
```

**Features:**
- Multi-platform collection in single run
- Automatic format normalization (GitHub nested vs GCP array)
- Configurable consensus threshold (default: 2-of-N)
- Exit code 0 = consensus achieved, non-zero = disagreement

## Key Configuration

**Supported Architectures:** amd64, arm64, armhf, i386, ppc64el, s390x

**Supported Suites:**
- `forky` (testing)
- `trixie` (stable)
- `bookworm` (oldstable)
- `bullseye` (oldoldstable)
- `unstable` (sid)

**Critical Build Requirements:**
- Exact timestamp from official artifacts repository
- Docker capabilities: `SYS_ADMIN`, drop `SETFCAP`
- Security options: `seccomp=unconfined`, `apparmor=unconfined`
- Tmpfs: `/tmp:dev,exec,suid,noatime`

## CI/CD Workflow

**Google Cloud Build (6 steps):**
1. Fetch official build parameters
2. Setup Debuerreotype v0.16
3. Build Debuerreotype Docker image
4. Build rootfs tarballs
5. Verify reproducibility against official checksums
6. Create OCI images

**GitHub Actions (4 jobs):**
1. `fetch-official`: Download official parameters and checksums
2. `build`: Matrix job for each architecture (uses QEMU for ARM)
3. `summary`: Generate markdown report with verification results
4. `update-dashboard`: Update dashboard data and badges from build results

**Scheduling:**
- Automated weekly runs: Sundays at 00:00 UTC
- Artifact retention: 7 days

## Reproducibility Principles

Debuerreotype ensures bit-for-bit reproducibility through:
- `snapshot.debian.org`: Time-locked package versions
- `SOURCE_DATE_EPOCH`: Normalized timestamps
- Deterministic tar: Sorted files, numeric owners
- Fixup process: Removes logs, machine IDs, variable content

Use the exact timestamp from official builds - this is the single most critical parameter for reproducibility.

## Documentation

- [`docs/debuerreotype-guide.md`](docs/debuerreotype-guide.md) - Step-by-step guide for using Debuerreotype
- [`docs/local-setup.md`](docs/local-setup.md) - Local verification setup and troubleshooting
- [`docs/gcp-setup-instructions.md`](docs/gcp-setup-instructions.md) - Google Cloud Platform integration with WIF
- [`docs/consensus-validation-guide.md`](docs/consensus-validation-guide.md) - Cross-platform consensus validation
- [`docs/design.md`](docs/design.md) - Complete system architecture and design rationale
- [`docs/dashboard-setup.md`](docs/dashboard-setup.md) - GitHub Pages dashboard configuration
