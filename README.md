# Debian Reproducibility Verification

![Build Status](https://github.com/sheurich/debian-repro/actions/workflows/reproducible-debian-build.yml/badge.svg)
![Lint Status](https://github.com/sheurich/debian-repro/actions/workflows/lint.yml/badge.svg)
![Reproducibility Rate](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json)
![Consensus Status](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/consensus.json)
![Last Verified](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/last-verified.json)

## Why This Exists

Millions of containers run on Debian Docker images. A compromised build process means compromised containers.

This system detects supply chain attacks by rebuilding official Debian Docker images from source and comparing SHA256 checksums. Bit-for-bit reproduction proves images remain untampered.

**Public dashboard:** https://sheurich.github.io/debian-repro/

## What We Detect

| Attack | Detected | Method |
|--------|----------|--------|
| Build process tampering | Yes | Checksum mismatch |
| CI platform compromise | Yes | Consensus failure between platforms |
| Package substitution | Yes | Reproducibility breaks |
| Docker Hub tampering | Yes | Registry verification via diff_id comparison |
| Upstream package backdoors | No | Out of scope |

We verify image *assembly*, not package *compilation*. See [Security Model](docs/security.md) for the threat model.

## How It Works

1. **Fetch** official build parameters from `debuerreotype/docker-debian-artifacts`
2. **Rebuild** using Debuerreotype with identical timestamps
3. **Compare** SHA256 checksums against official artifacts
4. **Require consensus** — all platforms must agree

### Multi-Platform Consensus

We build on two independent platforms:
- **GitHub Actions** (Microsoft infrastructure)
- **Google Cloud Build** (Google infrastructure)

Both must produce identical checksums. Disagreement signals platform compromise or non-deterministic builds.

### Trust Model

We trust:
- **Debian packages** — we verify assembly, not compilation
- **`docker-debian-artifacts`** — source of truth for official builds
- **SHA256** — cryptographic integrity

Multi-platform consensus eliminates single-CI as a trust point. See [Security Model](docs/security.md).

## Quick Start

### Local Verification

Runs on macOS and Linux with automatic multi-architecture support.

```bash
# Clone and run
git clone https://github.com/sheurich/debian-repro.git
cd debian-repro
./verify-local.sh

# Cross-architecture builds (auto-setup if needed)
./verify-local.sh --arch amd64   # Build AMD64 on Apple Silicon
./verify-local.sh --arch arm64   # Build ARM64 on Intel

# Parallel multi-suite builds
./verify-local.sh --parallel --suites "bookworm trixie bullseye"
```

The script detects missing architectures and installs QEMU emulation.

See [Local Setup](docs/local-setup.md) for troubleshooting.

## Coverage

**Architectures:**
- Supported: amd64, arm64, armhf, i386, ppc64el
- Unsupported: s390x (not in artifacts repository)

**Suites:**
- `forky` (testing)
- `trixie` (stable)
- `bookworm` (oldstable)
- `bullseye` (oldoldstable)
- `unstable` (sid)

## Documentation

### Understand the System
- [Security Model](docs/security.md) — Threat model, trust dependencies, detection methods
- [Architecture](docs/architecture.md) — Verification engine, consensus mechanism, toolchain

### Run Locally
- [Local Setup](docs/local-setup.md) — Prerequisites, cross-architecture builds, troubleshooting
- [Debuerreotype Guide](docs/debuerreotype-guide.md) — Manual builds with the official toolchain
- [Commands](docs/commands.md) — Command reference

### Operate in CI
- [Consensus Validation](docs/consensus-validation-guide.md) — Cross-platform verification
- [GCP Setup](docs/gcp-setup-instructions.md) — Google Cloud Build with Workload Identity Federation
- [Dashboard Setup](docs/dashboard-setup.md) — GitHub Pages configuration

### Future Work
- [Roadmap](docs/roadmap.md) — Planned features and investigated alternatives
