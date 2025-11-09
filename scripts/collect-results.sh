#!/usr/bin/env bash
# Collect verification results from multiple platforms for consensus checking

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="collect-results"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Collect verification results from multiple platforms for consensus checking.

Options:
  --serial SERIAL           Debian serial number (e.g., 20251020)
  --output-dir DIR          Output directory for collected results (default: consensus-results)
  --gcp-project PROJECT     GCP project ID (required for GCP results)
  --gcp-bucket BUCKET       GCS bucket path (default: PROJECT_cloudbuild/debian-reproducible)
  --github-repo REPO        GitHub repository (default: current repo)
  --platforms PLATFORMS     Comma-separated platforms to collect (default: github,gcp)
  --help                    Display this help message

Examples:
  # Collect results from both platforms
  $(basename "$0") --serial 20251020 --gcp-project my-project

  # Collect only GitHub results
  $(basename "$0") --serial 20251020 --platforms github

  # Specify custom output directory
  $(basename "$0") --serial 20251020 --gcp-project my-project --output-dir /tmp/results
EOF
}

#######################################
# Fetch results from GitHub Actions
# Arguments:
#   $1 - Serial number
#   $2 - Repository name
#   $3 - Output directory
#######################################
fetch_github_results() {
  local serial="$1"
  local repo="$2"
  local output_dir="$3"

  log_info "$COMPONENT" "Fetching GitHub Actions results for serial $serial"

  # Try to fetch from GitHub Pages dashboard data
  local pages_url="https://${repo%/*}.github.io/${repo##*/}/data/latest.json"

  log_debug "$COMPONENT" "Trying GitHub Pages: $pages_url"

  if curl -sSf -o "${output_dir}/github-latest.json" "$pages_url"; then
    # Check if serial matches
    local fetched_serial
    fetched_serial=$(jq -r '.serial' "${output_dir}/github-latest.json" 2>/dev/null)

    if [ "$fetched_serial" = "$serial" ]; then
      log_info "$COMPONENT" "Successfully fetched GitHub results from Pages (serial: $serial)"
      mv "${output_dir}/github-latest.json" "${output_dir}/github-${serial}.json"
      return 0
    else
      log_warn "$COMPONENT" "Serial mismatch: expected $serial, got $fetched_serial"
      rm -f "${output_dir}/github-latest.json"
    fi
  else
    log_debug "$COMPONENT" "Could not fetch from GitHub Pages"
  fi

  # Try to fetch from GitHub Actions artifacts using gh CLI
  if command -v gh &> /dev/null; then
    log_info "$COMPONENT" "Trying to fetch from GitHub Actions artifacts"

    # Get recent workflow runs
    local runs
    runs=$(gh run list \
      --repo "$repo" \
      --workflow "reproducible-debian-build.yml" \
      --limit 10 \
      --json databaseId,conclusion,createdAt)

    # Find successful run for this serial
    local run_id
    run_id=$(echo "$runs" | jq -r \
      --arg serial "$serial" \
      '.[] | select(.conclusion == "success") | .databaseId' | head -1)

    if [ -n "$run_id" ]; then
      log_info "$COMPONENT" "Found workflow run: $run_id"

      # Download artifacts (report.json should be in dashboard updates artifact)
      if gh run download "$run_id" --repo "$repo" --dir "${output_dir}/github-artifacts-${run_id}"; then
        # Look for report.json in downloaded artifacts
        local report_file
        report_file=$(find "${output_dir}/github-artifacts-${run_id}" -name "report.json" -o -name "latest.json" | head -1)

        if [ -f "$report_file" ]; then
          cp "$report_file" "${output_dir}/github-${serial}.json"
          log_info "$COMPONENT" "Successfully fetched GitHub results from artifacts"
          rm -rf "${output_dir}/github-artifacts-${run_id}"
          return 0
        fi
      fi
    fi
  fi

  log_warn "$COMPONENT" "Could not fetch GitHub Actions results for serial $serial"
  return 1
}

