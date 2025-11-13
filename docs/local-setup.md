# Local Setup Guide

Verify Debian reproducibility locally without CI/CD.

## Prerequisites

### Required Tools

```bash
# macOS
brew install docker jq git bc

# Ubuntu/Debian
sudo apt-get install docker.io jq git bc

# Verify installation
docker --version && jq --version && git --version
```

### Docker Setup

```bash
# Test Docker
docker run hello-world

# Linux: Add user to docker group
sudo usermod -aG docker $USER && newgrp docker
```

#### macOS with Colima

Colima enables cross-architecture builds by default:
- Default: `rosetta: false` and `binfmt: true` (optimal for multi-arch)
- Works with both `vmType: qemu` (default) or `vmType: vz`

```bash
# Install Colima
brew install colima

# Start with defaults (configured for cross-architecture builds)
colima start --cpu 4 --memory 8

# One-time binfmt setup (run after colima start)
docker run --rm --privileged tonistiigi/binfmt --install all

# Verify multi-architecture support
docker run --rm amd64/alpine uname -m    # Should output: x86_64
docker run --rm arm64v8/alpine uname -m  # Should output: aarch64
```

**Important:** Keep Colima's default `rosetta: false` setting. Rosetta conflicts with QEMU-based cross-architecture builds.

#### macOS with Docker Desktop

Docker Desktop supports cross-architecture builds, but Colima provides more reliable multi-arch support.

### Optional Tools

```bash
# Testing: bats
# Linting: shellcheck, yamllint
# Parallel builds: parallel
```

## Security Notice

Cross-architecture builds require privileged Docker access to register QEMU emulators with the kernel's binfmt_misc system.

**Command**: `docker run --rm --privileged tonistiigi/binfmt --install <arch>`

**Risk**: Privileged containers can escape sandbox restrictions and compromise the host.

**Mitigations**:
- Uses trusted images (`tonistiigi/binfmt`, `multiarch/qemu-user-static`)
- Prompts for confirmation (bypass with `SKIP_CONFIRM=true` in CI)
- Containers exit immediately with `--rm` flag
- Privileged access only for setup, not builds
- Optional: skip cross-architecture builds

**Alternatives** (if privileged access unavailable):
- Build native architecture only
- Use CI systems (GitHub Actions, Google Cloud Build)
- Manually install QEMU user-mode emulation on host

## Quick Start

```bash
# Clone and run
git clone https://github.com/sheurich/debian-repro.git
cd debian-repro
./verify-local.sh
```

## Manual Workflow

### 1. Fetch Official Parameters

```bash
./scripts/fetch-official.sh --arch amd64 --output-dir ./official-amd64

# Check parameters
cat ./official-amd64/serial.txt
cat ./official-amd64/epoch.txt
```

### 2. Setup Debuerreotype

```bash
# Clone (once)
git clone --depth 1 --tag 0.16 https://github.com/debuerreotype/debuerreotype.git

# Build Docker image (once)
cd debuerreotype
docker build --pull -t debuerreotype:0.16 .
cd ..
```

### 3. Build Rootfs

```bash
SERIAL=$(cat ./official-amd64/serial.txt)
EPOCH=$(cat ./official-amd64/epoch.txt)

./scripts/build-suite.sh \
  --suite bookworm \
  --arch amd64 \
  --epoch "$EPOCH" \
  --output-dir ./output \
  --image debuerreotype:0.16
```

### 4. Verify Reproducibility

```bash
./scripts/verify-checksum.sh \
  --build-dir ./output \
  --official-dir ./official-amd64 \
  --suite bookworm \
  --arch amd64 \
  --dpkg-arch amd64 \
  --serial "$SERIAL"

# Exit code: 0 = reproducible, 1 = not reproducible
```

## Full Verification Script

Create `verify-local.sh`:

