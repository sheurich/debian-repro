# Local Setup Guide

Run Debian reproducibility verification locally without CI/CD.

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

# macOS: Ensure Docker Desktop is running
```

### Optional Tools

```bash
# Testing: bats
# Linting: shellcheck, yamllint
# Parallel builds: parallel
```

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

```bash
# ARM64 requires QEMU on x86_64
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Build for ARM64
./scripts/fetch-official.sh --arch arm64 --output-dir ./official-arm64
EPOCH=$(cat ./official-arm64/epoch.txt)

./scripts/build-suite.sh \
  --suite bookworm \
  --arch arm64 \
  --epoch "$EPOCH" \
  --output-dir ./output \
  --image debuerreotype:0.16
```

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

# macOS
open -a Docker  # Start Docker Desktop
```

### Build Fails: SYS_ADMIN Required

Debuerreotype needs elevated privileges. The scripts handle this automatically. If running Docker manually:

```bash
docker run \
  --cap-add SYS_ADMIN \
  --cap-drop SETFCAP \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  ...
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

### ARM64 Builds Fail on x86_64

```bash
# Install QEMU
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Verify
docker run --rm arm64v8/alpine uname -m  # Should output: aarch64
```

## Directory Structure

```
debian-repro/
├── scripts/           # Verification scripts
├── tests/            # BATS test suite
├── docs/             # Documentation and dashboard
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