#!/usr/bin/env bash
# Generate shields.io badge JSON endpoints from verification reports

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="badges"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --report FILE --output-dir DIR

Generate shields.io badge JSON endpoints from verification report.

Required arguments:
  --report FILE        Verification report JSON file
  --output-dir DIR     Output directory for badge JSON files

Optional arguments:
  --help               Display this help message

Outputs (in output-dir):
  - build-status.json        Build status badge
  - reproducibility-rate.json Reproducibility rate badge
  - last-verified.json       Last verification date badge

Examples:
  $0 --report ./report.json --output-dir ./dashboard/badges
EOF
}

#######################################
# Generate build status badge
#######################################
generate_build_status_badge() {
  local report="$1"
  local output_dir="$2"

  # Check if any architecture failed
  local failed_count
  failed_count=$(echo "$report" | jq '[.architectures[] | select(.status == "failed")] | length')

  local color message
  if [ "$failed_count" -eq 0 ]; then
    color="brightgreen"
    message="passing"
  else
    color="red"
    message="failing"
  fi

  jq -n \
    --arg color "$color" \
    --arg msg "$message" \
    '{
      schemaVersion: 1,
      label: "build",
      message: $msg,
      color: $color
    }' > "$output_dir/build-status.json"

  log_info "$COMPONENT" "Generated build status badge: $message"
}

#######################################
# Generate reproducibility rate badge
#######################################
generate_reproducibility_badge() {
  local report="$1"
  local output_dir="$2"

  # Count total and reproducible suites
  local total_suites reproducible_suites rate

  total_suites=$(echo "$report" | jq '[.architectures[].suites[] | length] | length')
  reproducible_suites=$(echo "$report" | jq '[.architectures[].suites[] | select(.reproducible == true)] | length')

  if [ "$total_suites" -eq 0 ]; then
    rate="0"
  else
    rate=$(echo "scale=0; ($reproducible_suites * 100) / $total_suites" | bc)
  fi

  # Determine color based on rate
  local color
  if [ "$rate" -ge 95 ]; then
    color="brightgreen"
  elif [ "$rate" -ge 80 ]; then
    color="green"
  elif [ "$rate" -ge 60 ]; then
    color="yellowgreen"
  elif [ "$rate" -ge 40 ]; then
    color="yellow"
  elif [ "$rate" -ge 20 ]; then
    color="orange"
  else
    color="red"
  fi

  jq -n \
    --arg rate "${rate}%" \
    --arg color "$color" \
    '{
      schemaVersion: 1,
      label: "reproducibility",
      message: $rate,
      color: $color
    }' > "$output_dir/reproducibility-rate.json"

  log_info "$COMPONENT" "Generated reproducibility badge: $rate ($reproducible_suites/$total_suites)"
}

#######################################
# Generate last verified badge
#######################################
generate_last_verified_badge() {
  local report="$1"
  local output_dir="$2"

  # Extract timestamp and format as relative date
  local timestamp
  timestamp=$(echo "$report" | jq -r '.timestamp')

  # Convert to YYYY-MM-DD format
  local date_only
  date_only=$(echo "$timestamp" | cut -d'T' -f1)

  jq -n \
    --arg date "$date_only" \
    '{
      schemaVersion: 1,
      label: "last verified",
      message: $date,
      color: "blue"
    }' > "$output_dir/last-verified.json"

  log_info "$COMPONENT" "Generated last verified badge: $date_only"
}

#######################################
# Generate architecture-specific badges
#######################################
generate_arch_badges() {
  local report="$1"
  local output_dir="$2"

  # Get list of architectures
  local architectures
  architectures=$(echo "$report" | jq -r '.architectures | keys[]')

  for arch in $architectures; do
    local status
    status=$(echo "$report" | jq -r ".architectures.\"$arch\".status")

    local color message
    case "$status" in
      success)
        color="brightgreen"
        message="reproducible"
        ;;
      failed)
        color="red"
        message="not reproducible"
        ;;
      *)
        color="yellow"
        message="unknown"
        ;;
    esac

    jq -n \
      --arg arch "$arch" \
      --arg msg "$message" \
      --arg color "$color" \
      '{
        schemaVersion: 1,
        label: $arch,
        message: $msg,
        color: $color
      }' > "$output_dir/arch-${arch}.json"

    log_debug "$COMPONENT" "Generated badge for $arch: $message"
  done
}

#######################################
# Main function
#######################################
main() {
  require_commands jq bc

  local report_file=""
  local output_dir=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --report)
        report_file="$2"
        shift 2
        ;;
      --output-dir)
        output_dir="$2"
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
  if [ -z "$report_file" ] || [ -z "$output_dir" ]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 1
  fi

  if [ ! -f "$report_file" ]; then
    log_error "$COMPONENT" "Report file not found: $report_file"
    exit 1
  fi

  # Create output directory
  mkdir -p "$output_dir"

  # Load report
  local report
  report=$(cat "$report_file")

  # Generate all badges
  timer_start "generate_badges"

  generate_build_status_badge "$report" "$output_dir"
  generate_reproducibility_badge "$report" "$output_dir"
  generate_last_verified_badge "$report" "$output_dir"
  generate_arch_badges "$report" "$output_dir"

  local duration
  duration=$(timer_end "generate_badges")
  log_info "$COMPONENT" "All badges generated in ${duration}s"
}

main "$@"
