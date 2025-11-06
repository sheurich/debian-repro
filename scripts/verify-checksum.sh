#!/usr/bin/env bash
# Verify reproducibility by comparing SHA256 checksums

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="verify"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --build-dir DIR --official-dir DIR --suite SUITE --arch ARCH --dpkg-arch DPKG_ARCH --serial SERIAL

Verify reproducibility by comparing SHA256 checksums between local build and official artifacts.

Required arguments:
  --build-dir DIR       Directory containing build output
  --official-dir DIR    Directory containing official checksums
  --suite SUITE         Debian suite name (bookworm, trixie, etc.)
  --arch ARCH           Architecture name (amd64, arm64, etc.)
  --dpkg-arch DPKG_ARCH Debian package architecture name
  --serial SERIAL       Build serial (YYYYMMDD)

Optional arguments:
  --json               Output results as JSON
  --help               Display this help message

Exit codes:
  0 - Checksums match (reproducible)
  1 - Checksums don't match or file missing
  2 - Invalid arguments

Examples:
  $0 --build-dir ./output --official-dir ./official-amd64 \
     --suite bookworm --arch amd64 --dpkg-arch amd64 --serial 20251020
EOF
}

#######################################
# Compare checksums and report result
# Returns:
#   0 if match, 1 if mismatch or missing
#######################################
verify_suite() {
  local build_dir="$1"
  local official_dir="$2"
  local suite="$3"
  local arch="$4"
  local dpkg_arch="$5"
  local serial="$6"
  local json_output="$7"

  timer_start "verify_$suite"

  # Path to our build
  local our_file="${build_dir}/${serial}/${dpkg_arch}/${suite}/rootfs.tar.xz"
  if [ ! -f "$our_file" ]; then
    log_error "$COMPONENT" "Build file not found: $our_file"
    github_annotate "error" "Build file not found for ${suite} (${arch})"
    github_summary "### ❌ $suite"
    github_summary "Build failed - file not found"
    github_summary ""
    return 1
  fi

  # Calculate our checksum
  log_debug "$COMPONENT" "Computing SHA256 for $our_file"
  local our_sha256
  our_sha256=$(sha256sum "$our_file" | cut -d' ' -f1)

  # Get official checksum
  local official_file="${official_dir}/checksums/${suite}.sha256"
  if [ ! -f "$official_file" ]; then
    log_warn "$COMPONENT" "Official checksum not found for $suite"
    github_summary "### ⚠️ $suite"
    github_summary "Official checksum not found"
    github_summary "- Our SHA256: \`$our_sha256\`"
    github_summary ""

    if [ "$json_output" = "true" ]; then
      jq -n \
        --arg suite "$suite" \
        --arg arch "$arch" \
        --arg status "unknown" \
        --arg our_sha "$our_sha256" \
        '{suite: $suite, arch: $arch, status: $status, our_sha256: $our_sha}'
    fi

    return 1
  fi

  local official_sha256
  official_sha256=$(cut -d' ' -f1 < "$official_file")

  # Compare
  local duration
  duration=$(timer_end "verify_$suite")

  if [ "$our_sha256" = "$official_sha256" ]; then
    log_info "$COMPONENT" "✅ $suite ($arch): REPRODUCIBLE (${duration}s)"
    github_summary "### ✅ $suite"
    github_summary "**Reproducible!**"
    github_summary "- SHA256: \`$our_sha256\`"
    github_summary "- Build time: ${duration}s"
    github_summary ""

    if [ "$json_output" = "true" ]; then
      jq -n \
        --arg suite "$suite" \
        --arg arch "$arch" \
        --arg status "success" \
        --arg sha "$our_sha256" \
        --argjson time "$duration" \
        '{suite: $suite, arch: $arch, status: $status, reproducible: true, sha256: $sha, build_time_seconds: $time}'
    fi

    return 0
  else
    log_error "$COMPONENT" "❌ $suite ($arch): NOT REPRODUCIBLE"
    log_error "$COMPONENT" "  Official: $official_sha256"
    log_error "$COMPONENT" "  Ours:     $our_sha256"
    github_annotate "error" "Build for ${suite} (${arch}) is not reproducible"
    github_summary "### ❌ $suite"
    github_summary "**Not reproducible**"
    github_summary "- Official: \`$official_sha256\`"
    github_summary "- Ours: \`$our_sha256\`"
    github_summary "- Build time: ${duration}s"
    github_summary ""

    if [ "$json_output" = "true" ]; then
      jq -n \
        --arg suite "$suite" \
        --arg arch "$arch" \
        --arg status "failed" \
        --arg official "$official_sha256" \
        --arg ours "$our_sha256" \
        --argjson time "$duration" \
        '{suite: $suite, arch: $arch, status: $status, reproducible: false, official_sha256: $official, our_sha256: $ours, build_time_seconds: $time}'
    fi

    return 1
  fi
}

#######################################
# Main function
#######################################
main() {
  require_commands sha256sum cut jq

  local build_dir=""
  local official_dir=""
  local suite=""
  local arch=""
  local dpkg_arch=""
  local serial=""
  local json_output="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --build-dir)
        build_dir="$2"
        shift 2
        ;;
      --official-dir)
        official_dir="$2"
        shift 2
        ;;
      --suite)
        suite="$2"
        shift 2
        ;;
      --arch)
        arch="$2"
        shift 2
        ;;
      --dpkg-arch)
        dpkg_arch="$2"
        shift 2
        ;;
      --serial)
        serial="$2"
        shift 2
        ;;
      --json)
        json_output="true"
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "$COMPONENT" "Unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$build_dir" ] || [ -z "$official_dir" ] || [ -z "$suite" ] || \
     [ -z "$arch" ] || [ -z "$dpkg_arch" ] || [ -z "$serial" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 2
  fi

  log_info "$COMPONENT" "Verifying $suite for $arch"

  # Add header to GitHub summary
  github_summary "## Reproducibility Report ($arch)"
  github_summary ""

  # Verify and return result
  if verify_suite "$build_dir" "$official_dir" "$suite" "$arch" "$dpkg_arch" "$serial" "$json_output"; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
