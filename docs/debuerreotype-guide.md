# Building Debian Docker Images with Debuerreotype

Debuerreotype builds the official Debian Docker images on Docker Hub. This guide shows how to create identical images and verify official images remain untampered.

## Prerequisites

Clone Debuerreotype v0.16:
```bash
git clone --branch v0.16 https://github.com/debuerreotype/debuerreotype.git
cd debuerreotype
```

## Step 1: Get Official Build Parameters

Clone the artifacts repository for your architecture:
```bash
git clone --depth 1 --branch dist-amd64 \
  https://github.com/debuerreotype/docker-debian-artifacts.git \
  official-amd64
```

Extract the timestamp:
```bash
cat official-amd64/bookworm/rootfs.debuerreotype-epoch
# Output: 1760918400

date -r 1760918400 -u '+%Y-%m-%dT%H:%M:%SZ'
# Output: 2025-10-20T00:00:00Z
```

## Step 2: Build the Rootfs

Build with the exact official timestamp:
```bash
./docker-run.sh ./examples/debian.sh \
  --arch amd64 \
  output \
  bookworm \
  2025-10-20T00:00:00Z
```

This creates:
- `output/20251020/amd64/bookworm/rootfs.tar.xz` (standard)
- `output/20251020/amd64/bookworm/slim/rootfs.tar.xz` (slim)

## Step 3: Verify Reproducibility

Compare SHA256 checksums:
```bash
# Your build
cat output/20251020/amd64/bookworm/rootfs.tar.xz.sha256

# Official build
curl -sL https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts/dist-amd64/bookworm/rootfs.tar.xz.sha256
```

Checksums must match exactly for reproducibility.

## Step 4: Create Docker Image

Convert rootfs to Docker image:
```bash
./examples/oci-image.sh \
  output/debian-bookworm.tar \
  output/20251020/amd64/bookworm

docker load < output/debian-bookworm.tar
docker run --rm debian:bookworm cat /etc/debian_version
```

## Building Multiple Variants

### All Debian Releases
```bash
./docker-run.sh ./examples/debian-all.sh \
  --arch amd64 \
  output \
  2025-10-20T00:00:00Z
```

Builds: unstable, testing, stable, oldstable, oldoldstable

### Multiple Architectures
```bash
for arch in amd64 arm64 armhf i386 ppc64el s390x; do
  ./docker-run.sh ./examples/debian.sh \
    --arch "$arch" \
    output \
    bookworm \
    2025-10-20T00:00:00Z
done
```

## Requirements for Reproducibility

1. **Exact timestamp**: Use the timestamp from the official artifacts repository
2. **Matching checksums**: SHA256 must match the official build
3. **Unmodified scripts**: Use debuerreotype as-is
4. **Docker environment**: Use `docker-run.sh` for proper capabilities

## Current Official Parameters (October 2025)

- Timestamp: `2025-10-20T00:00:00Z`
- Epoch: `1760918400`
- Snapshot: `http://snapshot.debian.org/archive/debian/20251020T000000Z/`
- Suites: trixie (testing/stable), bookworm (oldstable), bullseye (oldoldstable)

## How Debuerreotype Ensures Reproducibility

Debuerreotype achieves bit-for-bit reproducibility through:

- **Snapshot.debian.org**: Fetches packages from a specific timestamp
- **SOURCE_DATE_EPOCH**: Normalizes all timestamps
- **Deterministic tar**: Sorts files alphabetically with numeric owners
- **Fixup process**: Removes logs, machine IDs, and variable content

The official builds run monthly via Jenkins at https://doi-janky.infosiftr.net/job/tianon/job/debuerreotype/, with artifacts pushed to GitHub.