```bash
#!/bin/bash
set -euo pipefail

ARCH="amd64"
SUITES="bookworm trixie"

# Fetch official parameters
./scripts/fetch-official.sh \
  --arch "$ARCH" \
  --output-dir "./official-$ARCH" \
  --suites "$SUITES"

SERIAL=$(cat "./official-$ARCH/serial.txt")
EPOCH=$(cat "./official-$ARCH/epoch.txt")

# Setup debuerreotype (if needed)
if [ ! -d debuerreotype ]; then
  git clone --depth 1 --tag 0.16 https://github.com/debuerreotype/debuerreotype.git
fi

# Build Docker image (if needed)
if ! docker image inspect debuerreotype:0.16 >/dev/null 2>&1; then
  (cd debuerreotype && docker build --pull -t debuerreotype:0.16 .)
fi

# Build all suites
./scripts/build-wrapper.sh \
  --suites "$SUITES" \
  --arch "$ARCH" \
  --epoch "$EPOCH" \
  --output-dir ./output \
  --image debuerreotype:0.16

# Verify each suite
for suite in $SUITES; do
  echo "Verifying $suite..."
  ./scripts/verify-checksum.sh \
    --build-dir ./output \
    --official-dir "./official-$ARCH" \
    --suite "$suite" \
    --arch "$ARCH" \
    --dpkg-arch "$ARCH" \
    --serial "$SERIAL"
done

echo "✅ All suites verified!"
```

## Advanced Usage

### Multi-Architecture Builds

Cross-architecture builds work automatically. The `verify-local.sh` script detects when you're building for a non-native architecture and automatically installs the required emulation support if needed.

#### Automatic Setup (All Platforms)

Simply specify the architecture you want:

```bash
# Build for any supported architecture
# Auto-setup happens if needed
./verify-local.sh --arch amd64   # AMD64 on Apple Silicon or linux/arm64
./verify-local.sh --arch arm64   # ARM64 on Intel Mac or linux/amd64
./verify-local.sh --arch armhf   # On any system
```

**How it works:**
1. Script detects your target architecture isn't natively supported
2. Automatically attempts to install binfmt emulation
3. Verifies emulation is working
4. Proceeds with build if successful
5. Shows helpful error messages if auto-setup fails

**Tested Examples (macOS with Colima/OrbStack on Apple Silicon):**
```bash
# Parallel multi-suite builds (native architecture)
./verify-local.sh --parallel --suites "bookworm trixie bullseye"

# Parallel multi-suite builds (cross-architecture)
./verify-local.sh --parallel --suites "bookworm trixie bullseye" --arch amd64
```

Both commands work reliably on Apple Silicon Macs with Colima v0.9.1+
and OrbStack v2.0.4+.

#### Manual Setup (Optional)

If automatic setup doesn't work or you prefer manual control:

**macOS (Colima):**
```bash
# Ensure binfmt is enabled in Colima config
# ~/.colima/default/colima.yaml should have:
# binfmt: true
# rosetta: false

# Restart Colima
colima stop && colima start

# Manually install all architectures
docker run --rm --privileged tonistiigi/binfmt --install all
```

**Linux:**
```bash
# Install QEMU user-mode emulation
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Or install system packages
sudo apt-get install qemu-user-static binfmt-support
```

**Docker Desktop:**
- Enable "Use Virtualization Framework" in settings
- **Disable** Rosetta for x86_64 emulation (causes /proc/self/exe errors)
- Restart Docker Desktop
- Let verify-local.sh auto-install binfmt on first cross-arch build

### Parallel Builds

```bash
./scripts/build-wrapper.sh \
  --suites "bookworm trixie bullseye" \
  --arch amd64 \
  --epoch "$EPOCH" \
  --output-dir ./output \
  --image debuerreotype:0.16 \
  --parallel \
  --max-jobs 2
```

### Generate Reports

```bash
# Capture environment
./scripts/capture-environment.sh --output ./results/environment.json

# Create verification report
./scripts/verify-checksum.sh \
  --build-dir ./output \
  --official-dir ./official-amd64 \
  --suite bookworm \
  --arch amd64 \
  --dpkg-arch amd64 \
  --serial "$SERIAL" \
  --json > ./results/amd64-bookworm.json

# Generate comprehensive report
./scripts/generate-report.sh \
  --results-dir ./results \
  --output ./report.json \
  --serial "$SERIAL" \
  --epoch "$EPOCH"

# Generate badges
./scripts/generate-badges.sh \
  --report ./report.json \
  --output-dir ./badges

# Note: Use ./badges for local testing
# CI workflow uses ./dashboard/badges for GitHub Pages deployment
```

## Debug Mode

```bash
# Enable verbose logging
export DEBUG=1
export LOG_LEVEL=0  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR

# Enable JSON output
export LOG_JSON=true

# Run any script with debugging
./scripts/fetch-official.sh --arch amd64 --output-dir ./official-amd64
```

## Testing

### Run Tests

