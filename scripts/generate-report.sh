#!/usr/bin/env bash
# Generate comprehensive JSON report for verification run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="report"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --results-dir DIR --output FILE [options]

Generate comprehensive JSON report combining verification results, environment, and metadata.

Required arguments:
  --results-dir DIR    Directory containing verification results
  --output FILE        Output JSON file

Optional arguments:
  --run-id ID          CI run ID (default: timestamp)
  --serial SERIAL      Build serial (YYYYMMDD)
  --epoch EPOCH        Build epoch timestamp
  --help               Display this help message

Expected structure in results-dir:
  - environment.json   (from capture-environment.sh)
  - {arch}-{suite}.json (from verify-checksum.sh --json)

Output format:
  {
    "timestamp": "2025-11-06T12:34:56Z",
    "run_id": "1234567890",
    "serial": "20251020",
    "epoch": 1760918400,
    "environment": {...},
    "architectures": {
      "amd64": {
        "status": "success",
        "suites": {
          "bookworm": {
            "reproducible": true,
            "sha256": "abc123...",
            "build_time_seconds": 456
          }
        }
      }
    }
  }

Examples:
  $0 --results-dir ./results --output ./report.json \
     --run-id 1234 --serial 20251020 --epoch 1760918400
EOF
}

#######################################
# Aggregate verification results by architecture
#######################################
aggregate_results() {
  local results_dir="$1"

  log_info "$COMPONENT" "Aggregating results from $results_dir"

  # Find all result JSON files (pattern: {arch}-{suite}.json)
  local result_files=()
  while IFS= read -r -d '' file; do
    result_files+=("$file")
  done < <(find "$results_dir" -name '*-*.json' -type f -print0 2>/dev/null)

  if [ ${#result_files[@]} -eq 0 ]; then
    log_warn "$COMPONENT" "No verification result files found"
    echo "{}"
    return
  fi

  log_debug "$COMPONENT" "Found ${#result_files[@]} result files"

  # Build architecture -> suite mapping
  local arch_data="{}"

  for result_file in "${result_files[@]}"; do
    local basename
    basename=$(basename "$result_file" .json)

    # Skip environment.json
    if [ "$basename" = "environment" ]; then
      continue
    fi

    # Parse filename: {arch}-{suite}.json
    local arch suite
    arch=$(echo "$basename" | cut -d'-' -f1)
    suite=$(echo "$basename" | cut -d'-' -f2-)

    log_debug "$COMPONENT" "Processing $arch / $suite"

    # Read result
    local result
    if ! result=$(cat "$result_file"); then
      log_warn "$COMPONENT" "Failed to read $result_file"
      continue
    fi

    # Check if arch exists in arch_data
    if ! echo "$arch_data" | jq -e ".\"$arch\"" >/dev/null 2>&1; then
      arch_data=$(echo "$arch_data" | jq \
        --arg arch "$arch" \
        '. + {($arch): {status: "pending", suites: {}}}')
    fi

    # Add suite result
    arch_data=$(echo "$arch_data" | jq \
      --arg arch "$arch" \
      --arg suite "$suite" \
      --argjson result "$result" \
      '.[$arch].suites[$suite] = $result')

    # Update architecture status
    local reproducible
    reproducible=$(echo "$result" | jq -r '.reproducible // false')

    if [ "$reproducible" != "true" ]; then
      arch_data=$(echo "$arch_data" | jq \
        --arg arch "$arch" \
        '.[$arch].status = "failed"')
    else
      # Only set success if not already failed
      local current_status
      current_status=$(echo "$arch_data" | jq -r ".\"$arch\".status")
      if [ "$current_status" = "pending" ]; then
        arch_data=$(echo "$arch_data" | jq \
          --arg arch "$arch" \
          '.[$arch].status = "success"')
      fi
    fi
  done

  echo "$arch_data"
}

#######################################
# Generate complete report
#######################################
generate_report() {
  local results_dir="$1"
  local run_id="$2"
  local serial="$3"
  local epoch="$4"

  timer_start "generate_report"

  # Load environment if available
  local environment="{}"
  if [ -f "$results_dir/environment.json" ]; then
    environment=$(cat "$results_dir/environment.json")
    log_debug "$COMPONENT" "Loaded environment data"
  else
    log_warn "$COMPONENT" "No environment.json found"
  fi

  # Aggregate verification results
  local architectures
  architectures=$(aggregate_results "$results_dir")

  # Build final report
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local report
  report=$(jq -n \
    --arg ts "$timestamp" \
    --arg run_id "$run_id" \
    --arg serial "$serial" \
    --arg epoch "$epoch" \
    --argjson env "$environment" \
    --argjson archs "$architectures" \
    '{
      timestamp: $ts,
      run_id: $run_id,
      serial: $serial,
      epoch: ($epoch | tonumber),
      environment: $env,
      architectures: $archs
    }')

  local duration
  duration=$(timer_end "generate_report")
  log_info "$COMPONENT" "Report generated in ${duration}s"

  echo "$report"
}

#######################################
# Main function
#######################################
main() {
  require_commands jq find

  local results_dir=""
  local output_file=""
  local run_id
  run_id=$(date +%s)
  local serial=""
  local epoch=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --results-dir)
        results_dir="$2"
        shift 2
        ;;
      --output)
        output_file="$2"
        shift 2
        ;;
      --run-id)
        run_id="$2"
        shift 2
        ;;
      --serial)
        serial="$2"
        shift 2
        ;;
      --epoch)
        epoch="$2"
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
  if [ -z "$results_dir" ] || [ -z "$output_file" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 1
  fi

  if [ ! -d "$results_dir" ]; then
    log_error "$COMPONENT" "Results directory not found: $results_dir"
    exit 1
  fi

  # Generate report
  local report
  report=$(generate_report "$results_dir" "$run_id" "$serial" "$epoch")

  # Write output
  echo "$report" > "$output_file"
  log_info "$COMPONENT" "Report written to $output_file"

  # Pretty print summary
  local total_archs total_suites successful_suites
  total_archs=$(echo "$report" | jq '.architectures | length')
  total_suites=$(echo "$report" | jq '[.architectures[].suites | length] | add')
  successful_suites=$(echo "$report" | jq '[.architectures[].suites[] | select(.reproducible == true)] | length')

  log_info "$COMPONENT" "Summary: $successful_suites/$total_suites suites reproducible across $total_archs architectures"
}

main "$@"
