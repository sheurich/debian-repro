#!/usr/bin/env bats
# Integration tests for scripts/verify-registry.sh

setup() {
  load '../test_helper'

  export TEST_DIR="${TEST_TEMP_DIR}/verify_registry_integration"
  mkdir -p "$TEST_DIR"

  # Suppress log output
  export LOG_LEVEL=99
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "crane can connect to Docker Hub" {
  skip_if_missing "crane"

  run crane manifest --platform linux/amd64 debian:bookworm
  [ "$status" -eq 0 ]
  [[ $output =~ "schemaVersion" ]]
}

@test "crane config extracts diff_ids" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  result=$(crane config --platform linux/amd64 debian:bookworm | jq -r '.rootfs.diff_ids[0]')
  [[ $result =~ ^sha256:[a-f0-9]{64}$ ]]
}

@test "verify-registry.sh produces valid JSON with --output" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  # This test requires actual artifacts, so we skip if we can't fetch them
  # Create a minimal real test by fetching actual artifacts

  # Clone official artifacts for one suite
  local artifacts_dir="$TEST_DIR/official-amd64"
  if ! git clone --depth 1 --single-branch --branch dist-amd64 \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$artifacts_dir" 2>/dev/null; then
    skip "Could not clone docker-debian-artifacts"
  fi

  run "${PROJECT_ROOT}/scripts/verify-registry.sh" \
    --arch amd64 \
    --artifacts-dir "$artifacts_dir" \
    --suites "bookworm" \
    --output "$TEST_DIR/result.json"

  # Script may fail on mismatch, but JSON should be valid
  [ -f "$TEST_DIR/result.json" ]
  assert_valid_json "$(cat "$TEST_DIR/result.json")"

  # Check required JSON fields
  local json
  json=$(cat "$TEST_DIR/result.json")
  assert_json_has_key "$json" "timestamp"
  assert_json_has_key "$json" "architecture"
  assert_json_has_key "$json" "status"
  assert_json_has_key "$json" "results"
  assert_json_has_key "$json" "summary"
}

@test "verify-registry.sh JSON output includes result details" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  local artifacts_dir="$TEST_DIR/official-amd64"
  if ! git clone --depth 1 --single-branch --branch dist-amd64 \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$artifacts_dir" 2>/dev/null; then
    skip "Could not clone docker-debian-artifacts"
  fi

  "${PROJECT_ROOT}/scripts/verify-registry.sh" \
    --arch amd64 \
    --artifacts-dir "$artifacts_dir" \
    --suites "bookworm" \
    --output "$TEST_DIR/result.json" || true

  local json
  json=$(cat "$TEST_DIR/result.json")

  # Check result array structure
  local first_result
  first_result=$(echo "$json" | jq '.results[0]')

  [ "$(echo "$first_result" | jq -r '.suite')" = "bookworm" ]
  [ "$(echo "$first_result" | jq -r '.architecture')" = "amd64" ]
  [[ $(echo "$first_result" | jq -r '.status') =~ ^(match|mismatch|error)$ ]]
  [[ $(echo "$first_result" | jq -r '.dockerhub_diffid') =~ ^sha256: ]]
  [[ $(echo "$first_result" | jq -r '.image') =~ ^debian: ]]
}

@test "verify-registry.sh summary counts are correct" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  local artifacts_dir="$TEST_DIR/official-amd64"
  if ! git clone --depth 1 --single-branch --branch dist-amd64 \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$artifacts_dir" 2>/dev/null; then
    skip "Could not clone docker-debian-artifacts"
  fi

  "${PROJECT_ROOT}/scripts/verify-registry.sh" \
    --arch amd64 \
    --artifacts-dir "$artifacts_dir" \
    --suites "bookworm trixie" \
    --output "$TEST_DIR/result.json" || true

  local json
  json=$(cat "$TEST_DIR/result.json")

  local total matched mismatched errors
  total=$(echo "$json" | jq '.summary.total')
  matched=$(echo "$json" | jq '.summary.matched')
  mismatched=$(echo "$json" | jq '.summary.mismatched')
  errors=$(echo "$json" | jq '.summary.errors')

  # Total should equal matched + mismatched + errors
  [ "$total" -eq $((matched + mismatched + errors)) ]

  # Total should be 2 (bookworm + trixie)
  [ "$total" -eq 2 ]
}

@test "verify-registry.sh exits 0 on all matches" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  local artifacts_dir="$TEST_DIR/official-amd64"
  if ! git clone --depth 1 --single-branch --branch dist-amd64 \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$artifacts_dir" 2>/dev/null; then
    skip "Could not clone docker-debian-artifacts"
  fi

  run "${PROJECT_ROOT}/scripts/verify-registry.sh" \
    --arch amd64 \
    --artifacts-dir "$artifacts_dir" \
    --suites "bookworm" \
    --output "$TEST_DIR/result.json"

  # Check status based on result
  local status_val
  status_val=$(cat "$TEST_DIR/result.json" | jq -r '.status')

  if [ "$status_val" = "pass" ]; then
    [ "$status" -eq 0 ]
  else
    [ "$status" -eq 1 ]
  fi
}

@test "verify-registry.sh auto-discovers suites" {
  skip_if_missing "crane"
  skip_if_missing "jq"

  local artifacts_dir="$TEST_DIR/official-amd64"
  if ! git clone --depth 1 --single-branch --branch dist-amd64 \
    https://github.com/debuerreotype/docker-debian-artifacts.git \
    "$artifacts_dir" 2>/dev/null; then
    skip "Could not clone docker-debian-artifacts"
  fi

  # Run without --suites to test auto-discovery
  "${PROJECT_ROOT}/scripts/verify-registry.sh" \
    --arch amd64 \
    --artifacts-dir "$artifacts_dir" \
    --output "$TEST_DIR/result.json" || true

  local json
  json=$(cat "$TEST_DIR/result.json")

  # Should have discovered multiple suites
  local total
  total=$(echo "$json" | jq '.summary.total')
  [ "$total" -gt 1 ]
}
