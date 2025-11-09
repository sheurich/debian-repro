# GCP Setup Instructions

This document contains instructions for setting up Google Cloud Platform resources needed for cross-platform reproducibility verification.

## Prerequisites

- GCP Project with billing enabled
- `gcloud` CLI installed and authenticated
- Project Owner or IAM Admin permissions

## Setup Steps

### 1. Create GCP Project and Enable APIs

```bash
# Create project (if needed)
gcloud projects create YOUR-PROJECT-ID

# Set as default
gcloud config set project YOUR-PROJECT-ID

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable iamcredentials.googleapis.com
```

### 2. Create Service Account and Grant Permissions

```bash
# Create service account
gcloud iam service-accounts create debian-repro-ci \
  --display-name="Debian Reproducibility CI" \
  --project=YOUR-PROJECT-ID

# Grant Cloud Build permissions
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.editor"

# Grant GCS permissions
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectCreator"
```

### 3. Create GCS Bucket

```bash
# Create bucket for results
gsutil mb -p YOUR-PROJECT-ID \
  -l us-central1 \
  gs://YOUR-PROJECT-ID-debian-repro-results

# Lifecycle policy to auto-delete old results (optional)
cat > /tmp/lifecycle.json <<'EOF'
{
  "lifecycle": {
    "rule": [{
      "action": {"type": "Delete"},
      "condition": {"age": 30}
    }]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json \
  gs://YOUR-PROJECT-ID-debian-repro-results
```

### 4. Set Up Workload Identity Federation

Create WIF pool and provider for secure, keyless authentication:

```bash
# Get project number
PROJECT_NUMBER=$(gcloud projects describe YOUR-PROJECT-ID --format="value(projectNumber)")

# Create Workload Identity Pool
gcloud iam workload-identity-pools create github-actions \
  --project=YOUR-PROJECT-ID \
  --location=global \
  --display-name="GitHub Actions"

# Create OIDC Provider
gcloud iam workload-identity-pools providers create-oidc debian-repro \
  --project=YOUR-PROJECT-ID \
  --location=global \
  --workload-identity-pool=github-actions \
  --display-name="Debian Repro Repository" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant service account impersonation to GitHub Actions from your repository
gcloud iam service-accounts add-iam-policy-binding \
  debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com \
  --project=YOUR-PROJECT-ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/YOUR-GITHUB-USERNAME/debian-repro"

# IMPORTANT: Grant Service Account User role for Cloud Build submission
# This allows the CI service account to submit builds that run as the compute service account
gcloud iam service-accounts add-iam-policy-binding \
  ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --project=YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Save provider name for GitHub configuration
echo "Provider: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/debian-repro"
```

### 5. Configure GitHub Repository Variables

Go to your GitHub repository settings:
https://github.com/sheurich/debian-repro/settings/secrets/actions

#### Add Repository Variables

Use the GitHub CLI or web UI to add these variables:

```bash
# Using GitHub CLI
gh variable set GCP_PROJECT_ID --body "YOUR-PROJECT-ID" --repo YOUR-GITHUB-USERNAME/debian-repro
gh variable set GCP_RESULTS_BUCKET --body "YOUR-PROJECT-ID-debian-repro-results" --repo YOUR-GITHUB-USERNAME/debian-repro
gh variable set GCP_WIF_PROVIDER --body "projects/PROJECT-NUMBER/locations/global/workloadIdentityPools/github-actions/providers/debian-repro" --repo YOUR-GITHUB-USERNAME/debian-repro
gh variable set GCP_WIF_SERVICE_ACCOUNT --body "debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" --repo YOUR-GITHUB-USERNAME/debian-repro
```

Or via GitHub web UI (Settings → Secrets and variables → Actions → Variables tab):
- `GCP_PROJECT_ID` - Your GCP project ID (e.g., `debian-repro-oxide`)
- `GCP_RESULTS_BUCKET` - The bucket name (e.g., `debian-repro-oxide-debian-repro-results`)
- `GCP_WIF_PROVIDER` - The provider string from step 4 (e.g., `projects/485735807805/locations/global/workloadIdentityPools/github-actions/providers/debian-repro`)
- `GCP_WIF_SERVICE_ACCOUNT` - The service account email (e.g., `debian-repro-ci@debian-repro-oxide.iam.gserviceaccount.com`)

