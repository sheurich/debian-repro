# README.md

## Project Purpose

This repository verifies the reproducibility of official Debian Docker images by rebuilding them with Debuerreotype and comparing SHA256 checksums. The goal is to prove that official Debian images on Docker Hub can be recreated bit-for-bit.

## Architecture

**Dual CI System:**
- **Google Cloud Build** (`cloudbuild.yaml`): Production-grade builds with E2_HIGHCPU_8 machines
- **GitHub Actions** (`.github/workflows/reproducible-debian-build.yml`): Automated weekly verification and manual triggers

**Core Tool:**
- Debuerreotype v0.16 (official Docker Hub Debian image builder)
- Cloned from https://github.com/debuerreotype/debuerreotype

**Verification Method:**
- Fetch official build parameters from `debuerreotype/docker-debian-artifacts` repo (branch: `dist-{arch}`)
- Build using identical timestamp (`SOURCE_DATE_EPOCH`)
- Compare SHA256 checksums between local build and official artifacts
- Build fails if checksums don't match

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

## Key Configuration

**Supported Architectures:** amd64, arm64, armhf, i386, ppc64el, s390x

**Supported Suites:**
- `trixie` (testing/stable)
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

**GitHub Actions (3 jobs):**
1. `fetch-official`: Download official parameters and checksums
2. `build`: Matrix job for each architecture (uses QEMU for ARM)
3. `summary`: Generate markdown report with verification results

**Scheduling:**
- Automated weekly runs: Sundays at 00:00 UTC
- Artifact retention: 7 days

## Reproducibility Principles

Debuerreotype ensures bit-for-bit reproducibility through:
- `snapshot.debian.org`: Time-locked package versions
- `SOURCE_DATE_EPOCH`: Normalized timestamps
- Deterministic tar: Sorted files, numeric owners
- Fixup process: Removes logs, machine IDs, variable content

The timestamp from official builds MUST be used exactly - this is the single most critical parameter for reproducibility.

## Documentation

See `HOWTO.md` for detailed step-by-step instructions on using Debuerreotype and verifying builds.
