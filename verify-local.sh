#!/usr/bin/env bash
# Quick local verification script for Debian reproducibility

set -Eeuo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
  # shellcheck source=./scripts/common.sh
  source "$SCRIPT_DIR/scripts/common.sh"
else
  echo "Error: common.sh not found" >&2
  exit 1
fi

readonly COMPONENT="verify-local"

# Detect native architecture
detect_native_arch() {
  local machine
  machine=$(uname -m)
  case "$machine" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    arm64) echo "arm64" ;;
    *) echo "amd64" ;;  # Default fallback
  esac
}

# Default configuration
ARCH="${ARCH:-$(detect_native_arch)}"
SUITES="${SUITES:-bookworm trixie}"
DEBUERREOTYPE_VERSION="0.16"
PARALLEL="${PARALLEL:-false}"
CLEAN="${CLEAN:-false}"

#######################################
# Display usage
#######################################
usage() {
  cat <<EOF
Usage: $0 [options]

Run complete Debian reproducibility verification locally.

Options:
  --arch ARCH           Architecture to verify (default: amd64)
  --suites "SUITES"     Space-separated suites (default: "bookworm trixie")
  --parallel            Build suites in parallel
  --clean               Clean previous builds before starting
  --help                Display this help

Environment variables:
  ARCH                  Same as --arch
  SUITES                Same as --suites
  PARALLEL              Set to "true" for parallel builds
  DEBUG                 Set to "1" for verbose output

Examples:
  # Verify bookworm and trixie for amd64
  $0

  # Verify single suite
  $0 --suites bookworm

  # Verify ARM64 (requires QEMU on x86_64)
  $0 --arch arm64

  # Parallel builds
  $0 --parallel --suites "bookworm trixie bullseye"

  # Clean previous builds first
  $0 --clean
EOF
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
  log_info "$COMPONENT" "Checking prerequisites..."

  require_commands docker git jq

  # Check Docker daemon
  if ! docker info >/dev/null 2>&1; then
    log_error "$COMPONENT" "Docker daemon not running"
    log_error "$COMPONENT" "Start Docker Desktop (macOS) or: sudo systemctl start docker (Linux)"
    exit 1
  fi

  # Warn about cross-architecture builds on macOS
  local host_arch native_arch os_name
  host_arch=$(uname -m)
  os_name=$(uname -s)
  native_arch=$(detect_native_arch)

  if [ "$os_name" = "Darwin" ] && [ "$ARCH" != "$native_arch" ]; then
    log_warn "$COMPONENT" "Cross-architecture builds on macOS may fail due to Rosetta limitations"
    log_warn "$COMPONENT" "Current arch: $ARCH, Native arch: $native_arch"
    log_warn "$COMPONENT" "For best results, use --arch $native_arch or run on Linux"

    # Give user a chance to abort
    log_info "$COMPONENT" "Continuing in 3 seconds... (Ctrl+C to abort)"
    sleep 3
  fi

  # Check QEMU for non-native architectures on Linux
  if [ "$os_name" = "Linux" ] && [ "$ARCH" != "$native_arch" ]; then
    log_info "$COMPONENT" "Setting up QEMU for $ARCH emulation..."
    if ! docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
      log_warn "$COMPONENT" "QEMU setup may have failed, proceeding anyway..."
    fi
  fi
}

#######################################
# Clean previous builds
#######################################
clean_builds() {
  log_info "$COMPONENT" "Cleaning previous builds..."
  rm -rf ./output ./official-* ./results
  log_info "$COMPONENT" "Clean complete"
}

