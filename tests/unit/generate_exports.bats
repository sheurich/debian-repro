#!/usr/bin/env bats
# Tests for generate-exports.sh

load ../test_helper

# Load bats-support and bats-assert if available
# Check multiple locations: CI (/usr/lib), local (/tmp for testing)
if [ -f '/usr/lib/bats-support/load.bash' ]; then
  load '/usr/lib/bats-support/load'
elif [ -f '/tmp/bats-support/load.bash' ]; then
  load '/tmp/bats-support/load'
fi

if [ -f '/usr/lib/bats-assert/load.bash' ]; then
  load '/usr/lib/bats-assert/load'
elif [ -f '/tmp/bats-assert/load.bash' ]; then
  load '/tmp/bats-assert/load'
fi

setup() {
  export TEST_DIR="$(mktemp -d)"
  export REPORT_FILE="$TEST_DIR/report.json"
  export OUTPUT_DIR="$TEST_DIR/output"
  mkdir -p "$OUTPUT_DIR"

  # Create test report
  cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "2025-11-07T12:00:00Z",
  "run_id": "123456",
  "serial": "20251020",
  "epoch": 1760918400,
  "environment": {
    "timestamp": "2025-11-07T12:00:00Z",
    "platform": "ubuntu-24.04"
  },
  "architectures": {
    "amd64": {
      "status": "success",
      "suites": {
        "bookworm": {
          "reproducible": true,
          "sha256": "abc123def456",
          "build_time_seconds": 100
        },
        "trixie": {
          "reproducible": false,
          "sha256": "def456ghi789",
          "build_time_seconds": 120
        }
      }
    }
  }
}
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "generate-exports.sh: fails without required arguments" {
  run ./scripts/generate-exports.sh
  assert_failure
  assert_output --partial "Missing required arguments"
}

@test "generate-exports.sh: fails with non-existent report file" {
  run ./scripts/generate-exports.sh --report /nonexistent --output-dir "$OUTPUT_DIR"
  assert_failure
  assert_output --partial "Report file not found"
}

@test "generate-exports.sh: generates CSV export" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check CSV file exists
  assert [ -f "$OUTPUT_DIR/latest.csv" ]

  # Check CSV header
  run head -n 1 "$OUTPUT_DIR/latest.csv"
  assert_output --partial "architecture,suite,reproducible"

  # Check CSV has data rows
  local row_count=$(wc -l < "$OUTPUT_DIR/latest.csv" | tr -d ' ')
  assert [ "$row_count" -gt 1 ]
}

@test "generate-exports.sh: CSV contains correct data" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check for specific data
  run grep '"amd64","bookworm",true' "$OUTPUT_DIR/latest.csv"
  assert_success

  run grep '"amd64","trixie",false' "$OUTPUT_DIR/latest.csv"
  assert_success
}

@test "generate-exports.sh: generates JSON-LD export" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check JSON-LD file exists
  assert [ -f "$OUTPUT_DIR/latest.jsonld" ]

  # Validate JSON-LD structure
  run jq -e '.["@context"]' "$OUTPUT_DIR/latest.jsonld"
  assert_success
  assert_output "\"https://schema.org\""

  run jq -e '.["@graph"][0]["@type"]' "$OUTPUT_DIR/latest.jsonld"
  assert_success
  assert_output "\"Dataset\""
}

@test "generate-exports.sh: JSON-LD includes correct metrics" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check for reproducibility rate (50% = 1/2)
  run jq -e '.["@graph"][0].variableMeasured[] | select(.name == "reproducibility_rate") | .value' "$OUTPUT_DIR/latest.jsonld"
  assert_success
  assert_output "50"
}

@test "generate-exports.sh: generates history CSV when history.json exists" {
  # Create history file
  cat > "$TEST_DIR/history.json" <<EOF
[
  $(<"$REPORT_FILE")
]
EOF

  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check history CSV exists
  assert [ -f "$OUTPUT_DIR/history.csv" ]

  # Check history CSV has header
  run head -n 1 "$OUTPUT_DIR/history.csv"
  assert_output --partial "timestamp,serial,architecture"
}

@test "generate-exports.sh: creates output directory if missing" {
  rm -rf "$OUTPUT_DIR"

  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  assert [ -d "$OUTPUT_DIR" ]
  assert [ -f "$OUTPUT_DIR/latest.csv" ]
}

@test "generate-exports.sh: handles empty architectures" {
  cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "2025-11-07T12:00:00Z",
  "run_id": "123456",
  "serial": "20251020",
  "epoch": 0,
  "environment": {},
  "architectures": {}
}
EOF

  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # CSV should still have header
  assert [ -f "$OUTPUT_DIR/latest.csv" ]
  local row_count=$(wc -l < "$OUTPUT_DIR/latest.csv" | tr -d ' ')
  assert [ "$row_count" -eq 1 ]  # Only header
}

@test "generate-exports.sh: JSON-LD is valid JSON" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  run jq empty "$OUTPUT_DIR/latest.jsonld"
  assert_success
}

@test "generate-exports.sh: CSV is valid format" {
  run ./scripts/generate-exports.sh --report "$REPORT_FILE" --output-dir "$OUTPUT_DIR"
  assert_success

  # Check each line has same number of commas
  run awk -F',' 'NR==1{cols=NF} NF!=cols{exit 1}' "$OUTPUT_DIR/latest.csv"
  assert_success
}
