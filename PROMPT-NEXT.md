# Debian Reproducibility - Next Phase Implementation

## Context

The Debian reproducibility verification system is fully functional with core features implemented. This document outlines the next phase: implementing smart verification and cross-platform reproducibility testing.

## Objective

Enhance the system with two major features:
1. **Smart Verification**: Only verify when official artifacts are updated (not on a fixed schedule)
2. **Daily Cross-Platform Reproducibility**: Build daily with current timestamps on both GitHub Actions and Google Cloud Build to verify platform-independent reproducibility

## Prerequisites - MUST COMPLETE FIRST

Before implementing the features in this document, you must complete the GCP setup:

### 1. Review Existing Implementation
- Read `PROMPT.md` for full context on current architecture
- Review existing workflows in `.github/workflows/`
- Understand modular scripts in `scripts/`

### 2. Execute GCP Setup (Required)
On a host with `gcloud` CLI configured:
```bash
# 1. Edit the script to set your PROJECT_ID
nano gcp-setup-commands.sh
# Change: PROJECT_ID="your-actual-project-id"

# 2. Run the setup script
chmod +x gcp-setup-commands.sh
./gcp-setup-commands.sh

# 3. Save the output values (you'll need these for GitHub)
```

### 3. Configure GitHub Repository
Add the following to your repository settings at `https://github.com/sheurich/debian-repro/settings/secrets/actions`:

**Repository Variables** (Settings → Secrets and variables → Actions → Variables tab):
- `GCP_PROJECT_ID` - Your GCP project ID
- `GCP_RESULTS_BUCKET` - Format: `{project-id}-debian-repro-results`

**For Workload Identity Federation** (Recommended):
- `GCP_WIF_PROVIDER` - The provider string from script output
- `GCP_WIF_SERVICE_ACCOUNT` - The service account email

**For Service Account Key** (Alternative if WIF not available):
- `GCP_SA_KEY` - The base64-encoded key from script output (add as Secret, not Variable)

### 4. Verify Setup
```bash
# Test that GCP authentication works
gh workflow run test-gcp-auth.yml

# Check the workflow run
gh run list --workflow=test-gcp-auth.yml
```

The test should show:
- Authentication successful
- Cloud Build API accessible
- GCS bucket accessible
- Test build completed

**Only proceed with implementation after all prerequisites pass.**

## Current State

### Implemented
- Complete verification system with modular scripts
- GitHub Actions workflow running weekly
- Google Cloud Build configuration
- Public dashboard with status badges
- GCP authentication infrastructure (Workload Identity Federation)
- Test workflow for GCP authentication (`test-gcp-auth.yml`)

### GCP Resources Configured
- Service account: `debian-repro-ci@{project-id}.iam.gserviceaccount.com`
- GCS bucket: `{project-id}-debian-repro-results`
- Workload Identity Federation pool: `github-actions`
- IAM roles: `cloudbuild.builds.editor`, `storage.objectViewer`, `storage.objectCreator`

## Implementation Tasks

### Task 1: Smart Verification Workflow

**Goal**: Detect changes in official artifacts and trigger verification only when needed.

**Create `.github/workflows/check-official-updates.yml`:**

```yaml
name: Check Official Updates

on:
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours
  workflow_dispatch:

permissions:
  contents: write

jobs:
  check:
    name: Check for Official Updates
    runs-on: ubuntu-24.04
    outputs:
      has_updates: ${{ steps.compare.outputs.has_updates }}
      architectures: ${{ steps.compare.outputs.architectures }}
```

**Key Implementation Points:**
1. Use `git ls-remote` to check commit SHAs (lightweight, no clone)
2. Track state in `docs/data/official-state.json`
3. Compare current vs stored state
4. Trigger main workflow only on changes
5. Commit state updates to track history

**Files to Create:**
- `.github/workflows/check-official-updates.yml`
- `docs/data/official-state.json` (initial empty state)

**Modify Existing:**
- `.github/workflows/reproducible-debian-build.yml`: Add `workflow_call` trigger

### Task 2: Update Cloud Build for GCS Export

**Goal**: Modify `cloudbuild.yaml` to export checksums to GCS for comparison.

**Add to `cloudbuild.yaml`:**