#######################################
# Setup debuerreotype
#######################################
setup_debuerreotype() {
  timer_start "setup_debuerreotype"

  # Clone if not exists
  if [ ! -d debuerreotype ]; then
    log_info "$COMPONENT" "Cloning debuerreotype v${DEBUERREOTYPE_VERSION}..."
    if ! git clone --depth 1 https://github.com/debuerreotype/debuerreotype.git >/dev/null 2>&1; then
      log_error "$COMPONENT" "Failed to clone debuerreotype"
      exit 1
    fi
  fi

  # Checkout correct version
  cd debuerreotype
  log_debug "$COMPONENT" "Checking out v${DEBUERREOTYPE_VERSION}..."
  git fetch --tags >/dev/null 2>&1 || true
  git checkout "refs/tags/${DEBUERREOTYPE_VERSION}" >/dev/null 2>&1
  cd ..

  # Build Docker image if needed
  if ! docker image inspect "debuerreotype:${DEBUERREOTYPE_VERSION}" >/dev/null 2>&1; then
    log_info "$COMPONENT" "Building debuerreotype Docker image..."
    cd debuerreotype
    if ! docker build --pull -q -t "debuerreotype:${DEBUERREOTYPE_VERSION}" . >/dev/null 2>&1; then
      log_error "$COMPONENT" "Failed to build debuerreotype image"
      exit 1
    fi
    cd ..
  else
    log_debug "$COMPONENT" "Debuerreotype image already exists"
  fi

  local duration
  duration=$(timer_end "setup_debuerreotype")
  log_info "$COMPONENT" "Debuerreotype setup complete (${duration}s)"
}

#######################################
# Main function
#######################################
main() {
  log_info "$COMPONENT" "Starting local verification"
  log_info "$COMPONENT" "Architecture: $ARCH"
  log_info "$COMPONENT" "Suites: $SUITES"

  timer_start "total"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --arch)
        ARCH="$2"
        shift 2
        ;;
      --suites)
        SUITES="$2"
        shift 2
        ;;
      --parallel)
        PARALLEL=true
        shift
        ;;
      --clean)
        CLEAN=true
        shift
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

  # Clean if requested
  if [ "$CLEAN" = true ]; then
    clean_builds
  fi

  # Check prerequisites
  check_prerequisites

  # Setup debuerreotype
  setup_debuerreotype

  # Fetch official parameters
  log_info "$COMPONENT" "Fetching official parameters..."
  if ! "$SCRIPT_DIR/scripts/fetch-official.sh" \
    --arch "$ARCH" \
    --output-dir "./official-$ARCH" \
    --suites "$SUITES"; then
    log_error "$COMPONENT" "Failed to fetch official parameters"
    exit 1
  fi

  # Read parameters
  SERIAL=$(cat "./official-$ARCH/serial.txt")
  EPOCH=$(cat "./official-$ARCH/epoch.txt")

  log_info "$COMPONENT" "Official build: serial=$SERIAL, epoch=$EPOCH"

  # Build suites
  log_info "$COMPONENT" "Building suites..."
  local build_args=(
    --suites "$SUITES"
    --arch "$ARCH"
    --epoch "$EPOCH"
    --output-dir ./output
    --image "debuerreotype:${DEBUERREOTYPE_VERSION}"
  )

  if [ "$PARALLEL" = true ]; then
    build_args+=(--parallel)
    log_info "$COMPONENT" "Using parallel builds"
  fi

  if ! "$SCRIPT_DIR/scripts/build-wrapper.sh" "${build_args[@]}"; then
    log_error "$COMPONENT" "Build failed"
    exit 1
  fi

  # Verify each suite
  log_info "$COMPONENT" "Verifying reproducibility..."
  mkdir -p ./results

  local failed=0
  for suite in $SUITES; do
    if ! "$SCRIPT_DIR/scripts/verify-checksum.sh" \
      --build-dir ./output \
      --official-dir "./official-$ARCH" \
      --suite "$suite" \
      --arch "$ARCH" \
      --dpkg-arch "$ARCH" \
      --serial "$SERIAL"; then
      failed=1
    fi
  done

  # Generate report
  log_info "$COMPONENT" "Generating report..."
  "$SCRIPT_DIR/scripts/capture-environment.sh" \
    --output ./results/environment.json

  local duration
  duration=$(timer_end "total")

  # Final summary
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ $failed -eq 0 ]; then
    echo "✅ SUCCESS: All suites are reproducible!"
    echo "   Architecture: $ARCH"
    echo "   Suites: $SUITES"
    echo "   Total time: ${duration}s"
  else
    echo "❌ FAILURE: Some suites are not reproducible"
    echo "   Check logs above for details"
    echo "   Total time: ${duration}s"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  log_info "$COMPONENT" "Build artifacts saved to: ./output/$SERIAL/"
  log_info "$COMPONENT" "Official checksums in: ./official-$ARCH/checksums/"

  exit $failed
}

main "$@"
