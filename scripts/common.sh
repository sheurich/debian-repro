#!/usr/bin/env bash
# Common utilities and logging functions for Debian reproducibility verification

# Check bash version (need 4.0+ for associative arrays)
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "Error: Bash 4.0 or higher required (found ${BASH_VERSION})" >&2
  echo "Install with: brew install bash (on macOS)" >&2
  exit 1
fi

set -Eeuo pipefail

# Enable debug mode if DEBUG=1
[ "${DEBUG:-0}" = "1" ] && set -x

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Associative array for timers
declare -A TIMERS

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
# shellcheck disable=SC2034  # Reserved for future use
readonly LOG_LEVEL_ERROR=3

# Current log level (default: INFO)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# JSON output mode
LOG_JSON=${LOG_JSON:-false}

#######################################
# Format timestamp in ISO 8601 format
# Outputs:
#   UTC timestamp string
#######################################
timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

#######################################
# Log message with level and component
# Arguments:
#   $1 - Log level (DEBUG|INFO|WARN|ERROR)
#   $2 - Component name
#   $3 - Message
# Outputs:
#   Formatted log message to stdout/stderr
#######################################
log() {
  local level="$1"
  local component="$2"
  local message="$3"
  local ts
  ts=$(timestamp)

  if [ "$LOG_JSON" = "true" ]; then
    # JSON format
    jq -n \
      --arg ts "$ts" \
      --arg level "$level" \
      --arg component "$component" \
      --arg msg "$message" \
      '{timestamp: $ts, level: $level, component: $component, message: $msg}'
  else
    # Human-readable format
    local color=""
    case "$level" in
      ERROR) color="$RED" ;;
      WARN)  color="$YELLOW" ;;
      INFO)  color="$GREEN" ;;
      DEBUG) color="$BLUE" ;;
    esac

    # All logs go to stderr to avoid mixing with data output (JSON, etc.)
    echo -e "${color}[${ts}] [${level}] [${component}] ${message}${NC}" >&2
  fi
}

#######################################
# Log debug message
#######################################
log_debug() {
  [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ] || return 0
  log "DEBUG" "$1" "$2"
}

#######################################
# Log info message
#######################################
log_info() {
  [ "$LOG_LEVEL" -le "$LOG_LEVEL_INFO" ] || return 0
  log "INFO" "$1" "$2"
}

#######################################
# Log warning message
#######################################
log_warn() {
  [ "$LOG_LEVEL" -le "$LOG_LEVEL_WARN" ] || return 0
  log "WARN" "$1" "$2"
}

#######################################
# Log error message
#######################################
log_error() {
  log "ERROR" "$1" "$2"
}

#######################################
# Start timer for operation
# Arguments:
#   $1 - Timer name
#######################################
timer_start() {
  local timer_name="$1"
  # Temporarily disable unbound variable check for array assignment
  set +u
  TIMERS[$timer_name]=$(date +%s)
  set -u
  log_debug "timer" "Started timer: $timer_name"
}

#######################################
# End timer and return elapsed seconds
# Arguments:
#   $1 - Timer name
# Outputs:
#   Elapsed seconds
#######################################
timer_end() {
  local timer_name="$1"
  local start_time=0

  # Temporarily disable unbound variable check for array access
  set +u
  if [[ -v TIMERS[$timer_name] ]]; then
    start_time="${TIMERS[$timer_name]}"
  fi
  set -u

  if [ "$start_time" -eq 0 ]; then
    log_warn "timer" "Timer '$timer_name' was not started"
    echo "0"
    return 1
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  log_debug "timer" "Timer '$timer_name' completed in ${duration}s"
  echo "$duration"
}

#######################################
# Check if command exists
# Arguments:
#   $1 - Command name
# Returns:
#   0 if exists, 1 otherwise
#######################################
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

#######################################
# Ensure required commands exist
# Arguments:
#   $@ - List of required commands
# Returns:
#   0 if all exist, exits with 1 otherwise
#######################################
require_commands() {
  local missing=()

  for cmd in "$@"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "dependency" "Missing required commands: ${missing[*]}"
    exit 1
  fi
}

#######################################
# Create GitHub Actions annotation
# Arguments:
#   $1 - Annotation type (notice|warning|error)
#   $2 - Message
# Outputs:
#   GitHub Actions annotation
#######################################
github_annotate() {
  local type="$1"
  local message="$2"

  # Only output if running in GitHub Actions
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::${type}::${message}"
  fi
}

#######################################
# Add content to GitHub Step Summary
# Arguments:
#   $1 - Markdown content
#######################################
github_summary() {
  local content="$1"

  # Only output if running in GitHub Actions
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$content" >> "$GITHUB_STEP_SUMMARY"
  fi
}

#######################################
# Set GitHub Actions output
# Arguments:
#   $1 - Output name
#   $2 - Output value
#######################################
github_output() {
  local name="$1"
  local value="$2"

  # Only output if running in GitHub Actions
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  fi
}
