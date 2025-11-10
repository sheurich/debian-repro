# Consensus Validation Guide

## Overview

Cross-platform consensus validation ensures no single CI system can be compromised without detection. This guide explains how to use the consensus validation tools to verify agreement across independent build platforms.

## Prerequisites

- GitHub CLI (`gh`) for accessing GitHub artifacts
- Google Cloud SDK (`gcloud`) for accessing GCS artifacts (optional)
- `jq` for JSON processing
- Authentication to GCP (if using Google Cloud Build results)

## Quick Start

### Automated Validation (Recommended)

The consensus-validator workflow runs automatically weekly after builds:

```bash
# Manual trigger for specific serial
gh workflow run consensus-validator.yml -f serial=20251103

# View results
gh run list --workflow=consensus-validator.yml --limit 5
gh run view <run-id>
```

### Manual Validation

When you need to validate consensus outside the automated workflow:

```bash
# 1. Collect results from all platforms
./scripts/collect-results.sh \
  --serial 20251103 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir consensus-results

# 2. Compare and validate
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --threshold 2 \
  --output consensus-report.json

# 3. View results
cat consensus-report.json | jq
```

## Understanding the Scripts

### collect-results.sh

Fetches verification reports from multiple platforms.

**Key Features:**
- Multi-platform collection in single run (fixed in commit 3ba3cbf)
- Supports GitHub Pages dashboard data
- Supports GitHub Actions workflow artifacts
- Supports Google Cloud Storage buckets
- Automatic retry on transient failures
- Exit code 0 on successful collection

**Parameters:**
- `--serial SERIAL` - Debian serial to collect (required)
- `--github-repo REPO` - GitHub repository (format: owner/repo)
- `--gcp-project PROJECT` - GCP project ID
- `--gcp-bucket BUCKET` - GCS bucket path (default: PROJECT_cloudbuild/debian-reproducible)
- `--output-dir DIR` - Directory to save results (default: consensus-results)
- `--platforms PLATFORMS` - Comma-separated platforms to collect (default: github,gcp)

**Examples:**

Collect from both platforms:
```bash
./scripts/collect-results.sh \
  --serial 20251103 \
  --github-repo sheurich/debian-repro \
  --gcp-project debian-repro-oxide \
  --output-dir /tmp/consensus
```

Collect from GitHub only:
```bash
./scripts/collect-results.sh \
  --serial 20251103 \
  --github-repo sheurich/debian-repro \
  --platforms github \
  --output-dir /tmp/consensus
```

### compare-platforms.sh

Validates consensus across collected platform results.

**Key Features:**
- Automatic format normalization (fixed in commit 3ba3cbf)
  - GitHub nested format: `.architectures.{arch}.suites.{suite}`
  - GCP array format: `.results[]`
- Configurable consensus threshold
- Detailed comparison reports
- Witness evidence for disagreements
- Exit code 0 = consensus achieved

**Parameters:**
- `--results-dir DIR` - Directory with collected results (required)
- `--threshold N` - Minimum platforms that must agree (default: 2)
- `--strict` - Require all platforms to match (optional)
- `--output FILE` - Output file for report (default: stdout)
- `--generate-evidence` - Create witness evidence files for disagreements

**Examples:**

Basic comparison:
```bash
./scripts/compare-platforms.sh \
  --results-dir ./consensus-results \
  --threshold 2 \
  --output consensus-report.json
```

Strict mode (all platforms must match):
```bash
./scripts/compare-platforms.sh \
  --results-dir ./consensus-results \
  --strict \
  --output consensus-report.json
```

With evidence generation:
```bash
./scripts/compare-platforms.sh \
  --results-dir ./consensus-results \
  --generate-evidence \
  --output consensus-report.json
```

## Understanding Results

### Successful Consensus

When platforms agree:
```json
{
  "timestamp": "2025-11-09T22:41:50Z",
  "consensus": {
    "achieved": true,
    "threshold": 2,
    "require_all_match": false
  },
  "summary": {
    "total_combinations": 8,
    "consensus_achieved": 8,
    "disagreements": 0,
    "consensus_rate": 1
  },
  "platforms": [
    "github-20251103.json",
    "gcp-20251103-amd64.json"
  ],
  "comparisons": [
    {
      "architecture": "amd64",
      "suite": "bookworm",
      "consensus": true,
      "consensus_checksum": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba",
      "platforms_agreeing": 2,
      "platforms_total": 2,
      "platform_results": [
        {
          "platform": "github-20251103.json",
          "sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba"
        },
        {
          "platform": "gcp-20251103-amd64.json",
          "sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba"
        }
      ],
      "disagreement": false
    }
  ]
}
```

