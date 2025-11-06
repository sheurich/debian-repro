#!/usr/bin/env bash
# Generate GitHub Actions matrix JSON for architecture builds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="setup-matrix"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --architectures ARCHS

Generate GitHub Actions matrix JSON for architecture builds.

Required arguments:
  --architectures ARCHS Comma-separated list of architectures
                        (amd64, arm64, armhf, i386, ppc64el, s390x)

Optional arguments:
  --help               Display this help message

Output:
  JSON matrix suitable for GitHub Actions strategy.matrix

Examples:
  $0 --architectures amd64,arm64
  $0 --architectures "amd64, arm64, armhf"
EOF
}

#######################################
# Map architecture to matrix entry
# Arguments:
#   $1 - Architecture name
# Outputs:
#   JSON object with arch, dpkg_arch, runner, artifacts_branch
#######################################
arch_to_matrix_entry() {
  local arch="$1"

  case "$arch" in
    amd64)
      jq -n \
        --arg arch "amd64" \
        --arg dpkg_arch "amd64" \
        --arg runner "ubuntu-latest" \
        --arg branch "dist-amd64" \
        '{arch: $arch, dpkg_arch: $dpkg_arch, runner: $runner, artifacts_branch: $branch}'
      ;;
    arm64)
      jq -n \
        --arg arch "arm64" \
        --arg dpkg_arch "arm64" \
        --arg runner "ubuntu-latest" \
        --arg branch "dist-arm64v8" \
        '{arch: $arch, dpkg_arch: $dpkg_arch, runner: $runner, artifacts_branch: $branch}'
      ;;
    armhf)
      jq -n \
        --arg arch "armhf" \
        --arg dpkg_arch "armhf" \
        --arg runner "ubuntu-latest" \
        --arg branch "dist-arm32v7" \
        '{arch: $arch, dpkg_arch: $dpkg_arch, runner: $runner, artifacts_branch: $branch}'
      ;;
    i386)
      jq -n \
        --arg arch "i386" \
        --arg dpkg_arch "i386" \
        --arg runner "ubuntu-latest" \
        --arg branch "dist-i386" \
        '{arch: $arch, dpkg_arch: $dpkg_arch, runner: $runner, artifacts_branch: $branch}'
      ;;
    ppc64el)
      jq -n \
        --arg arch "ppc64el" \
        --arg dpkg_arch "ppc64le" \
        --arg runner "ubuntu-latest" \
        --arg branch "dist-ppc64le" \
        '{arch: $arch, dpkg_arch: $dpkg_arch, runner: $runner, artifacts_branch: $branch}'
      ;;
    s390x)
      log_warn "$COMPONENT" "s390x not yet available in artifacts repo, skipping"
      return 1
      ;;
    *)
      log_warn "$COMPONENT" "Unknown architecture: $arch, skipping"
      return 1
      ;;
  esac
}

#######################################
# Generate matrix JSON
# Arguments:
#   $1 - Comma-separated architectures
# Outputs:
#   JSON matrix
#######################################
generate_matrix() {
  local architectures="$1"

  # Parse comma-separated list
  IFS=',' read -ra ARCHS <<< "$architectures"

  log_info "$COMPONENT" "Generating matrix for architectures: ${ARCHS[*]}"

  # Collect valid entries
  local entries=()
  for arch in "${ARCHS[@]}"; do
    arch=$(echo "$arch" | xargs)  # trim whitespace

    if [ -z "$arch" ]; then
      continue
    fi

    local entry
    if entry=$(arch_to_matrix_entry "$arch"); then
      entries+=("$entry")
      log_debug "$COMPONENT" "Added $arch to matrix"
    fi
  done

  if [ ${#entries[@]} -eq 0 ]; then
    log_error "$COMPONENT" "No valid architectures provided"
    exit 1
  fi

  # Combine into matrix JSON
  local matrix
  matrix=$(jq -n \
    --argjson entries "$(printf '%s\n' "${entries[@]}" | jq -s .)" \
    '{include: $entries}')

  echo "$matrix"
  log_info "$COMPONENT" "Generated matrix with ${#entries[@]} entries"
}

#######################################
# Main function
#######################################
main() {
  require_commands jq

  local architectures=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --architectures)
        architectures="$2"
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
  if [ -z "$architectures" ]; then
    log_error "$COMPONENT" "Missing required argument: --architectures"
    usage
    exit 1
  fi

  # Generate and output matrix
  generate_matrix "$architectures"
}

main "$@"
