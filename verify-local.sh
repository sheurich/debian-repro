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

# Get supported architectures from Docker/buildx
detect_supported_architectures() {
  local platforms

  # Try to get platforms from default buildx builder
  if platforms=$(docker buildx inspect 2>/dev/null | grep "Platforms:" | head -1); then
    # Parse platforms line: "Platforms: linux/arm64, linux/amd64, linux/386"
    # Extract just the architecture part after "linux/"
    echo "$platforms" | sed 's/.*Platforms: *//' | tr ',' '\n' | sed 's|linux/||g' | sed 's|/.*||g' | tr '\n' ' ' | sed 's/ *$//'
  else
    # Fallback: assume only native architecture is supported
    detect_native_arch
  fi
}

# Verify if target architecture is supported
verify_architecture_support() {
  local target_arch="$1"
  local supported_archs="$2"

  # Check if target is in supported list
  for arch in $supported_archs; do
    if [ "$arch" = "$target_arch" ]; then
      return 0
    fi
  done

  return 1
}

# Detect Docker environment
get_docker_environment() {
  local docker_context
  docker_context=$(docker context show 2>/dev/null || echo "unknown")

  # Check for specific environments
  if [ "$docker_context" = "colima" ] || [ -S "$HOME/.colima/docker.sock" ]; then
    echo "colima"
  elif [ "$docker_context" = "orbstack" ] || [ -S "$HOME/.orbstack/run/docker.sock" ]; then
    echo "orbstack"
  else
    echo "docker"
  fi
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

  # Detect architectures and verify support
  local native_arch supported_archs docker_env os_name
  native_arch=$(detect_native_arch)
  supported_archs=$(detect_supported_architectures)
  docker_env=$(get_docker_environment)
  os_name=$(uname -s)

  log_debug "$COMPONENT" "Native arch: $native_arch"
  log_debug "$COMPONENT" "Supported architectures: $supported_archs"
  log_debug "$COMPONENT" "Docker environment: $docker_env"

  # Check if cross-architecture build is needed
  if [ "$ARCH" != "$native_arch" ]; then
    # Verify target architecture is supported
    if ! verify_architecture_support "$ARCH" "$supported_archs"; then
      log_warn "$COMPONENT" "Architecture '$ARCH' not detected in supported list"
      log_info "$COMPONENT" "Attempting to automatically enable $ARCH emulation..."

      # Try to install binfmt for this architecture
      local install_output
      install_output=$(mktemp)

      if docker run --privileged --rm tonistiigi/binfmt --install "$ARCH" > "$install_output" 2>&1; then
        # Check if installation was successful
        if grep -q "installing:.*OK\|already registered" "$install_output"; then
          log_debug "$COMPONENT" "binfmt installation completed"

          # Verify installation worked by querying binfmt directly (buildx caches platform detection)
          local binfmt_check
          binfmt_check=$(docker run --privileged --rm tonistiigi/binfmt 2>/dev/null)

          # Check if target architecture is in the supported list from binfmt
          if echo "$binfmt_check" | jq -r '.supported[]?' 2>/dev/null | grep -q "linux/$ARCH"; then
            log_info "$COMPONENT" "✓ Successfully enabled $ARCH emulation"
            rm -f "$install_output"

            # Update supported_archs for the rest of the script
            # Note: buildx may still show old list until recreated, but binfmt works
            supported_archs="$supported_archs $ARCH"
          else
            log_error "$COMPONENT" "✗ Installation appeared successful but $ARCH still not detected"
            log_debug "$COMPONENT" "binfmt output: $binfmt_check"
            rm -f "$install_output"
            # Fall through to error handling below
          fi
        else
          log_warn "$COMPONENT" "binfmt installation did not report success"
          rm -f "$install_output"
          # Fall through to error handling below
        fi
      else
        log_warn "$COMPONENT" "Unable to automatically install binfmt (requires --privileged access)"
        rm -f "$install_output"
        # Fall through to error handling below
      fi

      # Final check - if still not supported, show detailed error
      if ! verify_architecture_support "$ARCH" "$supported_archs"; then
        log_error "$COMPONENT" "Architecture '$ARCH' is not supported by your Docker environment"
        log_error "$COMPONENT" "Supported architectures: $supported_archs"
        log_error "$COMPONENT" ""

        # Provide environment-specific guidance
        case "$docker_env" in
          colima)
            log_error "$COMPONENT" "To enable cross-architecture builds with Colima:"
            log_error "$COMPONENT" "1. Edit ~/.colima/default/colima.yaml and set 'binfmt: true'"
            log_error "$COMPONENT" "2. Restart: colima stop && colima start"
            log_error "$COMPONENT" "3. Manually run: docker run --privileged --rm tonistiigi/binfmt --install all"
            ;;
          docker-desktop)
            log_error "$COMPONENT" "To enable cross-architecture builds with Docker Desktop:"
            log_error "$COMPONENT" "1. Open Docker Desktop settings"
            log_error "$COMPONENT" "2. Enable 'Use Virtualization Framework' (disable Rosetta if enabled)"
            log_error "$COMPONENT" "3. Restart Docker Desktop"
            log_error "$COMPONENT" "4. Manually run: docker run --privileged --rm tonistiigi/binfmt --install all"
            ;;
          orbstack)
            log_error "$COMPONENT" "OrbStack should support multi-architecture by default"
            log_error "$COMPONENT" "Try manually: docker run --privileged --rm tonistiigi/binfmt --install all"
            ;;
          *)
            log_error "$COMPONENT" "To enable cross-architecture builds:"
            log_error "$COMPONENT" "Install qemu-user-static or enable binfmt support"
            log_error "$COMPONENT" "Run: docker run --privileged --rm tonistiigi/binfmt --install all"
            ;;
        esac

        exit 1
      fi
    else
      # Architecture is already supported - log informational message
      log_info "$COMPONENT" "Cross-architecture build: $native_arch → $ARCH (using emulation)"
    fi
  fi

  # Setup QEMU on Linux if needed (for compatibility)
  if [ "$os_name" = "Linux" ] && [ "$ARCH" != "$native_arch" ]; then
    log_debug "$COMPONENT" "Setting up QEMU for $ARCH emulation on Linux..."
    if ! docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
      log_debug "$COMPONENT" "QEMU setup command failed (may already be configured)"
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