### Failed Consensus

When platforms disagree:
```json
{
  "consensus": {
    "achieved": false,
    "threshold": 2
  },
  "summary": {
    "total_combinations": 8,
    "consensus_achieved": 7,
    "disagreements": 1,
    "consensus_rate": 0.875
  },
  "comparisons": [
    {
      "architecture": "arm64",
      "suite": "trixie",
      "consensus": false,
      "platforms_total": 2,
      "platforms_agreeing": 0,
      "platform_results": [
        {
          "platform": "github-20251103.json",
          "sha256": "abc123..."
        },
        {
          "platform": "gcp-20251103-amd64.json",
          "sha256": "def456..."
        }
      ],
      "disagreement": true
    }
  ]
}
```

## Troubleshooting

### Collection Failures

**Symptom:** `collect-results.sh` exits with non-zero code

**Common Causes:**
1. Platform artifacts not yet available
2. Network connectivity issues
3. Authentication problems (GCP)
4. Serial not found in any platform

**Solutions:**

Check if serial exists in GitHub dashboard:
```bash
curl -s https://sheurich.github.io/debian-repro/data/latest.json | jq '.serial'
```

Verify GCP authentication:
```bash
gcloud auth list
gcloud config get-value project
```

Test GCS bucket access:
```bash
gsutil ls gs://debian-repro-oxide_cloudbuild/debian-reproducible/ | head -5
```

### Consensus Disagreements

**Symptom:** `compare-platforms.sh` reports consensus failure

**Investigation Steps:**

1. **Check witness evidence:**
```bash
jq '.comparisons[] | select(.disagreement == true)' consensus-report.json
```

2. **Verify build parameters match:**
```bash
# Compare epochs across platforms
jq '.epoch' consensus-results/github-*.json
jq '.epoch' consensus-results/gcp-*.json
```

3. **Review build logs:**

GitHub Actions:
```bash
gh run list --workflow=reproducible-debian-build.yml --limit 5
gh run view <run-id> --log
```

Google Cloud Build:
```bash
gcloud builds list --limit 5
gcloud builds log <build-id>
```

4. **Check for platform-specific issues:**
   - Different Debuerreotype versions
   - Different timestamps used
   - Build failures masked by exit code issues
   - Network issues during package download

### Format Normalization Issues

**Symptom:** Script fails to parse JSON from one platform

**Diagnosis:**
```bash
# Check JSON structure
jq 'keys' consensus-results/github-*.json
jq 'keys' consensus-results/gcp-*.json

# Validate JSON
jq empty consensus-results/*.json
```

**Solution:** Format normalization is automatic as of commit 3ba3cbf. If issues persist, check:
- JSON is well-formed (`jq empty` should succeed)
- Files contain either `.results[]` or `.architectures{}` keys
- Serial numbers match across files

## Automated Workflow

### consensus-validator.yml

Runs weekly at 6 AM UTC on Mondays (after weekly builds).

**Triggers:**
- **Schedule**: Weekly on Mondays at 6 AM UTC
- **Manual**: `gh workflow run consensus-validator.yml -f serial=20251103`

**Process:**
1. Determines serial (from input or dashboard/data/latest.json)
2. Authenticates to GCP using Workload Identity Federation
3. Collects results from all available platforms
4. Compares and validates consensus
5. Generates summary report
6. Commits consensus report to repository

**Outputs:**
- GitHub Actions job summary with consensus status
- Downloadable artifact: `consensus-report-{serial}.zip`
- Committed to repository: `dashboard/data/consensus/{serial}.json`

**View workflow runs:**
```bash
# List recent runs
gh run list --workflow=consensus-validator.yml --limit 10

# View specific run
gh run view <run-id>

# Download artifacts
gh run download <run-id>
```

## Best Practices

1. **Run validation after builds complete:**
   - Wait 10-15 minutes after build workflow completes
   - Ensures all artifacts are uploaded and available

