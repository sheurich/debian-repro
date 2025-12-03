#!/usr/bin/env bash
# Verify Docker Hub images match docker-debian-artifacts checksums
#
# Compares the uncompressed rootfs checksum (diff_id) from Docker Hub
# against the decompressed rootfs.tar.xz from the artifacts repository.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="verify-registry"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") --arch ARCH --artifacts-dir DIR [options]

Verify Docker Hub images match docker-debian-artifacts checksums.

Required arguments:
  --arch ARCH           Architecture (amd64, arm64, armhf, i386, ppc64el)
  --artifacts-dir DIR   Directory containing rootfs.tar.xz files per suite

Optional arguments:
  --suites SUITES       Space-separated list of suites (default: auto-discover)
  --output FILE         Output JSON file (default: stdout)
  --help                Display this help message

Exit codes:
  0 - All images match artifacts
  1 - One or more mismatches detected
  2 - Invalid arguments
  3 - Network or tool error

Examples:
  $(basename "$0") --arch amd64 --artifacts-dir ./official-amd64
  $(basename "$0") --arch arm64 --artifacts-dir ./official-arm64 --suites "bookworm trixie"
  $(basename "$0") --arch amd64 --artifacts-dir ./official-amd64 --output results.json
EOF
}

#######################################
# Map dpkg architecture to Docker platform
# Arguments:
#   $1 - dpkg architecture name
# Outputs:
#   Docker platform string (e.g., linux/amd64)
# Returns:
#   0 on success, 1 on unknown architecture
#######################################
arch_to_platform() {
  local arch="$1"

  case "$arch" in
    amd64)   echo "linux/amd64" ;;
    arm64)   echo "linux/arm64/v8" ;;
    armhf)   echo "linux/arm/v7" ;;
    i386)    echo "linux/386" ;;
    ppc64el) echo "linux/ppc64le" ;;
    *)
      log_error "$COMPONENT" "Unknown architecture: $arch"
      return 1
      ;;
  esac
}

#######################################
# Map dpkg architecture to Docker Hub image prefix
# Arguments:
#   $1 - dpkg architecture name
# Outputs:
#   Image prefix (empty for amd64, e.g., "arm64v8" for arm64)
#######################################
arch_to_image_prefix() {
  local arch="$1"

  case "$arch" in
    amd64)   echo "" ;;
    arm64)   echo "arm64v8" ;;
    armhf)   echo "arm32v7" ;;
    i386)    echo "i386" ;;
    ppc64el) echo "ppc64le" ;;
    *)       echo "" ;;
  esac
}

#######################################
# Get rootfs diff_id from Docker Hub image config
# Arguments:
#   $1 - Full image reference (e.g., debian:bookworm)
#   $2 - Platform string (e.g., linux/amd64)
# Outputs:
#   SHA256 hash (without sha256: prefix)
# Returns:
#   0 on success, 1 on failure
#######################################
get_dockerhub_diffid() {
  local image="$1"
  local platform="$2"

  local config diffid
  if ! config=$(crane config --platform "$platform" "$image" 2>&1); then
    log_error "$COMPONENT" "Failed to fetch config for $image: $config"
    return 1
  fi

  diffid=$(echo "$config" | jq -r '.rootfs.diff_ids[0]' 2>/dev/null)
  if [ -z "$diffid" ] || [ "$diffid" = "null" ]; then
    log_error "$COMPONENT" "No diff_id found in config for $image"
    return 1
  fi

  # Strip sha256: prefix if present
  echo "${diffid#sha256:}"
}

