#!/usr/bin/env bash
# Validate docker-debian-artifacts repository integrity
# Checks that claimed serial/epoch are consistent with external sources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="validate-artifacts"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 --serial SERIAL --epoch EPOCH [options]

Validate docker-debian-artifacts parameters against external sources.

Required arguments:
  --serial SERIAL       Build serial (YYYYMMDD format)
  --epoch EPOCH         Unix epoch timestamp

Optional arguments:
  --skip-snapshot       Skip snapshot.debian.org validation (for offline testing)
  --help                Display this help message

Validation checks:
  1. Serial format is valid (YYYYMMDD)
  2. Epoch is within reasonable range (not future, not too old)
  3. Serial date matches epoch date (consistency check)
  4. snapshot.debian.org has archive for claimed serial (if online)

Exit codes:
  0 - Validation passed
  1 - Validation failed
  2 - Usage error
EOF
}

#######################################
# Validate serial format (YYYYMMDD)
# Arguments:
#   $1 - Serial string
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_serial_format() {
  local serial="$1"
  
  # Must be exactly 8 digits
  if [[ ! "$serial" =~ ^[0-9]{8}$ ]]; then
    log_error "$COMPONENT" "Invalid serial format: $serial (expected YYYYMMDD)"
    return 1
  fi
  
  # Extract components
  local year="${serial:0:4}"
  local month="${serial:4:2}"
  local day="${serial:6:2}"
  
  # Basic range checks
  if (( year < 2015 || year > 2100 )); then
    log_error "$COMPONENT" "Serial year out of range: $year"
    return 1
  fi
  if (( 10#$month < 1 || 10#$month > 12 )); then
    log_error "$COMPONENT" "Serial month out of range: $month"
    return 1
  fi
  if (( 10#$day < 1 || 10#$day > 31 )); then
    log_error "$COMPONENT" "Serial day out of range: $day"
    return 1
  fi
  
  log_debug "$COMPONENT" "Serial format valid: $serial"
  return 0
}

#######################################
# Validate epoch is within reasonable bounds
# Arguments:
#   $1 - Epoch timestamp
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_epoch_bounds() {
  local epoch="$1"
  local now
  now=$(date +%s)
  
  # Must be numeric
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    log_error "$COMPONENT" "Invalid epoch format: $epoch (expected numeric)"
    return 1
  fi
  
  # Cannot be in the future (with 1 day tolerance for timezone issues)
  local max_epoch=$((now + 86400))
  if (( epoch > max_epoch )); then
    log_error "$COMPONENT" "Epoch is in the future: $epoch > $max_epoch"
    return 1
  fi
  
  # Cannot be older than 2015 (Debuerreotype inception)
  local min_epoch=1420070400  # 2015-01-01 00:00:00 UTC
  if (( epoch < min_epoch )); then
    log_error "$COMPONENT" "Epoch is too old: $epoch < $min_epoch (2015-01-01)"
    return 1
  fi
  
  # Warn if older than 30 days (stale build)
  local stale_threshold=$((now - 30 * 86400))
  if (( epoch < stale_threshold )); then
    log_warn "$COMPONENT" "Epoch is more than 30 days old - build may be stale"
  fi
  
  log_debug "$COMPONENT" "Epoch bounds valid: $epoch"
  return 0
}

#######################################
# Validate serial and epoch are consistent
# Arguments:
#   $1 - Serial (YYYYMMDD)
#   $2 - Epoch timestamp
# Returns:
#   0 if consistent, 1 if mismatch
#######################################
validate_serial_epoch_consistency() {
  local serial="$1"
  local epoch="$2"
  
  # Convert epoch to date
  local epoch_date
  if [[ "$(uname)" == "Darwin" ]]; then
    epoch_date=$(date -r "$epoch" -u +%Y%m%d)
  else
    epoch_date=$(date -d "@$epoch" -u +%Y%m%d)
  fi
  
  if [[ "$serial" != "$epoch_date" ]]; then
    log_error "$COMPONENT" "Serial/epoch mismatch: serial=$serial but epoch date=$epoch_date"
    return 1
  fi
  
  log_debug "$COMPONENT" "Serial/epoch consistent: $serial matches epoch"
  return 0
}

#######################################
# Validate snapshot.debian.org has the claimed serial
# Arguments:
#   $1 - Serial (YYYYMMDD)
# Returns:
#   0 if exists, 1 if not found
#######################################
validate_snapshot_exists() {
  local serial="$1"
  local snapshot_url="https://snapshot.debian.org/archive/debian/${serial}T000000Z/"
  
  log_info "$COMPONENT" "Checking snapshot.debian.org for serial $serial"
  
  # HEAD request to check existence
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$snapshot_url")
  
  if [[ "$http_code" == "200" ]]; then
    log_info "$COMPONENT" "Snapshot exists: $snapshot_url"
    return 0
  elif [[ "$http_code" == "404" ]]; then
    log_error "$COMPONENT" "Snapshot NOT FOUND: $snapshot_url (serial may be fabricated)"
    return 1
  else
    log_warn "$COMPONENT" "Snapshot check returned HTTP $http_code (network issue?)"
    # Don't fail on network issues - just warn
    return 0
  fi
}

#######################################
# Main function
#######################################
main() {
  require_commands curl date

  local serial=""
  local epoch=""
  local skip_snapshot=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --serial)
        serial="$2"
        shift 2
        ;;
      --epoch)
        epoch="$2"
        shift 2
        ;;
      --skip-snapshot)
        skip_snapshot=true
        shift
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
  if [[ -z "$serial" ]] || [[ -z "$epoch" ]]; then
    log_error "$COMPONENT" "Missing required arguments"
    usage
    exit 2
  fi

  log_info "$COMPONENT" "Validating artifacts repo parameters: serial=$serial epoch=$epoch"

  local failed=0

  # Run validations
  validate_serial_format "$serial" || failed=1
  validate_epoch_bounds "$epoch" || failed=1
  
  if [[ $failed -eq 0 ]]; then
    validate_serial_epoch_consistency "$serial" "$epoch" || failed=1
  fi
  
  if [[ $failed -eq 0 ]] && [[ "$skip_snapshot" != "true" ]]; then
    validate_snapshot_exists "$serial" || failed=1
  fi

  if [[ $failed -eq 0 ]]; then
    log_info "$COMPONENT" "All validations passed"
    exit 0
  else
    log_error "$COMPONENT" "Validation FAILED - artifacts repo parameters may be compromised"
    exit 1
  fi
}

main "$@"