### 6. Test Authentication

Run the test workflow to verify everything is configured correctly:

```bash
# From your local machine with GitHub CLI
gh workflow run 204699375 --repo YOUR-GITHUB-USERNAME/debian-repro

# Or by workflow file name
gh workflow run test-gcp-auth.yml --repo YOUR-GITHUB-USERNAME/debian-repro
```

Or via GitHub UI:
1. Go to Actions tab
2. Select "Test GCP Authentication" workflow
3. Click "Run workflow"

The test will:
- Verify WIF authentication works
- Test Cloud Build API access
- Test GCS bucket read/write
- Submit a test Cloud Build job

### 7. Verify Setup

Check the workflow run output. You should see:
- ✅ Authentication successful
- ✅ Cloud Build API accessible
- ✅ GCS bucket accessible
- ✅ Test build completed

## Security Notes

### Workload Identity Federation
- **No long-lived credentials**: GitHub Actions requests short-lived tokens at runtime
- **Automatic rotation**: OIDC tokens expire quickly and are renewed automatically
- **Repository-scoped**: Only your specific repository can authenticate
- **Industry best practice**: Recommended by Google and GitHub for CI/CD authentication

## Troubleshooting

### Authentication Fails
```
Error: Could not authenticate to Google Cloud
```
**Solution**:
- Verify GitHub repository variables are set correctly (Settings → Secrets and variables → Actions → Variables)
- Check that the WIF provider string includes the correct project number
- Ensure the repository owner/name in the WIF binding matches your GitHub repository

### Permission Denied on Cloud Build
```
Error: Permission 'cloudbuild.builds.create' denied
```
**Solution**: Ensure the service account has `roles/cloudbuild.builds.editor`:
```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.editor"
```

### Cannot Submit Cloud Build Jobs
```
Error: caller does not have permission to act as service account
```
**Solution**: Grant the Service Account User role on the compute service account:
```bash
PROJECT_NUMBER=$(gcloud projects describe YOUR-PROJECT-ID --format="value(projectNumber)")
gcloud iam service-accounts add-iam-policy-binding \
  ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --project=YOUR-PROJECT-ID \
  --member="serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### GCS Access Denied
```
Error: AccessDeniedException: 403
```
**Solution**: Check bucket IAM permissions for the service account:
```bash
gsutil iam ch \
  serviceAccount:debian-repro-ci@YOUR-PROJECT-ID.iam.gserviceaccount.com:objectAdmin \
  gs://YOUR-PROJECT-ID-debian-repro-results
```

### Workload Identity Federation Error
```
Error: identity pool does not exist
```
**Solution**:
- Ensure the project number (not ID) is correct in the provider string
- Verify the WIF pool and provider were created successfully:
```bash
gcloud iam workload-identity-pools list --location=global --project=YOUR-PROJECT-ID
gcloud iam workload-identity-pools providers list --workload-identity-pool=github-actions --location=global --project=YOUR-PROJECT-ID
```

## Required Permissions Summary

The `debian-repro-ci` service account needs:
- `roles/cloudbuild.builds.editor` - Submit and view Cloud Build jobs
- `roles/storage.objectViewer` - Read from GCS bucket
- `roles/storage.objectCreator` - Write to GCS bucket
- `roles/iam.serviceAccountUser` on `{PROJECT_NUMBER}-compute@developer.gserviceaccount.com` - Submit builds that run as compute service account
- `roles/iam.workloadIdentityUser` - Allow GitHub Actions to impersonate the service account (granted via WIF binding)

## Next Steps

After successful setup:
1. The Smart Verification Workflow can be deployed
2. The Daily Cross-Platform Verification can be configured
3. Cloud Build will export results to GCS
4. GitHub Actions will compare results automatically