#######################################
# Extract diff_id from OCI manifest in artifacts repository
# Arguments:
#   $1 - Path to suite directory (e.g., ./official-amd64/bookworm)
# Outputs:
#   SHA256 hash (without sha256: prefix)
# Returns:
#   0 on success, 1 on failure
#######################################
get_artifacts_diffid() {
  local suite_dir="$1"
  local oci_index="${suite_dir}/oci/index.json"

  if [ ! -f "$oci_index" ]; then
    log_error "$COMPONENT" "OCI index not found: $oci_index"
    return 1
  fi

  # Extract the embedded manifest data, then the config data, then the diff_id
  # Structure: index.json -> manifests[0].data (base64) -> config.data (base64) -> rootfs.diff_ids[0]
  local manifest_data config_data diffid

  manifest_data=$(jq -r '.manifests[0].data' "$oci_index" 2>/dev/null)
  if [ -z "$manifest_data" ] || [ "$manifest_data" = "null" ]; then
    log_error "$COMPONENT" "No manifest data in OCI index"
    return 1
  fi

  config_data=$(echo "$manifest_data" | base64 -d | jq -r '.config.data' 2>/dev/null)
  if [ -z "$config_data" ] || [ "$config_data" = "null" ]; then
    log_error "$COMPONENT" "No config data in manifest"
    return 1
  fi

  diffid=$(echo "$config_data" | base64 -d | jq -r '.rootfs.diff_ids[0]' 2>/dev/null)
  if [ -z "$diffid" ] || [ "$diffid" = "null" ]; then
    log_error "$COMPONENT" "No diff_id in config"
    return 1
  fi

  # Strip sha256: prefix if present
  echo "${diffid#sha256:}"
}

#######################################
# Verify a single suite against Docker Hub
# Arguments:
#   $1 - Suite name (e.g., bookworm)
#   $2 - Architecture (e.g., amd64)
#   $3 - Artifacts directory
# Outputs:
#   JSON result object
# Returns:
#   0 on match, 1 on mismatch
#######################################
verify_suite() {
  local suite="$1"
  local arch="$2"
  local artifacts_dir="$3"

  local platform image_prefix image suite_dir
  platform=$(arch_to_platform "$arch")
  image_prefix=$(arch_to_image_prefix "$arch")

  # Construct image reference
  if [ -n "$image_prefix" ]; then
    image="${image_prefix}/debian:${suite}"
  else
    image="debian:${suite}"
  fi

  # Path to suite directory containing OCI manifest
  suite_dir="${artifacts_dir}/${suite}"

  log_info "$COMPONENT" "Verifying $suite ($arch): $image"

  local dockerhub_diffid="" artifacts_diffid="" status="error" error_msg=""

  # Get Docker Hub diff_id
  if ! dockerhub_diffid=$(get_dockerhub_diffid "$image" "$platform"); then
    error_msg="Failed to fetch Docker Hub diff_id"
    status="error"
  # Get artifacts diff_id from OCI manifest
  elif ! artifacts_diffid=$(get_artifacts_diffid "$suite_dir"); then
    error_msg="Failed to extract artifacts diff_id from OCI manifest"
    status="error"
  # Compare
  elif [ "$dockerhub_diffid" = "$artifacts_diffid" ]; then
    status="match"
    log_info "$COMPONENT" "  MATCH: $dockerhub_diffid"
  else
    status="mismatch"
    log_error "$COMPONENT" "  MISMATCH:"
    log_error "$COMPONENT" "    Docker Hub: $dockerhub_diffid"
    log_error "$COMPONENT" "    Artifacts:  $artifacts_diffid"
  fi

  # Output JSON result
  jq -n \
    --arg suite "$suite" \
    --arg arch "$arch" \
    --arg status "$status" \
    --arg dockerhub_diffid "sha256:${dockerhub_diffid}" \
    --arg artifacts_diffid "sha256:${artifacts_diffid}" \
    --arg image "$image" \
    --arg platform "$platform" \
    --arg error "$error_msg" \
    '{
      suite: $suite,
      architecture: $arch,
      status: $status,
      dockerhub_diffid: $dockerhub_diffid,
      artifacts_diffid: $artifacts_diffid,
      image: $image,
      platform: $platform
    } + (if $error != "" then {error: $error} else {} end)'

  [ "$status" = "match" ]
}