```yaml
substitutions:
  _RESULTS_BUCKET: '${PROJECT_ID}-debian-repro-results'

steps:
  # ... existing steps ...

  - name: 'gcr.io/cloud-builders/gsutil'
    id: 'export-checksums'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        # Create JSON with checksums
        # Upload to gs://${_RESULTS_BUCKET}/${BUILD_DATE}/${_ARCH}/cloud-build-results.json
```

**Implementation Requirements:**
1. Export checksums as JSON after verification
2. Use predictable GCS paths: `YYYYMMDD/arch/cloud-build-results.json`
3. Include build metadata (timestamp, build ID, serial)
4. Handle multiple suites in single JSON

### Task 3: Daily Cross-Platform Verification

**Goal**: Build daily with current timestamp on both platforms and compare.

**Create `.github/workflows/daily-cross-platform-verification.yml`:**

```yaml
name: Daily Cross-Platform Verification

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 06:00 UTC
  workflow_dispatch:
    inputs:
      date:
        description: 'Date for timestamp (YYYY-MM-DD)'
        default: 'today'

env:
  GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
  GCP_RESULTS_BUCKET: ${{ vars.GCP_RESULTS_BUCKET }}

jobs:
  generate-timestamp:
    # Generate daily timestamp

  trigger-cloud-build:
    # Submit Cloud Build with timestamp

  build-github:
    # Build on GitHub Actions

  wait-and-compare:
    # Wait for both, compare results
```

**Implementation Flow:**
1. Generate timestamp for current day (midnight UTC)
2. Trigger Cloud Build asynchronously
3. Build on GitHub Actions in parallel
4. Both write checksums to GCS
5. Comparison job waits for both results
6. Generate daily reproducibility report

**GCS Structure:**
```
gs://bucket/daily/
├── YYYYMMDD/
│   ├── amd64/
│   │   ├── github-actions-results.json
│   │   └── cloud-build-results.json
│   └── arm64/
│       ├── github-actions-results.json
│       └── cloud-build-results.json
```

### Task 4: Create Daily Build Cloud Build Config

**Create `cloudbuild-daily.yaml`:**

Similar to existing `cloudbuild.yaml` but:
1. Uses provided timestamp instead of official
2. Exports to daily/ path in GCS
3. Only builds bookworm for speed
4. Includes platform identifier in results

### Task 5: Implement Comparison Logic

**Create `scripts/compare-cross-platform.sh`:**

```bash
#!/usr/bin/env bash
# Compare checksums between GitHub Actions and Cloud Build

compare_results() {
  local gh_file="$1"
  local cb_file="$2"

  # Extract and compare SHA256
  # Generate comparison report
  # Return 0 if match, 1 if different
}
```

**Features:**
1. Download both JSON files from GCS
2. Compare SHA256 for each suite
3. Generate markdown report
4. Update daily reproducibility badge
5. Store historical data

### Task 6: Daily Reproducibility Dashboard

**Update `docs/` dashboard:**

1. Add daily reproducibility chart
2. Show 30-day trend
3. Per-platform success rates
4. Cross-platform match percentage

**Create `docs/data/daily-history.json`:**
```json
[
  {
    "date": "2024-11-06",
    "reproducibility_rate": 100,
    "platforms": {
      "github": { "success": true },
      "cloud_build": { "success": true }
    },
    "cross_platform_match": true
  }
]
```

**Update badges:**
- `docs/badges/daily-reproducibility.json`
- `docs/badges/cross-platform.json`

### Task 7: Analysis Scripts

**Create `scripts/analyze-daily-reproducibility.sh`:**

```bash
#!/usr/bin/env bash
# Analyze daily reproducibility trends

main() {
  # Download last 30 days from GCS
  # Calculate statistics
  # Generate report
  # Update badges
}
```

**Features:**
1. Fetch historical data from GCS
2. Calculate rolling averages
3. Identify patterns (failures on specific days/architectures)
4. Generate trend report
5. Alert on degradation

### Task 8: Update Documentation

**Update `README.md`:**
- Add daily reproducibility badge
- Document cross-platform verification
- Add GCP setup prerequisites

**Create `docs/cross-platform-verification.md`:**
- Explain dual-build approach
- Document GCS structure
- Troubleshooting guide
- Performance considerations

## Testing Strategy

### Manual Testing

