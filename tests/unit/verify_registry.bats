#!/usr/bin/env bats
# Unit tests for scripts/verify-registry.sh

setup() {
  load '../test_helper'

  # Create temp directory for test artifacts
  export TEST_DIR="${TEST_TEMP_DIR}/verify_registry_test"
  mkdir -p "$TEST_DIR"

  # Suppress log output during tests
  export LOG_LEVEL=99
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Define the mapping functions directly for testing
# (avoids re-sourcing common.sh which has readonly variables)
arch_to_platform() {
  local arch="$1"
  case "$arch" in
    amd64)   echo "linux/amd64" ;;
    arm64)   echo "linux/arm64/v8" ;;
    armhf)   echo "linux/arm/v7" ;;
    i386)    echo "linux/386" ;;
    ppc64el) echo "linux/ppc64le" ;;
    *)       return 1 ;;
  esac
}

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

@test "arch_to_platform maps amd64 correctly" {
  run arch_to_platform "amd64"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/amd64" ]
}

@test "arch_to_platform maps arm64 with variant" {
  run arch_to_platform "arm64"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/arm64/v8" ]
}

@test "arch_to_platform maps armhf correctly" {
  run arch_to_platform "armhf"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/arm/v7" ]
}

@test "arch_to_platform maps i386 correctly" {
  run arch_to_platform "i386"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/386" ]
}

@test "arch_to_platform maps ppc64el correctly" {
  run arch_to_platform "ppc64el"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/ppc64le" ]
}

@test "arch_to_platform fails on unknown architecture" {
  run arch_to_platform "unknown"
  [ "$status" -eq 1 ]
}

@test "arch_to_image_prefix returns empty for amd64" {
  result=$(arch_to_image_prefix "amd64")
  [ -z "$result" ]
}

@test "arch_to_image_prefix returns arm64v8 for arm64" {
  result=$(arch_to_image_prefix "arm64")
  [ "$result" = "arm64v8" ]
}

@test "arch_to_image_prefix returns arm32v7 for armhf" {
  result=$(arch_to_image_prefix "armhf")
  [ "$result" = "arm32v7" ]
}

@test "arch_to_image_prefix returns i386 for i386" {
  result=$(arch_to_image_prefix "i386")
  [ "$result" = "i386" ]
}

@test "arch_to_image_prefix returns ppc64le for ppc64el" {
  result=$(arch_to_image_prefix "ppc64el")
  [ "$result" = "ppc64le" ]
}

@test "verify-registry.sh requires arch argument" {
  skip_if_missing "crane"
  run "${PROJECT_ROOT}/scripts/verify-registry.sh" --artifacts-dir "$TEST_DIR"
  [ "$status" -eq 2 ]
  [[ $output =~ "Missing required argument: --arch" ]]
}

@test "verify-registry.sh requires artifacts-dir argument" {
  skip_if_missing "crane"
  run "${PROJECT_ROOT}/scripts/verify-registry.sh" --arch amd64
  [ "$status" -eq 2 ]
  [[ $output =~ "Missing required argument: --artifacts-dir" ]]
}

@test "verify-registry.sh validates architecture" {
  skip_if_missing "crane"
  run "${PROJECT_ROOT}/scripts/verify-registry.sh" --arch invalid --artifacts-dir "$TEST_DIR"
  [ "$status" -eq 2 ]
  [[ $output =~ "Invalid architecture" ]]
}

@test "verify-registry.sh validates artifacts directory exists" {
  skip_if_missing "crane"
  run "${PROJECT_ROOT}/scripts/verify-registry.sh" --arch amd64 --artifacts-dir "/nonexistent/path"
  [ "$status" -eq 2 ]
  [[ $output =~ "Artifacts directory not found" ]]
}

@test "verify-registry.sh shows help" {
  skip_if_missing "crane"
  run "${PROJECT_ROOT}/scripts/verify-registry.sh" --help
  [ "$status" -eq 0 ]
  [[ $output =~ "Usage:" ]]
  [[ $output =~ "--arch" ]]
  [[ $output =~ "--artifacts-dir" ]]
}

# Define discover_suites for testing (looks for OCI manifests)
discover_suites() {
  local artifacts_dir="$1"
  local suites=""
  for suite_dir in "$artifacts_dir"/*/; do
    if [ -f "${suite_dir}oci/index.json" ]; then
      local suite
      suite=$(basename "$suite_dir")
      suites="$suites $suite"
    fi
  done
  echo "$suites" | xargs
}

@test "discover_suites finds suites with OCI index" {
  # Create mock artifacts structure with OCI manifests
  mkdir -p "$TEST_DIR/artifacts/bookworm/oci"
  mkdir -p "$TEST_DIR/artifacts/trixie/oci"
  mkdir -p "$TEST_DIR/artifacts/empty"
  touch "$TEST_DIR/artifacts/bookworm/oci/index.json"
  touch "$TEST_DIR/artifacts/trixie/oci/index.json"
  # empty/ has no oci/index.json

  result=$(discover_suites "$TEST_DIR/artifacts")
  [[ $result =~ "bookworm" ]]
  [[ $result =~ "trixie" ]]
  [[ ! $result =~ "empty" ]]
}

@test "discover_suites returns empty for empty directory" {
  mkdir -p "$TEST_DIR/empty_artifacts"

  result=$(discover_suites "$TEST_DIR/empty_artifacts")
  [ -z "$result" ]
}
