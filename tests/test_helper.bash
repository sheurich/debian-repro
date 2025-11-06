#!/usr/bin/env bash
# Common test helper functions for BATS tests

# Get project root directory (parent of tests/ directory)
# Handle both tests/unit/ and tests/integration/ paths
if [[ "${BATS_TEST_DIRNAME}" == */tests/unit || "${BATS_TEST_DIRNAME}" == */tests/integration ]]; then
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
else
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
fi

# Test temp directory
export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}"

# Setup test fixtures
setup_fixtures() {
  export FIXTURES_DIR="${PROJECT_ROOT}/tests/fixtures"
}

# Create mock GitHub Actions environment
setup_github_env() {
  export GITHUB_ACTIONS=true
  export GITHUB_STEP_SUMMARY="${TEST_TEMP_DIR}/step_summary.txt"
  export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"
  touch "$GITHUB_STEP_SUMMARY"
  touch "$GITHUB_OUTPUT"
}

# Clean up GitHub Actions environment
teardown_github_env() {
  unset GITHUB_ACTIONS
  unset GITHUB_STEP_SUMMARY
  unset GITHUB_OUTPUT
}

# Create mock official artifacts structure
create_mock_official_artifacts() {
  local dir="$1"
  local serial="${2:-20251020}"
  local epoch="${3:-1760918400}"

  mkdir -p "$dir"
  echo "$serial" > "$dir/serial"
  echo "$epoch" > "$dir/debuerreotype-epoch"

  # Create suite directories with checksums
  for suite in bookworm trixie; do
    mkdir -p "$dir/$suite"
    echo "abc123def456789000000000000000000000000000000000000000000000000 rootfs.tar.xz" \
      > "$dir/$suite/rootfs.tar.xz.sha256"
  done
}

# Create mock build output
create_mock_build_output() {
  local dir="$1"
  local serial="${2:-20251020}"
  local arch="${3:-amd64}"

  mkdir -p "$dir/$serial/$arch/bookworm"
  mkdir -p "$dir/$serial/$arch/trixie"

  # Create dummy tar files
  touch "$dir/$serial/$arch/bookworm/rootfs.tar.xz"
  touch "$dir/$serial/$arch/trixie/rootfs.tar.xz"
}

# Assert file contains string
assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [ -f "$file" ] || {
    echo "File not found: $file" >&2
    return 1
  }

  grep -q "$pattern" "$file" || {
    echo "Pattern '$pattern' not found in $file" >&2
    echo "File contents:" >&2
    cat "$file" >&2
    return 1
  }
}

# Assert JSON is valid
assert_valid_json() {
  local json="$1"
  echo "$json" | jq empty 2>/dev/null || {
    echo "Invalid JSON: $json" >&2
    return 1
  }
}

# Assert JSON has key
assert_json_has_key() {
  local json="$1"
  local key="$2"

  echo "$json" | jq -e ".$key" >/dev/null 2>&1 || {
    echo "JSON missing key: $key" >&2
    echo "JSON: $json" >&2
    return 1
  }
}

# Skip test if command not available
skip_if_missing() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    skip "$cmd not installed"
  fi
}
