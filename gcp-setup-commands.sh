#!/bin/bash
# GCP Setup Commands for Debian Reproducibility Cross-Platform Verification
# Run these commands on a host with gcloud CLI configured

set -euo pipefail

# ============================================================================
# VARIABLES - UPDATE THESE
# ============================================================================

PROJECT_ID="your-project-id"  # CHANGE THIS to your actual GCP project ID
GITHUB_REPO="sheurich/debian-repro"  # Your GitHub repository
REGION="us-central1"  # Change if desired

# ============================================================================
# STEP 1: Create Service Account
# ============================================================================

echo "Creating service account..."
gcloud iam service-accounts create debian-repro-ci \
  --project="${PROJECT_ID}" \
  --description="Service account for debian-repro GitHub Actions" \
  --display-name="Debian Reproducibility CI"

SERVICE_ACCOUNT_EMAIL="debian-repro-ci@${PROJECT_ID}.iam.gserviceaccount.com"
echo "Service account created: ${SERVICE_ACCOUNT_EMAIL}"

# ============================================================================
# STEP 2: Grant Required Permissions
# ============================================================================

echo "Granting permissions to service account..."

# Permission to submit and view Cloud Build jobs
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/cloudbuild.builds.editor"

# Permission to read from GCS buckets
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.objectViewer"

# Permission to write to GCS buckets
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.objectCreator"

echo "Permissions granted"

# ============================================================================
# STEP 3: Create GCS Bucket for Results
# ============================================================================

BUCKET_NAME="${PROJECT_ID}-debian-repro-results"
echo "Creating GCS bucket: ${BUCKET_NAME}"

# Create bucket
gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"

# Set lifecycle to delete objects after 30 days
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 30,
          "matchesPrefix": ["daily/", "builds/"]
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
rm /tmp/lifecycle.json

# Grant service account access to bucket
gsutil iam ch \
  "serviceAccount:${SERVICE_ACCOUNT_EMAIL}:objectViewer" \
  "serviceAccount:${SERVICE_ACCOUNT_EMAIL}:objectCreator" \
  "gs://${BUCKET_NAME}"

echo "Bucket created and configured"

# ============================================================================
# STEP 4A: Set up Workload Identity Federation (RECOMMENDED)
# ============================================================================

echo "Setting up Workload Identity Federation..."

# Get project number
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
echo "Project number: ${PROJECT_NUMBER}"

# Create workload identity pool
gcloud iam workload-identity-pools create "github-actions" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --description="Pool for GitHub Actions OIDC tokens"

# Create OIDC provider
gcloud iam workload-identity-pools providers create-oidc "debian-repro" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-actions" \
  --display-name="Debian Repro GitHub" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant service account permissions for workload identity
gcloud iam service-accounts add-iam-policy-binding \
  "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${GITHUB_REPO}"

# Output the values needed for GitHub Actions
echo ""
echo "=========================================="
echo "WORKLOAD IDENTITY FEDERATION CONFIGURATION"
echo "=========================================="
echo "Add these to your GitHub Actions workflow:"
echo ""
echo "workload_identity_provider: 'projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/debian-repro'"
echo "service_account: '${SERVICE_ACCOUNT_EMAIL}'"
echo ""

# ============================================================================
# STEP 4B: Create Service Account Key (ALTERNATIVE - Less Secure)
# ============================================================================

echo "Creating service account key (alternative to Workload Identity)..."
echo "WARNING: This is less secure than Workload Identity Federation"
echo "Press Ctrl+C to skip, or Enter to continue..."
read -r

# Create key
KEY_FILE="/tmp/debian-repro-ci-key.json"
gcloud iam service-accounts keys create "${KEY_FILE}" \
  --iam-account="${SERVICE_ACCOUNT_EMAIL}"

# Base64 encode for GitHub secret
BASE64_KEY=$(base64 -w 0 "${KEY_FILE}" 2>/dev/null || base64 "${KEY_FILE}")

echo ""
echo "=========================================="
echo "SERVICE ACCOUNT KEY (ALTERNATIVE METHOD)"
echo "=========================================="
echo "1. Go to: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
echo "2. Click 'New repository secret'"
echo "3. Name: GCP_SA_KEY"
echo "4. Value: Copy the base64 string below"
echo ""
echo "---BEGIN BASE64 KEY---"
echo "${BASE64_KEY}"
echo "---END BASE64 KEY---"
echo ""
echo "5. Key file saved to: ${KEY_FILE}"
echo "   DELETE THIS FILE AFTER ADDING TO GITHUB SECRETS!"
echo ""

# ============================================================================
# STEP 5: Enable Required APIs
# ============================================================================

echo "Enabling required APIs..."
gcloud services enable cloudbuild.googleapis.com --project="${PROJECT_ID}"
gcloud services enable storage-api.googleapis.com --project="${PROJECT_ID}"
gcloud services enable iam.googleapis.com --project="${PROJECT_ID}"
gcloud services enable iamcredentials.googleapis.com --project="${PROJECT_ID}"

# ============================================================================
# STEP 6: Verification
# ============================================================================

echo ""
echo "=========================================="
echo "SETUP COMPLETE - VERIFICATION"
echo "=========================================="
echo ""
echo "Project ID: ${PROJECT_ID}"
echo "Service Account: ${SERVICE_ACCOUNT_EMAIL}"
echo "GCS Bucket: gs://${BUCKET_NAME}"
echo ""
echo "Verifying setup..."

# Check service account
gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" > /dev/null && \
  echo "✅ Service account exists"

# Check bucket
gsutil ls "gs://${BUCKET_NAME}" > /dev/null 2>&1 && \
  echo "✅ GCS bucket exists"

# Check workload identity pool
gcloud iam workload-identity-pools describe "github-actions" \
  --project="${PROJECT_ID}" \
  --location="global" > /dev/null 2>&1 && \
  echo "✅ Workload Identity Federation configured"

# List IAM bindings
echo ""
echo "IAM Bindings for service account:"
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:${SERVICE_ACCOUNT_EMAIL}"

echo ""
echo "=========================================="
echo "REQUIRED VALUES FOR GITHUB SECRETS/VARIABLES"
echo "=========================================="
echo ""
echo "Add these as GitHub repository variables:"
echo "  GCP_PROJECT_ID=${PROJECT_ID}"
echo "  GCP_RESULTS_BUCKET=${BUCKET_NAME}"
echo ""
echo "For Workload Identity (recommended):"
echo "  GCP_WIF_PROVIDER=projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/debian-repro"
echo "  GCP_WIF_SERVICE_ACCOUNT=${SERVICE_ACCOUNT_EMAIL}"
echo ""
echo "For Service Account Key (alternative):"
echo "  GCP_SA_KEY=(the base64 key from above)"
echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Add the GitHub secrets/variables listed above"
echo "2. If using service account key, delete ${KEY_FILE}"
echo "3. Test authentication with: gh workflow run test-gcp-auth.yml"
echo ""
echo "Cloud Build command to test from GitHub Actions:"
echo "  gcloud builds submit --config=cloudbuild.yaml \\"
echo "    --project=${PROJECT_ID} \\"
echo "    --substitutions=_RESULTS_BUCKET=${BUCKET_NAME}"