#######################################
# Discover available suites from artifacts directory
# Arguments:
#   $1 - Artifacts directory
# Outputs:
#   Space-separated list of suite names
#######################################
discover_suites() {
  local artifacts_dir="$1"
  local suites=""

  for suite_dir in "$artifacts_dir"/*/; do
    # Look for OCI manifest which contains the diff_id
    if [ -f "${suite_dir}oci/index.json" ]; then
      local suite
      suite=$(basename "$suite_dir")
      suites="$suites $suite"
    fi
  done

  echo "$suites" | xargs  # Trim whitespace
}

#######################################
# Main function
#######################################
main() {
  require_commands crane jq

  local arch=""
  local artifacts_dir=""
  local suites=""
  local output_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --arch)
        arch="$2"
        shift 2
        ;;
      --artifacts-dir)
        artifacts_dir="$2"
        shift 2
        ;;
      --suites)
        suites="$2"
        shift 2
        ;;
      --output)
        output_file="$2"
        shift 2
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
  if [ -z "$arch" ]; then
    log_error "$COMPONENT" "Missing required argument: --arch"
    usage
    exit 2
  fi

  if [ -z "$artifacts_dir" ]; then
    log_error "$COMPONENT" "Missing required argument: --artifacts-dir"
    usage
    exit 2
  fi

  # Validate architecture
  if ! arch_to_platform "$arch" >/dev/null 2>&1; then
    log_error "$COMPONENT" "Invalid architecture: $arch"
    exit 2
  fi

  # Validate artifacts directory
  if [ ! -d "$artifacts_dir" ]; then
    log_error "$COMPONENT" "Artifacts directory not found: $artifacts_dir"
    exit 2
  fi

  # Auto-discover suites if not specified
  if [ -z "$suites" ]; then
    suites=$(discover_suites "$artifacts_dir")
    if [ -z "$suites" ]; then
      log_error "$COMPONENT" "No suites found in artifacts directory"
      exit 2
    fi
    log_info "$COMPONENT" "Discovered suites: $suites"
  fi

  # Get serial from artifacts directory if available
  local serial=""
  if [ -f "$artifacts_dir/../serial.txt" ]; then
    serial=$(cat "$artifacts_dir/../serial.txt")
  elif [ -f "$artifacts_dir/serial" ]; then
    serial=$(cat "$artifacts_dir/serial")
  fi

  timer_start "verify_registry"

  local results=()
  local total=0 matched=0 mismatched=0 errors=0

  # Verify each suite
  for suite in $suites; do
    local result
    result=$(verify_suite "$suite" "$arch" "$artifacts_dir")
    results+=("$result")
    total=$((total + 1))

    local status
    status=$(echo "$result" | jq -r '.status')
    case "$status" in
      match)     matched=$((matched + 1)) ;;
      mismatch)  mismatched=$((mismatched + 1)) ;;
      *)         errors=$((errors + 1)) ;;
    esac
  done

  local duration
  duration=$(timer_end "verify_registry")

  # Determine overall status
  local overall_status="pass"
  if [ "$mismatched" -gt 0 ] || [ "$errors" -gt 0 ]; then
    overall_status="fail"
  fi

  # Build JSON output
  local results_json
  results_json=$(printf '%s\n' "${results[@]}" | jq -s '.')

  local output
  output=$(jq -n \
    --arg timestamp "$(timestamp)" \
    --arg serial "$serial" \
    --arg arch "$arch" \
    --arg status "$overall_status" \
    --argjson results "$results_json" \
    --argjson total "$total" \
    --argjson matched "$matched" \
    --argjson mismatched "$mismatched" \
    --argjson errors "$errors" \
    --argjson duration "$duration" \
    '{
      timestamp: $timestamp,
      serial: $serial,
      architecture: $arch,
      status: $status,
      results: $results,
      summary: {
        total: $total,
        matched: $matched,
        mismatched: $mismatched,
        errors: $errors,
        duration_seconds: $duration
      }
    }')

  # Output result
  if [ -n "$output_file" ]; then
    echo "$output" > "$output_file"
    log_info "$COMPONENT" "Results written to: $output_file"
  else
    echo "$output"
  fi

  # GitHub Actions integration
  github_summary "### Registry Verification ($arch)"
  github_summary "- **Status**: $overall_status"
  github_summary "- **Matched**: $matched/$total"
  if [ "$mismatched" -gt 0 ]; then
    github_summary "- **Mismatched**: $mismatched"
    github_annotate "error" "Registry verification failed: $mismatched mismatch(es) detected"
  fi

  log_info "$COMPONENT" "Verification complete: $matched/$total matched (${duration}s)"

  # Exit with appropriate code
  if [ "$overall_status" = "pass" ]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