2. **Use consistent serials:**
   - Match the serial used in build workflows
   - Check dashboard for latest verified serial

3. **Monitor consensus rates:**
   - Track consensus achievement over time
   - Investigate declining consensus rates promptly

4. **Keep threshold at 2:**
   - Requires multiple independent platforms
   - Balances security with operational feasibility

5. **Investigate all disagreements:**
   - Consensus failures signal potential compromise
   - Review witness evidence and build logs immediately

## Integration Examples

### In CI/CD Pipeline

```yaml
- name: Validate consensus
  run: |
    ./scripts/collect-results.sh \
      --serial ${{ env.SERIAL }} \
      --github-repo ${{ github.repository }} \
      --gcp-project ${{ vars.GCP_PROJECT_ID }} \
      --output-dir consensus-results

    ./scripts/compare-platforms.sh \
      --results-dir consensus-results \
      --threshold 2 \
      --output consensus-report.json
```

### Local Testing

```bash
# Create test directory
mkdir -p consensus-results

# Create mock GitHub result (nested format)
cat > consensus-results/github-20251103.json <<'EOF'
{
  "serial": "20251103",
  "timestamp": "2025-11-09T15:01:20Z",
  "architectures": {
    "amd64": {
      "suites": {
        "bookworm": {
          "reproducible": true,
          "sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba",
          "official_sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba"
        }
      }
    }
  }
}
EOF

# Create mock GCP result (array format)
cat > consensus-results/gcp-20251103-amd64.json <<'EOF'
{
  "serial": "20251103",
  "timestamp": "2025-11-09T18:11:53Z",
  "results": [
    {
      "architecture": "amd64",
      "suite": "bookworm",
      "reproducible": true,
      "sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba",
      "official_sha256": "b06055e3b5ceb5d30ece2923109790b54477afad47e4790739a35e89c5ac30ba"
    }
  ]
}
EOF

# Validate (should achieve consensus)
./scripts/compare-platforms.sh --results-dir consensus-results
```

## Testing Consensus Failure

To test disagreement handling:

```bash
# Create mismatched checksums
cat > consensus-results/github-20251103.json <<'EOF'
{
  "serial": "20251103",
  "architectures": {
    "amd64": {
      "suites": {
        "bookworm": {
          "sha256": "aaaa0000..."
        }
      }
    }
  }
}
EOF

cat > consensus-results/gcp-20251103-amd64.json <<'EOF'
{
  "serial": "20251103",
  "results": [
    {
      "architecture": "amd64",
      "suite": "bookworm",
      "sha256": "bbbb1111..."
    }
  ]
}
EOF

# This should report disagreement
./scripts/compare-platforms.sh \
  --results-dir consensus-results \
  --generate-evidence \
  --output disagreement-report.json

# Check exit code (should be non-zero)
echo "Exit code: $?"

# View evidence
cat disagreement-report.json | jq '.comparisons[] | select(.disagreement == true)'
```

## Report Structure

### Top-Level Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | When consensus validation ran (ISO 8601) |
| `consensus.achieved` | boolean | Whether overall consensus achieved |
| `consensus.threshold` | number | Minimum platforms required to agree |
| `summary.total_combinations` | number | Total suite/arch combinations checked |
| `summary.consensus_achieved` | number | Combinations with consensus |
| `summary.disagreements` | number | Combinations with disagreement |
| `summary.consensus_rate` | number | Percentage (0-1) of consensus achieved |
| `platforms` | array | List of platform result files compared |
| `comparisons` | array | Per-combination comparison details |

### Comparison Object

Each entry in `comparisons[]` contains:

| Field | Type | Description |
|-------|------|-------------|
| `architecture` | string | CPU architecture (amd64, arm64, etc.) |
| `suite` | string | Debian suite (bookworm, trixie, etc.) |
| `consensus` | boolean | Whether this combination achieved consensus |
| `consensus_checksum` | string | SHA256 if consensus reached |
| `platforms_agreeing` | number | Count of platforms that agree |
| `platforms_total` | number | Total platforms checked |
| `platform_results` | array | Per-platform checksums |
| `disagreement` | boolean | True if consensus not achieved |

## Related Documentation

- [Design Document](design.md) - System architecture
- [GCP Setup Instructions](gcp-setup-instructions.md) - GCP configuration
- [Local Setup Guide](local-setup.md) - Local verification
