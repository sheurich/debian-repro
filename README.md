# Debian Reproducibility Verification

![Build Status](https://github.com/sheurich/debian-repro/actions/workflows/reproducible-debian-build.yml/badge.svg)
![Lint Status](https://github.com/sheurich/debian-repro/actions/workflows/lint.yml/badge.svg)
![Reproducibility Rate](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json)
![Consensus Status](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/consensus.json)
![Last Verified](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/last-verified.json)

## Overview

Detect supply chain attacks against official Debian Docker images by rebuilding from source and comparing cryptographic checksums. Bit-for-bit reproduction proves images remain untampered.

**What we verify:**
- Build process reproducibility using Debuerreotype
- Checksum integrity across multiple independent CI systems (GitHub Actions, Google Cloud Build)
- Full consensus required: ALL platforms must agree

**Public dashboard:** https://sheurich.github.io/debian-repro/

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

**The script detects missing architectures and installs binfmt support via QEMU automatically.**

See **[docs/local-setup.md](docs/local-setup.md)** for setup details and troubleshooting.

For all commands (triggering builds, consensus validation, etc.), see **[docs/commands.md](docs/commands.md)**.

## Key Configuration

**Architecture Support:**
- **Default (automated weekly builds)**: amd64, arm64
- **Available on manual trigger**: amd64, arm64, armhf, i386, ppc64el
- **Explicitly unsupported**: s390x (not yet available in official artifacts repository)

**Supported Suites:**
- `forky` (testing)
- `trixie` (stable)
- `bookworm` (oldstable)
- `bullseye` (oldoldstable)
- `unstable` (sid)

For detailed architecture and system design, see **[docs/architecture.md](docs/architecture.md)**.

## Documentation

### Getting Started
- [`docs/local-setup.md`](docs/local-setup.md) - Local verification setup and troubleshooting
- [`docs/debuerreotype-guide.md`](docs/debuerreotype-guide.md) - Using Debuerreotype
- [`docs/commands.md`](docs/commands.md) - Command reference

### System Design
- [`docs/architecture.md`](docs/architecture.md) - System architecture and verification process
- [`docs/security.md`](docs/security.md) - Threat model and trust dependencies
- [`docs/design.md`](docs/design.md) - Complete design document

### Advanced Topics
- [`docs/consensus-validation-guide.md`](docs/consensus-validation-guide.md) - Cross-platform consensus validation
- [`docs/gcp-setup-instructions.md`](docs/gcp-setup-instructions.md) - Google Cloud Platform integration with WIF
- [`docs/dashboard-setup.md`](docs/dashboard-setup.md) - GitHub Pages dashboard configuration

### Roadmap
- [`docs/roadmap.md`](docs/roadmap.md) - Planned features and enhancements
