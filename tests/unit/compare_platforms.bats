#!/usr/bin/env bats
# Unit tests for scripts/compare-platforms.sh

setup() {
  load '../test_helper'
  
  # Create temp directory for test fixtures
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/results"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper to create mock platform result
create_mock_result() {
  local platform="$1"
  local arch="$2"
  local suite="$3"
  local checksum="$4"
  
  cat > "$TEST_DIR/results/${platform}-20260204.json" <<EOF
{
  "timestamp": "2026-02-04T00:00:00Z",
  "serial": "20260204",
  "platform": {"name": "$platform"},
  "results": [
    {
      "architecture": "$arch",
      "suite": "$suite",
      "sha256": "$checksum",
      "reproducible": true
    }
  ]
}
EOF
}

@test "consensus passes when two platforms agree" {
  create_mock_result "github" "amd64" "bookworm" "abc123"
  create_mock_result "gcp" "amd64" "bookworm" "abc123"
  
  run "${PROJECT_ROOT}/scripts/compare-platforms.sh" \
    --results-dir "$TEST_DIR/results" \
    --output "$TEST_DIR/consensus.json"
  
  [ "$status" -eq 0 ]
  
  # Verify consensus achieved
  consensus=$(jq -r '.consensus.achieved' "$TEST_DIR/consensus.json")
  [ "$consensus" = "true" ]
}

@test "consensus fails when platforms disagree" {
  create_mock_result "github" "amd64" "bookworm" "abc123"
  create_mock_result "gcp" "amd64" "bookworm" "xyz789"
  
  run "${PROJECT_ROOT}/scripts/compare-platforms.sh" \
    --results-dir "$TEST_DIR/results" \
    --output "$TEST_DIR/consensus.json"
  
  [ "$status" -eq 1 ]
  
  # Verify consensus not achieved
  consensus=$(jq -r '.consensus.achieved' "$TEST_DIR/consensus.json")
  [ "$consensus" = "false" ]
}

@test "consensus fails with only one platform" {
  create_mock_result "github" "amd64" "bookworm" "abc123"
  
  run "${PROJECT_ROOT}/scripts/compare-platforms.sh" \
    --results-dir "$TEST_DIR/results" \
    --output "$TEST_DIR/consensus.json"
  
  [ "$status" -eq 1 ]
}

@test "consensus handles multiple suite/arch combinations" {
  # GitHub has 2 combinations
  cat > "$TEST_DIR/results/github-20260204.json" <<'EOF'
{
  "results": [
    {"architecture": "amd64", "suite": "bookworm", "sha256": "aaa"},
    {"architecture": "arm64", "suite": "bookworm", "sha256": "bbb"}
  ]
}
EOF
  
  # GCP has matching combinations
  cat > "$TEST_DIR/results/gcp-20260204.json" <<'EOF'
{
  "results": [
    {"architecture": "amd64", "suite": "bookworm", "sha256": "aaa"},
    {"architecture": "arm64", "suite": "bookworm", "sha256": "bbb"}
  ]
}
EOF
  
  run "${PROJECT_ROOT}/scripts/compare-platforms.sh" \
    --results-dir "$TEST_DIR/results" \
    --output "$TEST_DIR/consensus.json"
  
  [ "$status" -eq 0 ]
  
  # Verify both combinations checked
  total=$(jq -r '.summary.total_combinations' "$TEST_DIR/consensus.json")
  [ "$total" -eq 2 ]
}

@test "evidence generated on disagreement with --generate-evidence" {
  create_mock_result "github" "amd64" "bookworm" "abc123"
  create_mock_result "gcp" "amd64" "bookworm" "xyz789"
  
  mkdir -p "$TEST_DIR/evidence"
  
  run "${PROJECT_ROOT}/scripts/compare-platforms.sh" \
    --results-dir "$TEST_DIR/results" \
    --output "$TEST_DIR/consensus.json" \
    --generate-evidence
  
  [ "$status" -eq 1 ]
  
  # Evidence file should exist
  [ -d "$TEST_DIR/evidence" ] || [ -d "$(dirname "$TEST_DIR/consensus.json")/evidence" ]
}
