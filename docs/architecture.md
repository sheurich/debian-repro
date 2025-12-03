# Architecture

Verification engine, build platforms, consensus mechanism, and toolchain integration.

## Overview

We detect supply chain attacks by proving official Debian Docker images rebuild bit-for-bit from source. Independent verification across multiple platforms protects containers relying on Debian base images.

## Verification Flow

```
┌─────────────────────┐
│ 1. Fetch Parameters │
│ (docker-debian-     │
│  artifacts repo)    │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 2. Rebuild          │
│ (Debuerreotype +    │
│  snapshot.debian.org)│
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 3. Compare SHA256   │
│ (local vs official) │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 4. Require Consensus│
│ (all platforms agree)│
└─────────────────────┘
```

## Current Trust Point

The `docker-debian-artifacts` repository is our single trust point.

```
┌─────────────────┐     ┌──────────────────────┐     ┌────────────┐
│ Debian Packages │ ──► │ docker-debian-       │ ──► │ Docker Hub │
│ (snapshot.d.o)  │     │ artifacts (verified) │     │ (gap)      │
└─────────────────┘     └──────────────────────┘     └────────────┘
        ▲                         ▲
        │                         │
        │    ┌───────────────┐    │
        └────│ Our Builds    │────┘
             │ (verification)│
             └───────────────┘
```

**Gap**: We don't verify Docker Hub images match the artifacts repository. An attacker who compromises Docker Hub could serve different images.

**Planned**: Direct Docker Hub verification closes this gap.

## Build Platforms

### GitHub Actions (Primary)

- Matrix builds across architectures
- Native ARM runners for arm64/armhf
- QEMU emulation for i386/ppc64el
- Weekly scheduled verification (Sundays 00:00 UTC)

### Google Cloud Build (Independent)

- Independent validation platform
- Workload Identity Federation authentication
- Artifact storage with lifecycle management

### Local Execution

- One command: `./verify-local.sh`
- Automatic QEMU setup for cross-architecture
- Parallel builds with CPU-based concurrency
- Supports Docker Desktop, Colima, OrbStack

## Consensus Mechanism

Full consensus required. All platforms must produce identical SHA256 checksums.

### Why Consensus Matters

- Detects single-platform compromise
- Reveals non-deterministic builds
- Eliminates CI as single trust point

### Implementation

**Result collection** (`scripts/collect-results.sh`): Fetches reports from GitHub Actions and GCP. Supports GitHub Pages and GCS bucket artifacts.

**Consensus validation** (`scripts/compare-platforms.sh`): Compares checksums across platforms per suite/architecture. Requires unanimous agreement. Generates witness evidence on disagreement.

**Automated validation** (`consensus-validator.yml`): Runs weekly after builds (Mondays 06:00 UTC). Uses Workload Identity Federation for GCP. Updates dashboard with consensus status.

### Usage

```bash
# Collect results from all platforms
./scripts/collect-results.sh \
  --serial 20251103 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# Validate consensus
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --output consensus-report.json
```

## Toolchain

### Debuerreotype

Official Debian image builder (v0.16 pinned).

**Requirements**:
- `SYS_ADMIN` capability for chroot operations
- Exact `SOURCE_DATE_EPOCH` timestamp
- Package versions locked via snapshot.debian.org

**How it achieves reproducibility**:
- Fetches packages from timestamped snapshot
- Normalizes all timestamps with SOURCE_DATE_EPOCH
- Deterministic tar with sorted files and numeric owners
- Fixup process removes logs, machine IDs, variable content

## Public Dashboard

**Location**: https://sheurich.github.io/debian-repro/

- Reproducibility status matrix
- 7-day historical trends
- Architecture breakdowns
- Consensus status per platform
- JSON/CSV/JSON-LD data exports

**Deployment**: `pages.yml` workflow deploys `/dashboard` directory. `update-dashboard` job updates data after each CI run.

## Repository Structure

```
/
├── .github/workflows/  # CI/CD workflows
├── scripts/            # Verification scripts
├── tests/              # BATS test suite
├── docs/               # Documentation
├── dashboard/          # GitHub Pages dashboard
│   ├── badges/         # Shields.io endpoints
│   ├── data/           # Verification data
│   └── index.html      # Dashboard interface
├── cloudbuild.yaml     # GCP Cloud Build config
└── verify-local.sh     # Local entry point
```

## Technical Requirements

### Docker Configuration

```yaml
capabilities:
  add: [SYS_ADMIN]
  drop: [SETFCAP]
security_opt:
  - seccomp=unconfined
  - apparmor=unconfined
tmpfs: /tmp:dev,exec,suid,noatime
environment:
  TZ: UTC
  SOURCE_DATE_EPOCH: <exact official epoch>
```

### Critical Parameters

- `SOURCE_DATE_EPOCH` must match official timestamp exactly
- Architecture names require mapping (Debian ↔ Docker)
- Output structure: `{serial}/{arch}/{suite}/`

## Architecture Support

| Architecture | GitHub Runner | GCP | Emulation |
|--------------|---------------|-----|-----------|
| amd64 | ubuntu-24.04 | Native | No |
| arm64 | ubuntu-24.04-arm | QEMU | No |
| armhf | ubuntu-24.04-arm | QEMU | No |
| i386 | ubuntu-24.04 + QEMU | QEMU | Yes |
| ppc64el | ubuntu-24.04 + QEMU | QEMU | Yes |

## Quality Assurance

**Testing**: BATS unit and integration tests. CI runs on every change.

**Linting**: Shellcheck for scripts, yamllint for YAML.

**Monitoring**: Reproducibility percentage, build duration, cross-platform match rate.

## Extensibility

**Adding architectures**: Update mappings, configure runners/emulation, add to matrix.

**Adding suites**: Automatic when they appear in official repository.

**Integration points**: JSON reports, Shields.io badges, GitHub Actions outputs, GCS artifacts.