1. **Test Smart Verification:**
   ```bash
   gh workflow run check-official-updates.yml
   # Verify it detects current state
   # Manually change official-state.json
   # Verify it triggers main workflow
   ```

2. **Test Cross-Platform Build:**
   ```bash
   gh workflow run daily-cross-platform-verification.yml \
     -f date=2024-11-06
   # Verify both platforms build
   # Check GCS for results
   # Verify comparison works
   ```

3. **Test GCS Operations:**
   ```bash
   # Upload test file
   gsutil cp test.json gs://bucket/test/
   # Download and verify
   gsutil cat gs://bucket/test/test.json
   ```

### Automated Testing

**Create `tests/integration/cross-platform.bats`:**

```bash
@test "compare identical checksums" {
  # Test comparison logic
}

@test "detect checksum mismatch" {
  # Test failure detection
}

@test "handle missing results" {
  # Test error handling
}
```

## Configuration Requirements

### GitHub Secrets/Variables

Already configured (from GCP setup):
- `GCP_PROJECT_ID` (variable)
- `GCP_RESULTS_BUCKET` (variable)
- `GCP_WIF_PROVIDER` (variable)
- `GCP_WIF_SERVICE_ACCOUNT` (variable)

### GCS Bucket Structure

Create these paths:
```bash
gsutil mkdir gs://${BUCKET}/daily/
gsutil mkdir gs://${BUCKET}/official-checks/
gsutil mkdir gs://${BUCKET}/builds/
```

## Implementation Order

1. **Week 1: Smart Verification**
   - Implement check-official-updates.yml
   - Test change detection
   - Verify trigger mechanism

2. **Week 2: Cloud Build GCS Export**
   - Update cloudbuild.yaml
   - Test checksum export
   - Verify GCS permissions

3. **Week 3: Daily Cross-Platform**
   - Create daily workflow
   - Implement both platform builds
   - Test GCS writes

4. **Week 4: Comparison & Reporting**
   - Implement comparison logic
   - Update dashboard
   - Add historical tracking

## Success Criteria

The implementation is complete when:

1. **Smart Verification**:
   - Runs every 4 hours
   - Only triggers on changes
   - Tracks state reliably
   - Handles all architectures

2. **Daily Cross-Platform**:
   - Builds daily at 06:00 UTC
   - Both platforms complete successfully
   - Results stored in GCS
   - Comparison identifies mismatches

3. **Monitoring**:
   - Daily reproducibility badge updates
   - Dashboard shows trends
   - Historical data retained 30 days
   - Alerts on failures

## Troubleshooting Guide

### Common Issues

1. **GCS Permission Denied**:
   - Verify service account has objectCreator role
   - Check bucket IAM bindings
   - Ensure Workload Identity is configured

2. **Cloud Build Not Triggering**:
   - Check gcloud authentication
   - Verify project ID is correct
   - Check Cloud Build API is enabled

3. **Checksum Mismatch Between Platforms**:
   - Verify same timestamp used
   - Check Docker versions match
   - Ensure same debuerreotype version

4. **Workflow Timeouts**:
   - Increase timeout in workflow
   - Check for network issues
   - Verify QEMU for ARM builds

## Performance Considerations

1. **Optimize Change Detection**:
   - Cache git ls-remote results
   - Batch architecture checks
   - Use minimal API calls

2. **Parallel Execution**:
   - Submit all Cloud Builds simultaneously
   - Run GitHub matrix builds in parallel
   - Async GCS uploads

3. **Storage Optimization**:
   - 30-day retention policy
   - Compress historical data
   - Store only checksums, not full artifacts

## Security Notes

1. **Workload Identity Federation**:
   - No long-lived keys
   - Automatic rotation
   - Repository-scoped access

2. **Least Privilege**:
   - Service account has minimal roles
   - No project owner permissions
   - Read-only where possible

3. **Data Integrity**:
   - Sign commits with GPG
   - Verify checksums at every step
   - Audit trail in GCS

## Expected Outcomes

After implementation:

1. **Resource Efficiency**: 75% reduction in unnecessary CI runs
2. **Daily Status**: Reproducibility status updated daily
3. **Platform Independence**: Verify builds work across CI systems
4. **Historical Data**: Track trends and patterns over time
5. **Faster Detection**: Find reproducibility issues within 4 hours