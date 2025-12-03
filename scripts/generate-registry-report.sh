#!/usr/bin/env bash
# Combine per-architecture registry verification results into a single report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="registry-report"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") --results-dir DIR --output FILE [options]

Combine per-architecture registry verification results into a single report.

Required arguments:
  --results-dir DIR   Directory containing per-arch result JSON files
  --output FILE       Output JSON file

Optional arguments:
  --help              Display this help message

Input files expected:
  results-amd64.json, results-arm64.json, etc.
  OR registry-amd64/results-amd64.json (artifact directory structure)

Examples:
  $(basename "$0") --results-dir ./artifacts --output dashboard/data/registry-latest.json
EOF
}

#######################################
# Main function
#######################################
main() {
  require_commands jq

  local results_dir=""
  local output_file=""

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
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "$COMPONENT" "Unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$results_dir" ]; then
    log_error "$COMPONENT" "Missing required argument: --results-dir"
    usage
    exit 2
  fi

  if [ -z "$output_file" ]; then
    log_error "$COMPONENT" "Missing required argument: --output"
    usage
    exit 2
  fi

  if [ ! -d "$results_dir" ]; then
    log_error "$COMPONENT" "Results directory not found: $results_dir"
    exit 2
  fi

  timer_start "generate_report"

  # Find all result JSON files
  local result_files=()

  # Pattern 1: results-{arch}.json in results_dir
  for f in "$results_dir"/results-*.json; do
    [ -f "$f" ] && result_files+=("$f")
  done

  # Pattern 2: registry-{arch}/results-{arch}.json (GitHub Actions artifact structure)
  for d in "$results_dir"/registry-*/; do
    if [ -d "$d" ]; then
      for f in "$d"/*.json; do
        [ -f "$f" ] && result_files+=("$f")
      done
    fi
  done

  if [ ${#result_files[@]} -eq 0 ]; then
    log_error "$COMPONENT" "No result files found in $results_dir"
    exit 1
  fi

  log_info "$COMPONENT" "Found ${#result_files[@]} result file(s)"

  # Combine all results
  local all_results=()
  local total=0 matched=0 mismatched=0 errors=0
  local serial="" latest_timestamp=""
  local overall_status="pass"

  for result_file in "${result_files[@]}"; do
    log_debug "$COMPONENT" "Processing: $result_file"

    local arch_results arch_summary file_serial file_timestamp

    # Extract data from each file
    arch_results=$(jq '.results' "$result_file")
    arch_summary=$(jq '.summary' "$result_file")
    file_serial=$(jq -r '.serial // ""' "$result_file")
    file_timestamp=$(jq -r '.timestamp' "$result_file")
    file_status=$(jq -r '.status' "$result_file")

    # Track serial (should be same across all)
    if [ -n "$file_serial" ] && [ "$file_serial" != "null" ]; then
      serial="$file_serial"
    fi

    # Track latest timestamp
    if [ -z "$latest_timestamp" ] || [[ "$file_timestamp" > "$latest_timestamp" ]]; then
      latest_timestamp="$file_timestamp"
    fi

    # Accumulate results
    all_results+=("$arch_results")

    # Accumulate summary counts
    total=$((total + $(echo "$arch_summary" | jq '.total')))
    matched=$((matched + $(echo "$arch_summary" | jq '.matched')))
    mismatched=$((mismatched + $(echo "$arch_summary" | jq '.mismatched')))
    errors=$((errors + $(echo "$arch_summary" | jq '.errors')))

    # Track overall status
    if [ "$file_status" = "fail" ]; then
      overall_status="fail"
    fi
  done

  # Combine all result arrays into one
  local combined_results
  combined_results=$(printf '%s\n' "${all_results[@]}" | jq -s 'add')

  # Get list of architectures
  local architectures
  architectures=$(echo "$combined_results" | jq -r '[.[].architecture] | unique | sort | join(",")')

  local duration
  duration=$(timer_end "generate_report")

  # Build final report
  local output
  output=$(jq -n \
    --arg timestamp "$(timestamp)" \
    --arg verification_timestamp "$latest_timestamp" \
    --arg serial "$serial" \
    --arg status "$overall_status" \
    --arg architectures "$architectures" \
    --argjson results "$combined_results" \
    --argjson total "$total" \
    --argjson matched "$matched" \
    --argjson mismatched "$mismatched" \
    --argjson errors "$errors" \
    --argjson duration "$duration" \
    '{
      timestamp: $timestamp,
      verification_timestamp: $verification_timestamp,
      serial: $serial,
      status: $status,
      architectures: ($architectures | split(",")),
      results: $results,
      summary: {
        total: $total,
        matched: $matched,
        mismatched: $mismatched,
        errors: $errors,
        match_rate: (if $total > 0 then ($matched / $total) else 0 end),
        generation_duration_seconds: $duration
      }
    }')

  # Create output directory if needed
  mkdir -p "$(dirname "$output_file")"

  # Write output
  echo "$output" > "$output_file"

  log_info "$COMPONENT" "Report generated: $output_file"
  log_info "$COMPONENT" "  Status: $overall_status"
  log_info "$COMPONENT" "  Matched: $matched/$total"
  log_info "$COMPONENT" "  Architectures: $architectures"

  # GitHub Actions integration
  github_summary "### Registry Verification Report"
  github_summary "- **Status**: $overall_status"
  github_summary "- **Serial**: $serial"
  github_summary "- **Matched**: $matched/$total ($(echo "scale=1; $matched * 100 / $total" | bc)%)"
  github_summary "- **Architectures**: $architectures"

  if [ "$mismatched" -gt 0 ]; then
    github_annotate "error" "Registry verification: $mismatched mismatch(es) detected"
  fi
}

main "$@"
