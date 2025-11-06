#!/usr/bin/env bash
# Build a single Debian suite using debuerreotype

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="build"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --suite SUITE --arch ARCH --epoch EPOCH --output-dir DIR --image IMAGE

Build a single Debian suite using debuerreotype Docker image.

Required arguments:
  --suite SUITE         Suite name (bookworm, trixie, etc.)
  --arch ARCH           Debian architecture (amd64, arm64, armhf, etc.)
  --epoch EPOCH         Unix epoch timestamp for SOURCE_DATE_EPOCH
  --output-dir DIR      Output directory for build artifacts
  --image IMAGE         Debuerreotype Docker image tag

Optional arguments:
  --help               Display this help message

Examples:
  $0 --suite bookworm --arch amd64 --epoch 1760918400 \
     --output-dir ./output --image debuerreotype:0.16
EOF
}

#######################################
# Build suite with debuerreotype
#######################################
build_suite() {
  local suite="$1"
  local arch="$2"
  local epoch="$3"
  local output_dir="$4"
  local image="$5"

  timer_start "build_$suite"

  log_info "$COMPONENT" "Building $suite for $arch (epoch: $epoch)"

  # Ensure output directory exists
  mkdir -p "$output_dir"

  # Run debuerreotype in Docker
  # Security capabilities required for debootstrap operations
  local build_output
  build_output=$(mktemp)

  if ! docker run \
    --rm \
    --cap-add SYS_ADMIN \
    --cap-drop SETFCAP \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --tmpfs /tmp:dev,exec,suid,noatime \
    --env TZ=UTC \
    --env SOURCE_DATE_EPOCH="$epoch" \
    --env TMPDIR=/tmp \
    --volume "$(realpath "$output_dir"):/output" \
    "$image" \
    sh -c "
      set -ex
      cd /tmp
      echo 'Building $suite for $arch...'
      /opt/debuerreotype/examples/debian.sh \
        --arch='$arch' \
        /output \
        '$suite' \
        '@$epoch'
    " > "$build_output" 2>&1; then
    log_error "$COMPONENT" "Build failed for $suite"
    log_error "$COMPONENT" "Last 20 lines of output:"
    tail -20 "$build_output" | while IFS= read -r line; do
      log_error "$COMPONENT" "  $line"
    done
    rm -f "$build_output"
    github_annotate "error" "Build failed for $suite ($arch)"
    return 1
  fi

  rm -f "$build_output"

  local duration
  duration=$(timer_end "build_$suite")
  log_info "$COMPONENT" "Completed $suite in ${duration}s"

  return 0
}

#######################################
# Main function
#######################################
main() {
  require_commands docker realpath

  local suite=""
  local arch=""
  local epoch=""
  local output_dir=""
  local image=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --suite)
        suite="$2"
        shift 2
        ;;
      --arch)
        arch="$2"
        shift 2
        ;;
      --epoch)
        epoch="$2"
        shift 2
        ;;
      --output-dir)
        output_dir="$2"
        shift 2
        ;;
      --image)
        image="$2"
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
  if [ -z "$suite" ] || [ -z "$arch" ] || [ -z "$epoch" ] || \
     [ -z "$output_dir" ] || [ -z "$image" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 1
  fi

  # Build the suite
  if build_suite "$suite" "$arch" "$epoch" "$output_dir" "$image"; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
