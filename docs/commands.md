# Command Reference

Common commands for triggering builds, local development, and consensus validation.

## Triggering Builds

### GitHub Actions (manual)

```bash
gh workflow run reproducible-debian-build.yml \
  -f suites='bookworm trixie' \
  -f architectures='amd64,arm64' \
  -f verify_only=true
```

### Google Cloud Build

```bash
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SUITE=bookworm,_ARCHITECTURES="amd64 arm64"
```

## Local Development

Requires Debuerreotype clone. See [local-setup.md](local-setup.md) for details.

### Fetch official parameters

```bash
git clone --depth 1 --branch dist-amd64 \
  https://github.com/debuerreotype/docker-debian-artifacts.git official-amd64
cat official-amd64/serial
cat official-amd64/debuerreotype-epoch
```

### Build rootfs

```bash
./docker-run.sh ./examples/debian.sh \
  --arch amd64 output bookworm 2025-10-20T00:00:00Z
```

### Verify checksums

```bash
# Your local build (debuerreotype creates nested structure)
cat output/20251020/amd64/bookworm/rootfs.tar.xz.sha256

# Official build (flat structure in dist-* branch)
curl -sL https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts/dist-amd64/bookworm/rootfs.tar.xz.sha256

# Or compare directly
sha256sum output/20251020/amd64/bookworm/rootfs.tar.xz
```

## Consensus Validation

Full consensus required: ALL platforms must produce identical checksums.

### Cross-platform verification

```bash
# Collect results from all platforms for a serial
./scripts/collect-results.sh \
  --serial 20251020 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# Validate consensus (requires full agreement)
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --output consensus-report.json
```

### Automated consensus check

```bash
# Trigger consensus validator workflow
gh workflow run consensus-validator.yml -f serial=20251020

# Watch progress
gh run watch

# View consensus report in artifacts
gh run download <run-id> -n consensus-report
```

### Features

- Multi-platform collection in single run
- Automatic format normalization
- Full consensus required
- Exit code 0 = consensus, non-zero = disagreement
