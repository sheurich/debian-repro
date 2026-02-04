# Task: Fix Debuerreotype Version Mismatch (debian-repro-6y8)

## Priority: P0 (Critical - Blocking)

## Problem

GitHub Actions uses debuerreotype commit `e044a8f` (post-0.16 with distro-info-data fix), while GCP cloudbuild.yaml and verify-local.sh use tag `0.16`. This version divergence makes consensus validation impossible.

## Evidence

- `.github/workflows/reproducible-debian-build.yml` line 35: `DEBUERREOTYPE_VERSION: 'e044a8f'`
- `cloudbuild.yaml` line 15: `_DEBUERREOTYPE_VERSION: '0.16'`
- `verify-local.sh` line 151: `DEBUERREOTYPE_VERSION="0.16"`

## Required Changes

### 1. Update cloudbuild.yaml

Change line 15 from:
```yaml
_DEBUERREOTYPE_VERSION: '0.16'
```
To:
```yaml
_DEBUERREOTYPE_VERSION: 'e044a8f'
```

Also update the git clone command in step 'setup-debuerreotype' (around line 84) since `--branch` works for tags but commit SHAs need:
```bash
git clone https://github.com/debuerreotype/debuerreotype.git
cd debuerreotype
git checkout "${_DEBUERREOTYPE_VERSION}"
```

### 2. Update verify-local.sh

Change line 151 from:
```bash
DEBUERREOTYPE_VERSION="0.16"
```
To:
```bash
DEBUERREOTYPE_VERSION="e044a8f"
```

Also update the checkout command around line 364 from:
```bash
git checkout "refs/tags/${DEBUERREOTYPE_VERSION}"
```
To:
```bash
git checkout "${DEBUERREOTYPE_VERSION}"
```

### 3. Update docs/security.md

Update the Trust Dependencies table to reflect the new version:
```markdown
| **Debuerreotype e044a8f** | Official Debian image builder | Pinned commit, verified checkout |
```

## Verification

After changes:
1. Run `shellcheck verify-local.sh` - must pass
2. Run `yamllint cloudbuild.yaml` - must pass (or note yaml quirks)
3. Verify version strings are consistent across all 3 files

## Commit Message

```
fix(consensus): synchronize Debuerreotype version across all platforms

GitHub Actions uses commit e044a8f (post-0.16 with distro-info-data fix)
while GCP and local verification used tag 0.16. This version mismatch
made cross-platform consensus impossible.

Updates:
- cloudbuild.yaml: use e044a8f instead of 0.16
- verify-local.sh: use e044a8f instead of 0.16
- docs/security.md: reflect correct version in trust table

Closes: debian-repro-6y8
```

## After Completion

Run: `bd close debian-repro-6y8`
