Debuerreotype is the official tool used to build all Debian Docker images on Docker Hub (docker.io/library/debian). Here's how to create identical images:

Step 1: Find the Official Build Parameters

The official builds use specific timestamps stored in the https://github.com/debuerreotype/docker-debian-artifacts repository:

# Clone the official artifacts repository for your architecture
git clone --depth 1 --branch dist-amd64 \
  https://github.com/debuerreotype/docker-debian-artifacts.git \
  official-amd64

# Get the timestamp used for official builds
cat official-amd64/bookworm/rootfs.debuerreotype-epoch
# Example output: 1760918400

# Convert to ISO 8601 format
date -r 1760918400 -u '+%Y-%m-%dT%H:%M:%SZ'
# Example output: 2025-10-20T00:00:00Z

Step 2: Build the Rootfs Tarball

Use the exact timestamp from the official build:

# Build Debian bookworm (stable) - matches official image
./docker-run.sh ./examples/debian.sh \
  --arch amd64 \
  output \
  bookworm \
  2025-10-20T00:00:00Z

# This creates:
# output/20251020/amd64/bookworm/rootfs.tar.xz (standard variant)
# output/20251020/amd64/bookworm/slim/rootfs.tar.xz (slim variant)

Step 3: Verify It Matches Official Build

Compare SHA256 checksums to ensure bit-for-bit reproducibility:

# Your local build
cat output/20251020/amd64/bookworm/rootfs.tar.xz.sha256

# Official build
curl -sL https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts/dist-amd64/bookworm/rootfs.tar.xz.sha256

# These must be IDENTICAL

Step 4: Convert to Docker Image

# Create OCI/Docker image from rootfs
./examples/oci-image.sh \
  output/debian-bookworm.tar \
  output/20251020/amd64/bookworm

# Load into Docker
docker load < output/debian-bookworm.tar

# Test it
docker run --rm debian:bookworm cat /etc/debian_version

Building All Official Variants

All Current Debian Releases

# Builds unstable, testing, stable, oldstable, oldoldstable
./docker-run.sh ./examples/debian-all.sh \
  --arch amd64 \
  output \
  2025-10-20T00:00:00Z

Multiple Architectures

# Official architectures
for arch in amd64 arm64 armhf i386 ppc64el s390x; do
  ./docker-run.sh ./examples/debian.sh \
    --arch "$arch" \
    output \
    bookworm \
    2025-10-20T00:00:00Z
done

Key Points for Identical Builds

1. Use the EXACT timestamp from the official artifacts repository - this is critical for reproducibility
2. The SHA256 must match - if it doesn't, you're not building identically
3. Don't modify any scripts - use debuerreotype as-is
4. Use docker-run.sh wrapper - it sets up the proper build environment with required capabilities

Current Official Build Parameters (October 2025)

- Timestamp: 2025-10-20T00:00:00Z
- Epoch: 1760918400
- Snapshot URL: http://snapshot.debian.org/archive/debian/20251020T000000Z/
- Active Suites: trixie (testing/stable), bookworm (oldstable), bullseye (oldoldstable)

Why This Works

Debuerreotype ensures reproducibility through:
- Snapshot.debian.org: Fetches packages from a specific point in time
- SOURCE_DATE_EPOCH: All timestamps normalized to the build epoch
- Deterministic tar: Files sorted alphabetically, numeric owners, excluded non-deterministic content
- Fixup process: Removes logs, machine IDs, and other variable content

The official Debian Docker images are built monthly (or when security updates require) using Jenkins at https://doi-janky.infosiftr.net/job/tianon/job/debuerreotype/, and the artifacts
 are pushed to the docker-debian-artifacts repository on GitHub.
