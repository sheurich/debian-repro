# GCP Setup Instructions

This document contains instructions for setting up Google Cloud Platform resources needed for cross-platform reproducibility verification.

## Prerequisites

- GCP Project with billing enabled
- `gcloud` CLI installed and authenticated
- Project Owner or IAM Admin permissions

## Setup Steps

### 1. Run Setup Commands

Copy `gcp-setup-commands.sh` to your GCP-enabled host and run:

```bash
# First, edit the script to set your PROJECT_ID
nano gcp-setup-commands.sh

# Update this line with your actual project ID:
PROJECT_ID="your-actual-project-id"

# Make executable and run
chmod +x gcp-setup-commands.sh
./gcp-setup-commands.sh
```

The script will:
1. Create a service account `debian-repro-ci`
2. Grant minimal required permissions
3. Create a GCS bucket for results storage
4. Set up Workload Identity Federation (recommended)
5. Optionally create a service account key (less secure alternative)

### 2. Add GitHub Secrets and Variables

After running the script, go to your GitHub repository settings:
https://github.com/sheurich/debian-repro/settings/secrets/actions

#### Add Repository Variables

Click "Variables" tab and add:
- `GCP_PROJECT_ID` - Your GCP project ID
- `GCP_RESULTS_BUCKET` - The bucket name (format: `{project-id}-debian-repro-results`)

#### For Workload Identity Federation (Recommended)

Add these variables:
- `GCP_WIF_PROVIDER` - The provider string shown in script output
- `GCP_WIF_SERVICE_ACCOUNT` - The service account email

#### For Service Account Key (Alternative)

Add this secret:
- `GCP_SA_KEY` - The base64-encoded key from script output

**Important**: After adding the key to GitHub, delete the local key file:
```bash
rm /tmp/debian-repro-ci-key.json
```

### 3. Test Authentication

Run the test workflow to verify everything is configured correctly:

```bash
# From your local machine with GitHub CLI
gh workflow run test-gcp-auth.yml
```

Or via GitHub UI:
1. Go to Actions tab
2. Select "Test GCP Authentication" workflow
3. Click "Run workflow"

The test will:
- Verify authentication works
- Test Cloud Build API access
- Test GCS bucket read/write
- Submit a test Cloud Build job

### 4. Verify Setup

Check the workflow run output. You should see:
- ✅ Authentication successful
- ✅ Cloud Build API accessible
- ✅ GCS bucket accessible
- ✅ Test build completed

## Security Notes

### Workload Identity Federation (Recommended)
- No long-lived credentials
- Automatic key rotation
- Scoped to specific repository
- Best security practice

### Service Account Key (Alternative)
- Long-lived credential
- Must be manually rotated
- Higher security risk
- Use only if Workload Identity isn't possible

## Troubleshooting

### Authentication Fails
```
Error: Could not authenticate to Google Cloud
```
**Solution**: Verify the GitHub secrets/variables are set correctly

### Permission Denied on Cloud Build
```
Error: Permission 'cloudbuild.builds.create' denied
```
**Solution**: Ensure the service account has `roles/cloudbuild.builds.editor`

### GCS Access Denied
```
Error: AccessDeniedException: 403
```
**Solution**: Check bucket IAM permissions for the service account

### Workload Identity Federation Error
```
Error: identity pool does not exist
```
**Solution**: Ensure the project number is correct in the provider string

## Required Permissions Summary

The service account needs:
- `roles/cloudbuild.builds.editor` - Submit and view builds
- `roles/storage.objectViewer` - Read from GCS
- `roles/storage.objectCreator` - Write to GCS

## Next Steps

After successful setup:
1. The Smart Verification Workflow can be deployed
2. The Daily Cross-Platform Verification can be configured
3. Cloud Build will export results to GCS
4. GitHub Actions will compare results automatically