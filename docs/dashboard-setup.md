# Dashboard Setup Guide

This guide explains how to configure and use the reproducibility verification dashboard.

## Overview

The dashboard provides a web-based interface showing:
- Current reproducibility status for all architectures and suites
- 30-day historical trend chart
- Per-architecture verification details
- Status badges for embedding in README files

**Live Dashboard:** https://sheurich.github.io/debian-repro/

## Configuring GitHub Pages

The dashboard requires GitHub Pages to be configured to serve from the `/dashboard` directory.

### Setup Steps

1. **Navigate to Repository Settings**
   - Go to https://github.com/sheurich/debian-repro/settings/pages

2. **Configure Source**
   - **Source:** Deploy from a branch
   - **Branch:** `main`
   - **Directory:** `/dashboard` (not `/docs`)
   - Click **Save**

3. **Verify Deployment**
   - Wait 1-2 minutes for initial deployment
   - Visit https://sheurich.github.io/debian-repro/
   - You should see the reproducibility dashboard with current data

### First-Time Setup

If this is the first GitHub Pages deployment for the repository, the page may show placeholder data until the first CI run completes.

## How Dashboard Updates Work

The dashboard automatically updates after each verification run through the GitHub Actions `update-dashboard` job.

### Update Process

1. **Build Phase** - Matrix jobs build and verify each architecture
2. **Artifact Collection** - Build results uploaded as GitHub Actions artifacts
3. **Dashboard Update Job** - Triggered after builds complete:
   - Downloads all build artifacts
   - Clones official checksums for comparison
   - Generates JSON result files for each suite/architecture
   - Runs `capture-environment.sh` to record build context
   - Runs `generate-report.sh` to create comprehensive report
   - Updates `dashboard/data/latest.json` with current results
   - Appends to `dashboard/data/history.json` (keeps last 90 entries)
   - Runs `generate-badges.sh` to regenerate all badge endpoints
   - Commits and pushes changes to repository
4. **GitHub Pages Deployment** - Automatically triggered by commit

### Update Frequency

- **Weekly Schedule:** Sundays at 00:00 UTC
- **Manual Triggers:** Via GitHub Actions workflow dispatch
- **Smart Verification:** (planned) Every 4 hours when upstream changes detected

## Dashboard Files

```
dashboard/
├── index.html              # Main dashboard page
├── script.js               # Dashboard JavaScript (Chart.js, data fetching)
├── style.css               # Responsive styling
├── .nojekyll               # Disable Jekyll processing
├── badges/                 # Shields.io badge JSON endpoints
│   ├── build-status.json           # Overall build status
│   ├── reproducibility-rate.json   # Percentage of reproducible builds
│   └── last-verified.json          # Last verification date
└── data/                   # Verification results
    ├── latest.json         # Most recent verification results
    └── history.json        # Historical results (90 most recent)
```

## Data Format

### latest.json Structure

```json
{
  "timestamp": "2025-11-07T12:00:00Z",
  "run_id": "1234567890",
  "serial": "20251020",
  "epoch": 1760918400,
  "environment": {
    "platform": "GitHub Actions",
    "runner": "ubuntu-24.04",
    "debuerreotype_version": "0.16"
  },
  "architectures": {
    "amd64": {
      "status": "success",
      "suites": {
        "bookworm": {
          "reproducible": true,
          "sha256": "abc123...",
          "official_sha256": "abc123...",
          "build_time_seconds": 456
        }
      }
    }
  }
}
```

### Badge JSON Format (Shields.io)

```json
{
  "schemaVersion": 1,
  "label": "reproducibility",
  "message": "100%",
  "color": "brightgreen"
}
```

## Badge URLs

Badges are served from GitHub Pages and can be embedded using shields.io:

```markdown
![Build Status](https://github.com/sheurich/debian-repro/actions/workflows/reproducible-debian-build.yml/badge.svg)
![Reproducibility Rate](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json)
![Last Verified](https://img.shields.io/endpoint?url=https://sheurich.github.io/debian-repro/badges/last-verified.json)
```

### Available Badge Endpoints

- **Build Status:** `https://sheurich.github.io/debian-repro/badges/build-status.json`
- **Reproducibility Rate:** `https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json`
- **Last Verified:** `https://sheurich.github.io/debian-repro/badges/last-verified.json`

## Local Development

To test dashboard changes locally before deploying:

```bash
# Navigate to dashboard directory
cd dashboard

# Serve with Python's built-in HTTP server
python3 -m http.server 8000

# Visit in browser
open http://localhost:8000
```

### Testing with Local Data

Create sample data files for testing:

