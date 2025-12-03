# Docker Hub Registry Verification

Detect registry tampering by comparing Docker Hub images against `docker-debian-artifacts` checksums.

## Overview

This feature closes the trust gap between the `docker-debian-artifacts` repository and Docker Hub. The main build workflow verifies that local rebuilds match the artifacts repository. Registry verification confirms that Docker Hub serves the same images.

```
Local Rebuild ─────┐
                   ├──> docker-debian-artifacts <──> Docker Hub
Official Build ────┘                                      ↑
                                                          │
                                        Registry verification closes this gap
```

## How It Works

### Checksum Comparison

Docker Hub stores images with layer metadata including `diff_id`—the SHA256 checksum of the **uncompressed** filesystem tarball. The artifacts repository stores OCI manifests with embedded diff_ids.

To compare:

```bash
# From Docker Hub (via crane):
crane config --platform linux/amd64 debian:bookworm | jq -r '.rootfs.diff_ids[0]'
# Returns: sha256:abc123...

# From artifacts repository OCI manifest:
# Structure: oci/index.json → manifests[0].data (base64) → config.data (base64) → rootfs.diff_ids[0]
jq -r '.manifests[0].data' bookworm/oci/index.json | base64 -d | jq -r '.config.data' | base64 -d | jq -r '.rootfs.diff_ids[0]'
# Returns: sha256:abc123...
```

A match proves Docker Hub serves the exact filesystem from the artifacts repository.

### Architecture Mapping

| Debian Arch | Docker Platform | Docker Hub Image |
|-------------|-----------------|------------------|
| amd64 | linux/amd64 | debian:suite |
| arm64 | linux/arm64/v8 | arm64v8/debian:suite |
| armhf | linux/arm/v7 | arm32v7/debian:suite |
| i386 | linux/386 | i386/debian:suite |
| ppc64el | linux/ppc64le | ppc64le/debian:suite |

## Usage

### Automated Verification

The workflow runs daily at 2 AM UTC:

```yaml
on:
  schedule:
    - cron: '0 2 * * *'
```

### Manual Trigger

```bash
# Verify all default architectures
gh workflow run registry-verification.yml

# Verify specific architectures
gh workflow run registry-verification.yml -f architectures=amd64,arm64

# Verify specific suites
gh workflow run registry-verification.yml -f suites="bookworm trixie"
```

### Local Verification

```bash
# Fetch official artifacts
./scripts/fetch-official.sh --arch amd64 --output-dir official-amd64

# Verify against Docker Hub
./scripts/verify-registry.sh \
  --arch amd64 \
  --artifacts-dir official-amd64 \
  --output results.json
```

## Output Format

```json
{
  "timestamp": "2025-12-03T12:00:00Z",
  "serial": "20251103",
  "architecture": "amd64",
  "status": "pass",
  "results": [
    {
      "suite": "bookworm",
      "status": "match",
      "dockerhub_diffid": "sha256:abc...",
      "artifacts_diffid": "sha256:abc...",
      "image": "debian:bookworm",
      "platform": "linux/amd64"
    }
  ],
  "summary": {
    "total": 4,
    "matched": 4,
    "mismatched": 0
  }
}
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All images match |
| 1 | One or more mismatches |
| 2 | Invalid arguments |
| 3 | Network or tool error |

## Investigation

### Mismatch Detected

A mismatch indicates one of:

1. **Docker Hub tampering** — Images modified after publication
2. **Artifacts repository tampering** — Source checksums modified
3. **Build timing** — Different serial versions between artifacts and Docker Hub

### Steps

1. Check the serial numbers match between artifacts and Docker Hub
2. Compare the specific diff_ids in the report
3. Pull the image locally and inspect: `docker pull debian:bookworm && docker inspect`
4. Check recent commits to `docker-debian-artifacts` repository
5. Report findings to Debian security team if tampering suspected

## Dependencies

- **crane** — Google's container registry tool (daemonless)
- **jq** — JSON processor

Install crane:

```bash
# Linux
curl -sL https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz | tar xz crane
sudo mv crane /usr/local/bin/

# macOS
brew install crane
```

## Dashboard Integration

Registry verification status appears on the dashboard:

- **Badge**: `dashboard/badges/registry-verification.json`
- **Latest results**: `dashboard/data/registry-latest.json`
- **History**: `dashboard/data/registry-history.json` (90 days)

## Trust Model

This verification:

- **Detects**: Docker Hub image tampering, registry substitution attacks
- **Requires trust in**: `docker-debian-artifacts` repository as source of truth
- **Does not detect**: Upstream source compromise, compiler backdoors

Combined with build verification, this provides end-to-end integrity from source packages to Docker Hub.
