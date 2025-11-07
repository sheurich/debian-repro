#!/usr/bin/env bash
# Generate CSV and JSON-LD exports from verification report JSON

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="exports"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --report FILE --output-dir DIR

Generate machine-readable exports (CSV, JSON-LD) from verification report.

Required arguments:
  --report FILE        Verification report JSON file
  --output-dir DIR     Output directory for exports

Optional arguments:
  --help               Display this help message

Outputs (in output-dir):
  - latest.csv         Verification matrix in CSV format
  - latest.jsonld      JSON-LD structured data with Schema.org vocabulary
  - history.csv        Historical data (if history.json exists)

Examples:
  $0 --report ./dashboard/data/latest.json --output-dir ./dashboard/data
EOF
}

#######################################
# Generate CSV export from JSON report
# Creates a flat table: arch,suite,reproducible,sha256,build_time
#######################################
generate_csv() {
  local report="$1"
  local output_file="$2"

  log_info "$COMPONENT" "Generating CSV export"

  # CSV header
  echo "architecture,suite,reproducible,sha256,build_time_seconds,timestamp,serial" > "$output_file"

  # Extract data using jq
  local timestamp serial
  timestamp=$(echo "$report" | jq -r '.timestamp')
  serial=$(echo "$report" | jq -r '.serial')

  # Iterate through architectures and suites
  echo "$report" | jq -r \
    --arg ts "$timestamp" \
    --arg serial "$serial" \
    '.architectures | to_entries[] |
     .key as $arch |
     .value.suites | to_entries[] |
     [$arch, .key, .value.reproducible, .value.sha256,
      (.value.build_time_seconds // 0), $ts, $serial] |
     @csv' >> "$output_file"

  local row_count
  row_count=$(wc -l < "$output_file" | tr -d ' ')
  log_info "$COMPONENT" "CSV export complete: $((row_count - 1)) rows"
}

#######################################
# Generate JSON-LD structured data
# Uses Schema.org vocabulary for semantic web
#######################################
generate_jsonld() {
  local report="$1"
  local output_file="$2"

  log_info "$COMPONENT" "Generating JSON-LD export"

  # Calculate statistics
  local total_suites reproducible_suites rate timestamp serial
  total_suites=$(echo "$report" | jq '[.architectures[].suites[] | length] | length')
  reproducible_suites=$(echo "$report" | jq '[.architectures[].suites[] | select(.reproducible == true)] | length')
  timestamp=$(echo "$report" | jq -r '.timestamp')
  serial=$(echo "$report" | jq -r '.serial')

  if [ "$total_suites" -eq 0 ]; then
    rate=0
  else
    rate=$(echo "scale=0; ($reproducible_suites * 100) / $total_suites" | bc)
  fi

  # Generate JSON-LD with Schema.org vocabulary
  jq -n \
    --argjson report "$report" \
    --arg rate "$rate" \
    --arg timestamp "$timestamp" \
    --arg serial "$serial" \
    --arg total "$total_suites" \
    --arg reproducible "$reproducible_suites" \
    '{
      "@context": "https://schema.org",
      "@graph": [
        {
          "@type": "Dataset",
          "@id": "https://sheurich.github.io/debian-repro/data/latest.jsonld",
          "name": "Debian Reproducibility Verification Data",
          "description": "Bit-for-bit verification results of official Debian Docker images using Debuerreotype",
          "url": "https://sheurich.github.io/debian-repro/",
          "license": "https://opensource.org/licenses/MIT",
          "version": $serial,
          "dateModified": $timestamp,
          "creator": {
            "@type": "Person",
            "name": "Shiloh Heurich",
            "email": "sheurich@fastly.com"
          },
          "distribution": [
            {
              "@type": "DataDownload",
              "encodingFormat": "application/json",
              "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.json",
              "name": "JSON Report"
            },
            {
              "@type": "DataDownload",
              "encodingFormat": "text/csv",
              "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.csv",
              "name": "CSV Export"
            },
            {
              "@type": "DataDownload",
              "encodingFormat": "application/ld+json",
              "contentUrl": "https://sheurich.github.io/debian-repro/data/latest.jsonld",
              "name": "JSON-LD Structured Data"
            }
          ],
          "temporalCoverage": $timestamp,
          "spatialCoverage": {
            "@type": "Place",
            "name": "Global"
          },
          "keywords": ["debian", "reproducible builds", "docker", "verification", "debuerreotype"],
          "variableMeasured": [
            {
              "@type": "PropertyValue",
              "name": "reproducibility_rate",
              "value": ($rate | tonumber),
              "unitText": "percent",
              "description": "Percentage of suites that were reproducible"
            },
            {
              "@type": "PropertyValue",
              "name": "total_suites",
              "value": ($total | tonumber),
              "description": "Total number of suite/architecture combinations verified"
            },
            {
              "@type": "PropertyValue",
              "name": "reproducible_suites",
              "value": ($reproducible | tonumber),
              "description": "Number of reproducible suite/architecture combinations"
            },
            {
              "@type": "PropertyValue",
              "name": "serial",
              "value": $serial,
              "description": "Build serial number (YYYYMMDD format)"
            }
          ],
          "measurementTechnique": "SHA256 checksum comparison of Docker image rootfs tarballs built with Debuerreotype using identical SOURCE_DATE_EPOCH timestamps",
          "about": {
            "@type": "Thing",
            "name": "Reproducible Builds",
            "url": "https://reproducible-builds.org/",
            "description": "A set of software development practices that create an independently-verifiable path from source to binary code"
          }
        },
        {
          "@type": "SoftwareApplication",
          "@id": "https://sheurich.github.io/debian-repro/",
          "name": "Debian Reproducibility Verification Dashboard",
          "applicationCategory": "DeveloperApplication",
          "operatingSystem": "Any",
          "softwareVersion": "2.0.0",
          "offers": {
            "@type": "Offer",
            "price": "0",
            "priceCurrency": "USD"
          },
          "codeRepository": "https://github.com/sheurich/debian-repro",
          "programmingLanguage": "JavaScript",
          "author": {
            "@type": "Person",
            "name": "Shiloh Heurich",
            "email": "sheurich@fastly.com"
          },
          "datePublished": "2025-01-01",
          "dateModified": $timestamp,
          "description": "Static dashboard for visualizing Debian Docker image reproducibility verification results",
          "keywords": ["dashboard", "visualization", "debian", "reproducible builds"]
        }
      ]
    }' > "$output_file"

  log_info "$COMPONENT" "JSON-LD export complete: $rate% reproducibility rate"
}

#######################################
# Generate historical CSV if history.json exists
#######################################
generate_history_csv() {
  local history_file="$1"
  local output_file="$2"

  if [ ! -f "$history_file" ]; then
    log_debug "$COMPONENT" "No history file, skipping history CSV"
    return
  fi

  log_info "$COMPONENT" "Generating history CSV"

  # CSV header
  echo "timestamp,serial,architecture,suite,reproducible,sha256,build_time_seconds" > "$output_file"

  # Extract historical data
  jq -r '.[] |
    .timestamp as $ts |
    .serial as $serial |
    .architectures | to_entries[] |
    .key as $arch |
    .value.suites | to_entries[] |
    [$ts, $serial, $arch, .key, .value.reproducible, .value.sha256, (.value.build_time_seconds // 0)] |
    @csv' "$history_file" >> "$output_file"

  local row_count
  row_count=$(wc -l < "$output_file" | tr -d ' ')
  log_info "$COMPONENT" "History CSV complete: $((row_count - 1)) rows"
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

  # Generate exports
  timer_start "generate_exports"

  generate_csv "$report" "$output_dir/latest.csv"
  generate_jsonld "$report" "$output_dir/latest.jsonld"

  # Generate history CSV if history.json exists in same directory
  local history_file
  history_file="$(dirname "$report_file")/history.json"
  if [ -f "$history_file" ]; then
    generate_history_csv "$history_file" "$output_dir/history.csv"
  fi

  local duration
  duration=$(timer_end "generate_exports")
  log_info "$COMPONENT" "All exports generated in ${duration}s"
}

main "$@"
