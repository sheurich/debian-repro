#!/usr/bin/env bash
# Compare verification results from multiple platforms and determine consensus

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="compare-platforms"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Compare verification results from multiple platforms and determine consensus.

Options:
  --results-dir DIR         Directory containing platform results (default: consensus-results)
  --output FILE             Output file for consensus report (default: consensus-report.json)
  --threshold N             Minimum platforms required for consensus (default: 2)
  --require-match           Require all platforms to match (strict consensus)
  --generate-evidence       Generate witness evidence for failures
  --help                    Display this help message

Examples:
  # Compare results with 2-of-N consensus
  $(basename "$0") --results-dir consensus-results

  # Strict mode: all platforms must match
  $(basename "$0") --results-dir consensus-results --require-match

  # Custom threshold
  $(basename "$0") --results-dir consensus-results --threshold 3
EOF
}

#######################################
# Extract results by architecture and suite from a platform report
# Arguments:
#   $1 - Platform report file (JSON)
#   $2 - Platform name
# Outputs:
#   JSON array of results with platform info
#######################################
extract_results() {
  local report_file="$1"
  local platform_name="$2"

  if [ ! -f "$report_file" ]; then
    log_debug "$COMPONENT" "Report file not found: $report_file"
    echo "[]"
    return
  fi

  jq --arg platform "$platform_name" '
    if .results then
      .results | map(
        . + {
          platform: $platform,
          timestamp: (.timestamp // parent.timestamp)
        }
      )
    else
      []
    end
  ' "$report_file"
}

#######################################
# Compare checksums across platforms for a specific suite/arch
# Arguments:
#   $1 - Architecture
#   $2 - Suite
#   $3... - Platform result files
# Outputs:
#   JSON comparison result
#######################################
compare_suite_arch() {
  local arch="$1"
  local suite="$2"
  shift 2
  local result_files=("$@")

  log_debug "$COMPONENT" "Comparing $suite/$arch across ${#result_files[@]} platforms"

  local platform_results="[]"
  local checksums=()
  local platforms=()

  # Extract results from each platform
  for result_file in "${result_files[@]}"; do
    local platform
    platform=$(basename "$result_file" | sed 's/-[0-9]\+.*\.json$//')

    # Extract checksum for this suite/arch
    local result
    result=$(jq -r \
      --arg arch "$arch" \
      --arg suite "$suite" \
      '.results[]? | select(.architecture == $arch and .suite == $suite) | .sha256' \
      "$result_file" 2>/dev/null)

    if [ -n "$result" ] && [ "$result" != "null" ]; then
      checksums+=("$result")
      platforms+=("$platform")

      # Add to platform_results array
      local platform_data
      platform_data=$(jq -n \
        --arg platform "$platform" \
        --arg checksum "$result" \
        '{platform: $platform, sha256: $checksum}')

      platform_results=$(echo "$platform_results" | jq --argjson item "$platform_data" '. + [$item]')
    fi
  done

  # Determine consensus
  local unique_checksums
  unique_checksums=$(printf '%s\n' "${checksums[@]}" | sort -u | wc -l | tr -d ' ')

  local consensus=false
  local consensus_checksum=""
  local agreement_count=0

  if [ "$unique_checksums" -eq 1 ]; then
    # All platforms agree
    consensus=true
    consensus_checksum="${checksums[0]}"
    agreement_count="${#checksums[@]}"
  elif [ "$unique_checksums" -gt 1 ]; then
    # Find majority
    local checksum_counts
    checksum_counts=$(printf '%s\n' "${checksums[@]}" | sort | uniq -c | sort -rn)

    local max_count
    max_count=$(echo "$checksum_counts" | head -1 | awk '{print $1}')

    if [ "$max_count" -ge 2 ]; then
      # At least 2 platforms agree
      consensus=true
      consensus_checksum=$(echo "$checksum_counts" | head -1 | awk '{print $2}')
      agreement_count="$max_count"
    fi
  fi

  # Build comparison result
  jq -n \
    --arg arch "$arch" \
    --arg suite "$suite" \
    --argjson consensus "$consensus" \
    --arg checksum "$consensus_checksum" \
    --argjson agreement "$agreement_count" \
    --argjson total "${#checksums[@]}" \
    --argjson platforms "$platform_results" \
    '{
      architecture: $arch,
      suite: $suite,
      consensus: $consensus,
      consensus_checksum: $checksum,
      platforms_agreeing: $agreement,
      platforms_total: $total,
      platform_results: $platforms,
      disagreement: ($total > 0 and $consensus == false)
    }'
}

#######################################
# Generate witness evidence for disagreements
# Arguments:
#   $1 - Comparison result (JSON)
#   $2 - Results directory
#   $3 - Output directory
#######################################
generate_witness_evidence() {
  local comparison="$1"
  local results_dir="$2"
  local output_dir="$3"

  local arch suite
  arch=$(echo "$comparison" | jq -r '.architecture')
  suite=$(echo "$comparison" | jq -r '.suite')

  local evidence_file="${output_dir}/evidence-${arch}-${suite}.json"

  log_info "$COMPONENT" "Generating witness evidence for $suite/$arch disagreement"

  # Collect detailed information from each platform
  local evidence="[]"

  local platforms
  platforms=$(echo "$comparison" | jq -r '.platform_results[].platform')

  for platform in $platforms; do
    # Find the platform report file
    local report_files=("${results_dir}/${platform}"-*.json)

    if [ -f "${report_files[0]}" ]; then
      local platform_detail
      platform_detail=$(jq \
        --arg arch "$arch" \
        --arg suite "$suite" \
        --arg platform "$platform" \
        '{
          platform: $platform,
          result: (.results[] | select(.architecture == $arch and .suite == $suite)),
          environment: .environment,
          timestamp: .timestamp,
          build_url: .platform.build_url
        }' "${report_files[0]}")

      evidence=$(echo "$evidence" | jq --argjson item "$platform_detail" '. + [$item]')
    fi
  done

  # Write evidence file
  jq -n \
    --arg arch "$arch" \
    --arg suite "$suite" \
    --arg timestamp "$(timestamp)" \
    --argjson evidence "$evidence" \
    '{
      architecture: $arch,
      suite: $suite,
      timestamp: $timestamp,
      type: "reproducibility-disagreement",
      platform_evidence: $evidence,
      investigation_required: true
    }' > "$evidence_file"

  log_info "$COMPONENT" "Witness evidence saved to: $evidence_file"
}