```bash
# Install BATS
npm install -g bats

# Run all tests
./tests/run-tests.sh

# Run specific test
bats tests/unit/common.bats

# Run with filter
bats --filter "timestamp returns ISO 8601 format" tests/unit/common.bats
```

### Linting

```bash
shellcheck scripts/*.sh
yamllint .github/workflows/ cloudbuild.yaml
```

## Troubleshooting

### Docker Permission Denied

```bash
# Linux
sudo usermod -aG docker $USER && newgrp docker
```

### Build Fails: Requires SYS_ADMIN

Debuerreotype requires elevated privileges. Scripts handle this automatically. For manual Docker runs:

```bash
docker run --cap-add SYS_ADMIN --cap-drop SETFCAP \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined ...
```

### Checksums Don't Match

**Common causes:**

1. **Wrong timestamp**: Use exact epoch from official artifacts
   ```bash
   cat ./official-amd64/debuerreotype-epoch
   ```

2. **Wrong debuerreotype version**: Must use v0.16
   ```bash
   cd debuerreotype && git describe --tags  # Should show: 0.16
   ```

3. **Disk space**: Need ~5GB per suite
   ```bash
   df -h .
   ```

### Out of Disk Space

```bash
docker system prune -a
rm -rf ./output/*
```

### Cross-Architecture Build Issues

#### Architecture Not Detected

Error: `Architecture 'amd64' is not supported by your Docker environment`

**Solution**: `verify-local.sh` automatically installs binfmt emulation. If auto-setup fails:

**macOS (Colima):**
```bash
# Check configuration
cat ~/.colima/default/colima.yaml | grep -E "(rosetta|binfmt)"
# Should show: rosetta: false, binfmt: true

# Recreate if wrong
colima delete && colima start  # Defaults correct

# Or install manually
docker run --rm --privileged tonistiigi/binfmt --install all
```

#### Rosetta Errors (macOS)

Error: `rosetta error: Unable to open /proc/self/exe: 40` or `Trace/breakpoint trap`

**Cause**: Rosetta enabled in Colima conflicts with build operations.

**Solution**:
```bash
# Check Rosetta status
cat ~/.colima/default/colima.yaml | grep rosetta

# Disable and restart
colima stop
# Edit ~/.colima/default/colima.yaml: set rosetta: false
colima start

# Or recreate
colima delete && colima start  # Defaults: rosetta: false
```

**Why**: Rosetta has `/proc/self/exe` access issues during builds. QEMU (binfmt) is more compatible.

#### Linux: Cross-Architecture Setup

```bash
# Install QEMU user-mode emulation
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Verify
docker run --rm arm64v8/alpine uname -m  # Should output: aarch64
docker run --rm amd64/alpine uname -m    # Should output: x86_64
```

#### Architecture Not Supported

Error: `Architecture 'X' is not supported by your Docker environment`

**Solution**: Install binfmt emulation:

```bash
docker run --rm --privileged tonistiigi/binfmt --install all
```

## Directory Structure

```
debian-repro/
├── scripts/           # Verification scripts
├── tests/            # BATS test suite
├── docs/             # Documentation guides
├── dashboard/        # Web dashboard (GitHub Pages)
├── debuerreotype/    # Cloned tool (local only)
├── output/           # Build artifacts (gitignored)
├── official-*/       # Official parameters (gitignored)
└── results/          # Verification results (gitignored)
```

## Performance Tips

- **Cache debuerreotype**: Keep directory between runs
- **Cache Docker image**: Build once, reuse many times
- **Use parallel builds**: 2-3x speedup for multiple suites
- **Use local SSD**: Faster than network mounts
- **Allocate resources**: Increase Docker Desktop CPU/memory

## Common Workflows

### Daily Verification
```bash
./verify-local.sh
```

### Compare Architectures
```bash
for arch in amd64 arm64; do
  ./scripts/fetch-official.sh --arch "$arch" --output-dir "./official-$arch"
  # Build and verify...
done
```

### Historical Verification
```bash
# Verify older builds
git clone https://github.com/debuerreotype/docker-debian-artifacts.git
cd docker-debian-artifacts
git checkout $(git rev-list -n 1 --before="2024-10-01" dist-amd64)
# Extract serial and epoch from this commit
```

## Getting Help

- **Script help**: `./scripts/fetch-official.sh --help`
- **Working examples**: Check `.github/workflows/`
- **Issues**: https://github.com/sheurich/debian-repro/issues
- **Debuerreotype docs**: https://github.com/debuerreotype/debuerreotype
