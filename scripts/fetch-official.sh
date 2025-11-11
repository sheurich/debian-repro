#!/usr/bin/env bash
# Fetch official Debian build parameters from docker-debian-artifacts repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="fetch-official"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --arch ARCH --output-dir DIR [options]

Fetch official Debian build parameters from docker-debian-artifacts repository.

Required arguments:
  --arch ARCH           Architecture (amd64, arm64, armhf, i386, ppc64el)
  --output-dir DIR      Directory to store fetched artifacts

Optional arguments:
  --suites SUITES       Space-separated list of suites (default: fetch all)
  --help               Display this help message

Outputs:
  Creates OUTPUT_DIR with:
    - serial.txt         Build serial (YYYYMMDD)
    - epoch.txt          Unix epoch timestamp
    - timestamp.txt      @{epoch} format for debuerreotype
    - snapshot-url.txt   snapshot.debian.org URL
    - checksums/         Directory with suite checksums

Examples:
  $0 --arch amd64 --output-dir ./official-amd64
  $0 --arch arm64 --output-dir ./official-arm64 --suites "bookworm trixie"
EOF
}

#######################################
# Map architecture to artifacts branch
# Arguments:
#   $1 - Architecture name
# Outputs:
#   Branch name (dist-*)
#######################################
arch_to_branch() {
  local arch="$1"

  case "$arch" in
    amd64)    echo "dist-amd64" ;;
    arm64)    echo "dist-arm64v8" ;;
    armhf)    echo "dist-arm32v7" ;;
    i386)     echo "dist-i386" ;;
    ppc64el)  echo "dist-ppc64le" ;;
    s390x)
      log_error "$COMPONENT" "s390x not yet available in artifacts repo"
      exit 1
      ;;
    *)
      log_error "$COMPONENT" "Unknown architecture: $arch"
      exit 1
      ;;
  esac
}

#######################################
# Main function
#######################################
main() {
  require_commands git

  local arch=""
  local output_dir=""
  local suites=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --arch)
        arch="$2"
        shift 2
        ;;
      --output-dir)
        output_dir="$2"
        shift 2
        ;;
      --suites)
        suites="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "$COMPONENT" "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$arch" ] || [ -z "$output_dir" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 1
  fi

  # Convert output_dir to absolute path before changing directories
  output_dir=$(cd "$(dirname "$output_dir")" 2>/dev/null && pwd)/$(basename "$output_dir") || {
    # If parent doesn't exist, use current directory + output_dir
    output_dir="$(pwd)/$output_dir"
  }

  # Get artifacts branch for architecture
  local branch
  branch=$(arch_to_branch "$arch")

  timer_start "fetch_official"
  log_info "$COMPONENT" "Fetching official parameters for $arch from $branch"

  # Clone artifacts repository (not local for EXIT trap to access)
  temp_dir=""
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT

  log_debug "$COMPONENT" "Cloning to temporary directory: $temp_dir"

  if ! git clone --depth 1 --single-branch --branch "$branch" \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$temp_dir" >/dev/null 2>&1; then
    log_error "$COMPONENT" "Failed to clone artifacts repository"
    exit 1
  fi

  # Extract build parameters
  cd "$temp_dir" || {
    log_error "$COMPONENT" "Failed to change to temp directory"
    exit 1
  }

  if [ ! -f serial ] || [ ! -f debuerreotype-epoch ]; then
    log_error "$COMPONENT" "Missing required files in artifacts repo"
    exit 1
  fi

  local serial epoch snapshot_url timestamp
  serial=$(cat serial)
  epoch=$(cat debuerreotype-epoch)
  # Security: Use HTTPS to prevent man-in-the-middle attacks on snapshot URLs
  snapshot_url="https://snapshot.debian.org/archive/debian/${serial}T000000Z"
  timestamp="@${epoch}"

  log_info "$COMPONENT" "Found build parameters:"
  log_info "$COMPONENT" "  Serial: $serial"
  log_info "$COMPONENT" "  Epoch: $epoch"
  log_info "$COMPONENT" "  Snapshot: $snapshot_url"

  # Create output directory
  mkdir -p "$output_dir/checksums"

  # Save parameters
  echo "$serial" > "$output_dir/serial.txt"
  echo "$epoch" > "$output_dir/epoch.txt"
  echo "$timestamp" > "$output_dir/timestamp.txt"
  echo "$snapshot_url" > "$output_dir/snapshot-url.txt"

  # Copy checksums for requested suites (or all if not specified)
  if [ -n "$suites" ]; then
    for suite in $suites; do
      local checksum_file="$suite/rootfs.tar.xz.sha256"
      if [ -f "$checksum_file" ]; then
        cp "$checksum_file" "$output_dir/checksums/$suite.sha256"
        log_info "$COMPONENT" "Copied checksum for $suite"
      else
        log_warn "$COMPONENT" "Checksum not found for suite: $suite"
      fi
    done
  else
    # Copy all checksums
    for suite_dir in */; do
      suite="${suite_dir%/}"
      local checksum_file="$suite/rootfs.tar.xz.sha256"
      if [ -f "$checksum_file" ]; then
        cp "$checksum_file" "$output_dir/checksums/$suite.sha256"
        log_debug "$COMPONENT" "Copied checksum for $suite"
      fi
    done
  fi

  local duration
  duration=$(timer_end "fetch_official")
  log_info "$COMPONENT" "Completed in ${duration}s"

  # Output summary for GitHub Actions
  github_summary "### Official Build Parameters"
  github_summary "- **Architecture**: $arch"
  github_summary "- **Serial**: $serial"
  github_summary "- **Epoch**: $epoch"
  github_summary "- **Snapshot**: $snapshot_url"
}

main "$@"
