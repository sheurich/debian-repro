#!/usr/bin/env bats
# Integration tests for verification workflow

setup() {
  load '../test_helper'
  setup_fixtures

  export TEST_DIR="${TEST_TEMP_DIR}/verify_test"
  mkdir -p "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fetch-official.sh fetches parameters correctly" {
  skip_if_missing "git"

  run "${PROJECT_ROOT}/scripts/fetch-official.sh" \
    --arch amd64 \
    --output-dir "$TEST_DIR/official"

  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/official/serial.txt" ]
  [ -f "$TEST_DIR/official/epoch.txt" ]
  [ -f "$TEST_DIR/official/timestamp.txt" ]
  [ -f "$TEST_DIR/official/snapshot-url.txt" ]
  [ -d "$TEST_DIR/official/checksums" ]
}

@test "fetch-official.sh handles invalid architecture" {
  run "${PROJECT_ROOT}/scripts/fetch-official.sh" \
    --arch invalid-arch \
    --output-dir "$TEST_DIR/official"

  [ "$status" -eq 1 ]
  [[ $output =~ "Unknown architecture" ]]
}

@test "fetch-official.sh requires arch argument" {
  run "${PROJECT_ROOT}/scripts/fetch-official.sh" \
    --output-dir "$TEST_DIR/official"

  [ "$status" -eq 1 ]
  [[ $output =~ "Missing required arguments" ]]
}

@test "setup-matrix.sh generates valid JSON" {
  skip_if_missing "jq"

  # Suppress logging to get clean JSON output
  run bash -c "LOG_LEVEL=99 ${PROJECT_ROOT}/scripts/setup-matrix.sh --architectures 'amd64,arm64' 2>/dev/null"

  [ "$status" -eq 0 ]
  assert_valid_json "$output"

  # Check matrix structure
  echo "$output" | jq -e '.include | length == 2' >/dev/null
  echo "$output" | jq -e '.include[0].arch == "amd64"' >/dev/null
  echo "$output" | jq -e '.include[1].arch == "arm64"' >/dev/null
}

@test "setup-matrix.sh handles single architecture" {
  skip_if_missing "jq"

  run bash -c "LOG_LEVEL=99 ${PROJECT_ROOT}/scripts/setup-matrix.sh --architectures 'amd64' 2>/dev/null"

  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  echo "$output" | jq -e '.include | length == 1' >/dev/null
}

@test "setup-matrix.sh skips unknown architectures" {
  skip_if_missing "jq"

  run bash -c "LOG_LEVEL=99 ${PROJECT_ROOT}/scripts/setup-matrix.sh --architectures 'amd64,unknown,arm64' 2>/dev/null"

  [ "$status" -eq 0 ]
  assert_valid_json "$output"
  # Should have 2 entries (unknown skipped)
  echo "$output" | jq -e '.include | length == 2' >/dev/null
}

@test "capture-environment.sh generates valid JSON" {
  skip_if_missing "jq"

  run bash -c "LOG_LEVEL=99 ${PROJECT_ROOT}/scripts/capture-environment.sh 2>/dev/null"

  [ "$status" -eq 0 ]
  assert_valid_json "$output"

  # Check required fields
  assert_json_has_key "$output" "timestamp"
  assert_json_has_key "$output" "os"
  assert_json_has_key "$output" "docker"
  assert_json_has_key "$output" "git"
}

@test "capture-environment.sh writes to file" {
  skip_if_missing "jq"

  run bash -c "LOG_LEVEL=99 ${PROJECT_ROOT}/scripts/capture-environment.sh --output '$TEST_DIR/env.json' 2>/dev/null"

  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/env.json" ]
  assert_valid_json "$(cat "$TEST_DIR/env.json")"
}

@test "generate-report.sh requires results directory" {
  run "${PROJECT_ROOT}/scripts/generate-report.sh" \
    --output "$TEST_DIR/report.json"

  [ "$status" -eq 1 ]
  [[ $output =~ "Missing required arguments" ]]
}

@test "generate-report.sh handles missing results directory" {
  run "${PROJECT_ROOT}/scripts/generate-report.sh" \
    --results-dir "/nonexistent" \
    --output "$TEST_DIR/report.json"

  [ "$status" -eq 1 ]
  [[ $output =~ "Results directory not found" ]]
}

@test "generate-badges.sh requires report file" {
  run "${PROJECT_ROOT}/scripts/generate-badges.sh" \
    --output-dir "$TEST_DIR/badges"

  [ "$status" -eq 1 ]
  [[ $output =~ "Missing required arguments" ]]
}