```bash
# Create test data
cat > dashboard/data/latest.json <<'EOF'
{
  "timestamp": "2025-11-07T12:00:00Z",
  "run_id": "test",
  "serial": "20251020",
  "epoch": 1760918400,
  "environment": {"platform": "local"},
  "architectures": {
    "amd64": {
      "status": "success",
      "suites": {
        "bookworm": {
          "reproducible": true,
          "sha256": "test123",
          "official_sha256": "test123",
          "build_time_seconds": 300
        }
      }
    }
  }
}
EOF

# Generate badges
./scripts/generate-badges.sh \
  --report dashboard/data/latest.json \
  --output-dir dashboard/badges
```

## Troubleshooting

### Dashboard Shows Old Data

**Symptoms:** Dashboard displays outdated verification results

**Solutions:**
1. Check GitHub Pages deployment status:
   - Go to Settings → Pages
   - Verify deployment completed successfully
   - Look for "Your site is published at..." message

2. Verify the `update-dashboard` job ran successfully:
   ```bash
   gh run list --workflow=reproducible-debian-build.yml --limit 5
   gh run view [run-id] --log
   ```

3. Check recent commits:
   ```bash
   git log --oneline --grep="Update dashboard" -5
   ```

4. Force a page rebuild:
   - Make a trivial commit to dashboard/
   - GitHub Pages will redeploy automatically

### Dashboard Not Loading

**Symptoms:** 404 error or blank page

**Solutions:**
1. Verify GitHub Pages configuration:
   - Settings → Pages
   - Ensure "Source" is set to main branch, /dashboard folder
   - Not /docs or root

2. Check browser console for JavaScript errors:
   - Open Developer Tools (F12)
   - Look for failed network requests
   - Verify data files are accessible

3. Ensure data files exist:
   ```bash
   ls -la dashboard/data/
   # Should see: latest.json, history.json
   ```

4. Wait for Pages deployment:
   - Check Actions tab for pages-build-deployment workflow
   - Can take 1-2 minutes after commit

### Badge URLs Return 404

**Symptoms:** Badge images not loading in README

**Solutions:**
1. Verify badge files exist:
   ```bash
   ls -la dashboard/badges/
   ```

2. Check GitHub Pages is serving files:
   - Visit https://sheurich.github.io/debian-repro/badges/reproducibility-rate.json
   - Should see JSON response

3. Wait for Pages cache to update:
   - GitHub Pages uses CDN with caching
   - Can take 2-5 minutes for updates to propagate

4. Force shields.io cache refresh:
   - Add cache-busting query parameter: `?v=2`
   - Shields.io will fetch fresh data

### Workflow Fails to Update Dashboard

**Symptoms:** `update-dashboard` job fails in GitHub Actions

**Common Issues:**

**Permission Denied:**
```
! [remote rejected] main -> main (permission denied)
```

**Solution:** Verify workflow has `contents: write` permission (line 345 in workflow file)

**Merge Conflict:**
```
error: failed to push some refs
```

**Solution:** Pull latest changes before manual runs:
```bash
git pull origin main
```

**Missing Data Files:**
```
cp: cannot stat 'report.json': No such file or directory
```

**Solution:** Check earlier job steps for failures in artifact generation

## Monitoring Dashboard Health

### Check Dashboard Update History

```bash
# View dashboard update commits
git log --oneline --grep="Update dashboard" --all

# View latest dashboard data
cat dashboard/data/latest.json | jq '{timestamp, serial, architectures: (.architectures | keys)}'

# Count historical entries
jq 'length' dashboard/data/history.json
```

### Monitor Update Frequency

```bash
# Check last update time
jq -r '.timestamp' dashboard/data/latest.json

# Check if updates are stale (older than 8 days)
LAST_UPDATE=$(jq -r '.timestamp' dashboard/data/latest.json)
LAST_EPOCH=$(date -d "$LAST_UPDATE" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_UPDATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_OLD=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))

if [ $DAYS_OLD -gt 7 ]; then
  echo "⚠️  Dashboard data is $DAYS_OLD days old"
else
  echo "✅ Dashboard data is current ($DAYS_OLD days old)"
fi
```

### Verify Reproducibility Rate

```bash
# Calculate current reproducibility rate
jq -r '
  .architectures | to_entries |
  map(.value.suites | to_entries | map(.value.reproducible)) |
  flatten |
  group_by(.) |
  map({key: (.[0] | tostring), value: length}) |
  from_entries |
  .true / (.true + .false) * 100
' dashboard/data/latest.json
```

## Manual Dashboard Update

If you need to manually trigger a dashboard update:

```bash
# Trigger workflow run
gh workflow run reproducible-debian-build.yml \
  -f suites='bookworm trixie' \
  -f architectures='amd64,arm64' \
  -f verify_only=true

# Watch progress
gh run watch

# Pull updated dashboard files
git pull origin main
```

## Related Documentation

- [Local Setup Guide](local-setup.md) - Running verifications locally
- [Debuerreotype Guide](debuerreotype-guide.md) - Understanding the build tool
- [Design Document](design.md) - System architecture and design decisions
- [GitHub Actions Workflow](../.github/workflows/reproducible-debian-build.yml) - Full workflow source
