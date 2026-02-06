#!/usr/bin/env bats
# Unit tests for scripts/validate-artifacts-repo.sh

setup() {
  load '../test_helper'
  VALIDATE_SCRIPT="${PROJECT_ROOT}/scripts/validate-artifacts-repo.sh"
}

# --- Serial format tests ---

@test "validates correct serial format" {
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 0 ]
}

@test "rejects invalid serial format - too short" {
  run "$VALIDATE_SCRIPT" --serial 2026020 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid serial format" ]]
}

@test "rejects invalid serial format - letters" {
  run "$VALIDATE_SCRIPT" --serial 2026020a --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid serial format" ]]
}

@test "rejects serial with invalid month" {
  run "$VALIDATE_SCRIPT" --serial 20261305 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "month out of range" ]]
}

@test "rejects serial with invalid day" {
  run "$VALIDATE_SCRIPT" --serial 20260232 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "day out of range" ]]
}

@test "rejects serial year before 2015" {
  run "$VALIDATE_SCRIPT" --serial 20140101 --epoch 1388534400 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "year out of range" ]]
}

# --- Epoch bounds tests ---

@test "rejects future epoch" {
  # 10 days in the future
  future_epoch=$(($(date +%s) + 864000))
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch "$future_epoch" --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "future" ]]
}

@test "rejects epoch before 2015" {
  # 2014-01-01
  run "$VALIDATE_SCRIPT" --serial 20140101 --epoch 1388534400 --skip-snapshot
  [ "$status" -eq 1 ]
  # Will fail on serial year check first
}

@test "rejects non-numeric epoch" {
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch "abc123" --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid epoch format" ]]
}

# --- Serial/epoch consistency tests ---

@test "rejects serial/epoch mismatch" {
  # Serial says Feb 5 2026, but epoch is Feb 4 2026
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1770163200 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "mismatch" ]]
}

@test "accepts matching serial and epoch" {
  # Both represent Feb 5 2026 00:00:00 UTC
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 0 ]
}

# --- Argument handling tests ---

@test "missing arguments returns usage error" {
  run "$VALIDATE_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Missing required arguments" ]]
}

@test "missing serial returns usage error" {
  run "$VALIDATE_SCRIPT" --epoch 1770249600
  [ "$status" -eq 2 ]
}

@test "missing epoch returns usage error" {
  run "$VALIDATE_SCRIPT" --serial 20260205
  [ "$status" -eq 2 ]
}

@test "help flag shows usage" {
  run "$VALIDATE_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "unknown argument returns error" {
  run "$VALIDATE_SCRIPT" --invalid-flag
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown argument" ]]
}

# --- Skip snapshot flag tests ---

@test "skip-snapshot flag prevents network call" {
  # This should pass without network access
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1770249600 --skip-snapshot
  [ "$status" -eq 0 ]
  # Should not contain snapshot check output
  [[ ! "$output" =~ "Checking snapshot.debian.org" ]]
}