#######################################
# Main execution
#######################################
main() {
  local results_dir="consensus-results"
  local output_file="consensus-report.json"
  local threshold=2
  local require_match=false
  local generate_evidence=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --results-dir)
        results_dir="$2"
        shift 2
        ;;
      --output)
        output_file="$2"
        shift 2
        ;;
      --threshold)
        threshold="$2"
        shift 2
        ;;
      --require-match)
        require_match=true
        shift
        ;;
      --generate-evidence)
        generate_evidence=true
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "$COMPONENT" "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  # Validate
  if [ ! -d "$results_dir" ]; then
    log_error "$COMPONENT" "Results directory not found: $results_dir"
    exit 1
  fi

  # Find all platform result files
  local result_files=("${results_dir}"/*.json)

  if [ ${#result_files[@]} -eq 0 ] || [ ! -f "${result_files[0]}" ]; then
    log_error "$COMPONENT" "No result files found in $results_dir"
    exit 1
  fi

  log_info "$COMPONENT" "Comparing ${#result_files[@]} platform result(s)"

  # Extract all unique architecture/suite combinations
  local suite_arch_combinations
  suite_arch_combinations=$(jq -s '
    [.[] | .results[]? | {architecture, suite}] |
    unique |
    .[]
  ' "${result_files[@]}" | jq -s '.')

  log_info "$COMPONENT" "Found $(echo "$suite_arch_combinations" | jq 'length') suite/architecture combinations"

  # Compare each combination
  local comparisons="[]"
  local consensus_count=0
  local disagreement_count=0

  while IFS= read -r combination; do
    local arch suite
    arch=$(echo "$combination" | jq -r '.architecture')
    suite=$(echo "$combination" | jq -r '.suite')

    local comparison
    comparison=$(compare_suite_arch "$arch" "$suite" "${result_files[@]}")

    comparisons=$(echo "$comparisons" | jq --argjson item "$comparison" '. + [$item]')

    # Track consensus
    local has_consensus
    has_consensus=$(echo "$comparison" | jq -r '.consensus')

    if [ "$has_consensus" = "true" ]; then
      ((consensus_count++))
      log_info "$COMPONENT" "✅ Consensus: $suite/$arch"
    else
      ((disagreement_count++))
      log_warn "$COMPONENT" "❌ Disagreement: $suite/$arch"

      # Generate evidence if requested
      if [ "$generate_evidence" = "true" ]; then
        mkdir -p "$(dirname "$output_file")/evidence"
        generate_witness_evidence "$comparison" "$results_dir" "$(dirname "$output_file")/evidence"
      fi
    fi
  done < <(echo "$suite_arch_combinations" | jq -c '.[]')

  # Determine overall consensus
  local total_combinations
  total_combinations=$(echo "$comparisons" | jq 'length')

  local overall_consensus=false
  if [ "$require_match" = "true" ]; then
    # Strict mode: all must match
    [ "$disagreement_count" -eq 0 ] && overall_consensus=true
  else
    # Threshold mode: require minimum agreement
    [ "${#result_files[@]}" -ge "$threshold" ] && [ "$consensus_count" -gt 0 ] && overall_consensus=true
  fi

  # Generate final report
  local platforms_list
  platforms_list=$(printf '%s\n' "${result_files[@]}" | xargs -n1 basename | sed 's/-[0-9]\+.*\.json$//' | sort -u | jq -R . | jq -s .)

  jq -n \
    --arg timestamp "$(timestamp)" \
    --argjson consensus "$overall_consensus" \
    --argjson threshold "$threshold" \
    --argjson total "$total_combinations" \
    --argjson agreed "$consensus_count" \
    --argjson disagreed "$disagreement_count" \
    --argjson platforms "$platforms_list" \
    --argjson comparisons "$comparisons" \
    '{
      timestamp: $timestamp,
      consensus: {
        achieved: $consensus,
        threshold: $threshold,
        require_all_match: ($threshold == -1)
      },
      summary: {
        total_combinations: $total,
        consensus_achieved: $agreed,
        disagreements: $disagreed,
        consensus_rate: (($agreed / $total * 100) | round / 100)
      },
      platforms: $platforms,
      comparisons: $comparisons
    }' > "$output_file"

  log_info "$COMPONENT" "Consensus report saved to: $output_file"

  # Summary
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "Consensus Report Summary"
  echo "═══════════════════════════════════════════════"
  echo "Platforms compared: ${#result_files[@]}"
  echo "Total combinations: $total_combinations"
  echo "Consensus achieved: $consensus_count"
  echo "Disagreements: $disagreement_count"
  echo ""

  if [ "$overall_consensus" = "true" ]; then
    echo "✅ Overall consensus: ACHIEVED"
    exit 0
  else
    echo "❌ Overall consensus: FAILED"
    echo ""
    echo "See $output_file for details"

    if [ "$generate_evidence" = "true" ]; then
      echo "Witness evidence: $(dirname "$output_file")/evidence/"
    fi

    exit 1
  fi
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  main "$@"
fi
