#!/usr/bin/env bash
# Wrapper script for building multiple Debian suites in parallel or sequentially

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="build-wrapper"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --suites SUITES --arch ARCH --epoch EPOCH --output-dir DIR --image IMAGE [options]

Build multiple Debian suites using debuerreotype.

Required arguments:
  --suites SUITES      Space-separated list of suites
  --arch ARCH          Debian architecture
  --epoch EPOCH        Unix epoch timestamp for SOURCE_DATE_EPOCH
  --output-dir DIR     Output directory for build artifacts
  --image IMAGE        Debuerreotype Docker image tag

Optional arguments:
  --parallel           Build suites in parallel (default: sequential)
  --max-jobs N         Maximum parallel jobs (default: number of CPUs)
  --help               Display this help message

Examples:
  $0 --suites "bookworm trixie" --arch amd64 --epoch 1760918400 \
     --output-dir ./output --image debuerreotype:0.16

  $0 --suites "bookworm trixie bullseye" --arch arm64 --epoch 1760918400 \
     --output-dir ./output --image debuerreotype:0.16 --parallel --max-jobs 2
EOF
}

#######################################
# Build suites sequentially
#######################################
build_sequential() {
  local suites="$1"
  local arch="$2"
  local epoch="$3"
  local output_dir="$4"
  local image="$5"

  log_info "$COMPONENT" "Building suites sequentially: $suites"

  local failed=0
  for suite in $suites; do
    if ! "${SCRIPT_DIR}/build-suite.sh" \
      --suite "$suite" \
      --arch "$arch" \
      --epoch "$epoch" \
      --output-dir "$output_dir" \
      --image "$image"; then
      log_error "$COMPONENT" "Failed to build $suite"
      failed=1
    fi
  done

  return $failed
}

#######################################
# Build suites in parallel using GNU parallel or background jobs
#######################################
build_parallel() {
  local suites="$1"
  local arch="$2"
  local epoch="$3"
  local output_dir="$4"
  local image="$5"
  local max_jobs="$6"

  log_info "$COMPONENT" "Building suites in parallel (max jobs: $max_jobs): $suites"

  if command_exists parallel; then
    # Use GNU parallel if available
    log_debug "$COMPONENT" "Using GNU parallel"

    echo "$suites" | tr ' ' '\n' | parallel -j "$max_jobs" \
      "${SCRIPT_DIR}/build-suite.sh" \
        --suite {} \
        --arch "$arch" \
        --epoch "$epoch" \
        --output-dir "$output_dir" \
        --image "$image"

    return "${PIPESTATUS[1]}"
  else
    # Fall back to background jobs
    log_debug "$COMPONENT" "Using background jobs (GNU parallel not available)"

    local pids=()
    local failed=0
    local running=0

    for suite in $suites; do
      # Wait if we've reached max jobs
      while [ "$running" -ge "$max_jobs" ]; do
        for pid in "${pids[@]}"; do
          if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" || failed=1
            running=$((running - 1))
          fi
        done
        sleep 0.1
      done

      # Start build in background
      "${SCRIPT_DIR}/build-suite.sh" \
        --suite "$suite" \
        --arch "$arch" \
        --epoch "$epoch" \
        --output-dir "$output_dir" \
        --image "$image" &

      pids+=($!)
      running=$((running + 1))
      log_debug "$COMPONENT" "Started build for $suite (PID: $!)"
    done

    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
      wait "$pid" || failed=1
    done

    return $failed
  fi
}

#######################################
# Main function
#######################################
main() {
  require_commands docker

  local suites=""
  local arch=""
  local epoch=""
  local output_dir=""
  local image=""
  local parallel=false
  local max_jobs
  max_jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "2")

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --suites)
        suites="$2"
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
      --parallel)
        parallel=true
        shift
        ;;
      --max-jobs)
        max_jobs="$2"
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
  if [ -z "$suites" ] || [ -z "$arch" ] || [ -z "$epoch" ] || \
     [ -z "$output_dir" ] || [ -z "$image" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 1
  fi

  timer_start "build_all"

  # Build suites
  local result
  if [ "$parallel" = true ]; then
    build_parallel "$suites" "$arch" "$epoch" "$output_dir" "$image" "$max_jobs"
    result=$?
  else
    build_sequential "$suites" "$arch" "$epoch" "$output_dir" "$image"
    result=$?
  fi

  local duration
  duration=$(timer_end "build_all")
  log_info "$COMPONENT" "Total build time: ${duration}s"

  exit $result
}

main "$@"