#######################################
# Fetch results from Google Cloud Build
# Arguments:
#   $1 - Serial number
#   $2 - GCP project ID
#   $3 - GCS bucket path
#   $4 - Output directory
#######################################
fetch_gcp_results() {
  local serial="$1"
  local project_id="$2"
  local bucket_path="$3"
  local output_dir="$4"

  log_info "$COMPONENT" "Fetching GCP results for serial $serial"

  # Check if gcloud is installed
  if ! command -v gcloud &> /dev/null; then
    log_error "$COMPONENT" "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
    return 1
  fi

  # Check if gsutil is available
  if ! command -v gsutil &> /dev/null; then
    log_error "$COMPONENT" "gsutil not found. Install with: gcloud components install gsutil"
    return 1
  fi

  # List recent builds
  log_debug "$COMPONENT" "Looking for builds in gs://${bucket_path}/"

  # Get list of build IDs (directories in GCS bucket)
  # Cloud Build uses UUID format (e.g., 35a9519c-c057-454e-85e4-ceabd862d2e0)
  local build_ids
  build_ids=$(gsutil ls "gs://${bucket_path}/" | grep -E '/[a-f0-9-]{36}/$' | tail -20)

  if [ -z "$build_ids" ]; then
    log_warn "$COMPONENT" "No builds found in gs://${bucket_path}/"
    return 1
  fi

  # Check each build for matching serial
  for build_dir in $build_ids; do
    log_debug "$COMPONENT" "Checking build: $build_dir"

    # Try to download the consensus report
    local report_path="${build_dir}consensus-data/"
    local report_files
    report_files=$(gsutil ls "${report_path}gcp-${serial}-*.json" 2>/dev/null || true)

    if [ -n "$report_files" ]; then
      for report_file in $report_files; do
        local arch
        arch=$(basename "$report_file" | sed "s/gcp-${serial}-//" | sed 's/.json$//')

        log_info "$COMPONENT" "Found GCP report for serial $serial, architecture $arch"
        gsutil cp "$report_file" "${output_dir}/gcp-${serial}-${arch}.json"
      done
      return 0
    fi

    # Fallback: try to get gcp-report.json
    if gsutil cp "${build_dir}gcp-report.json" "${output_dir}/gcp-report-temp.json" 2>/dev/null; then
      # Check if serial matches
      local fetched_serial
      fetched_serial=$(jq -r '.serial' "${output_dir}/gcp-report-temp.json" 2>/dev/null)

      if [ "$fetched_serial" = "$serial" ]; then
        log_info "$COMPONENT" "Successfully fetched GCP results from build ${build_dir##*/}"
        mv "${output_dir}/gcp-report-temp.json" "${output_dir}/gcp-${serial}.json"
        return 0
      else
        rm -f "${output_dir}/gcp-report-temp.json"
      fi
    fi
  done

  log_warn "$COMPONENT" "Could not find GCP results for serial $serial"
  return 1
}

#######################################
# Main execution
#######################################
main() {
  local serial=""
  local output_dir="consensus-results"
  local gcp_project=""
  local gcp_bucket=""
  local github_repo=""
  local platforms="github,gcp"

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --serial)
        serial="$2"
        shift 2
        ;;
      --output-dir)
        output_dir="$2"
        shift 2
        ;;
      --gcp-project)
        gcp_project="$2"
        shift 2
        ;;
      --gcp-bucket)
        gcp_bucket="$2"
        shift 2
        ;;
      --github-repo)
        github_repo="$2"
        shift 2
        ;;
      --platforms)
        platforms="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "$COMPONENT" "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$serial" ]; then
    log_error "$COMPONENT" "Missing required argument: --serial"
    usage
    exit 1
  fi

  # Set defaults
  if [ -z "$github_repo" ]; then
    # Try to detect from git remote
    if git remote get-url origin &>/dev/null; then
      github_repo=$(git remote get-url origin | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
      log_debug "$COMPONENT" "Detected GitHub repo: $github_repo"
    else
      log_warn "$COMPONENT" "Could not detect GitHub repo. Use --github-repo to specify."
    fi
  fi

  if [ -z "$gcp_bucket" ] && [ -n "$gcp_project" ]; then
    gcp_bucket="${gcp_project}_cloudbuild/debian-reproducible"
    log_debug "$COMPONENT" "Using default GCS bucket: gs://${gcp_bucket}/"
  fi

  # Create output directory
  mkdir -p "$output_dir"
  log_info "$COMPONENT" "Collecting results for serial $serial to $output_dir"

  # Track success
  local collected_count=0

  # Parse platforms
  IFS=',' read -ra PLATFORM_LIST <<< "$platforms"

  for platform in "${PLATFORM_LIST[@]}"; do
    platform=$(echo "$platform" | xargs)  # trim whitespace

    case "$platform" in
      github)
        if [ -n "$github_repo" ]; then
          if fetch_github_results "$serial" "$github_repo" "$output_dir"; then
            collected_count=$((collected_count + 1))
          fi
        else
          log_warn "$COMPONENT" "Skipping GitHub: no repository specified"
        fi
        ;;
      gcp)
        if [ -n "$gcp_project" ]; then
          if fetch_gcp_results "$serial" "$gcp_project" "$gcp_bucket" "$output_dir"; then
            collected_count=$((collected_count + 1))
          fi
        else
          log_warn "$COMPONENT" "Skipping GCP: no project specified (use --gcp-project)"
        fi
        ;;
      *)
        log_warn "$COMPONENT" "Unknown platform: $platform"
        ;;
    esac
  done

  # Summary
  log_info "$COMPONENT" "Collection complete: $collected_count platform(s) retrieved"

  # List collected files
  echo ""
  echo "Collected results:"
  ls -lh "$output_dir"/*.json 2>/dev/null || true

  if [ "$collected_count" -eq 0 ]; then
    log_error "$COMPONENT" "No results collected"
    exit 1
  fi

  exit 0
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  main "$@"
fi
