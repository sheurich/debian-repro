#!/usr/bin/env bash
# Capture build environment fingerprint for reproducibility debugging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly COMPONENT="environment"

#######################################
# Display usage information
#######################################
usage() {
  cat <<EOF
Usage: $0 [--output FILE]

Capture build environment fingerprint including OS, Docker, QEMU versions, and Git SHA.

Optional arguments:
  --output FILE        Output file (default: stdout)
  --help               Display this help message

Output format:
  JSON object with environment details

Examples:
  $0
  $0 --output environment.json
EOF
}

#######################################
# Get Docker version
#######################################
get_docker_version() {
  if command_exists docker; then
    docker --version 2>/dev/null | head -n1 || echo "unknown"
  else
    echo "not installed"
  fi
}

#######################################
# Get QEMU version
#######################################
get_qemu_version() {
  if command_exists qemu-system-x86_64; then
    qemu-system-x86_64 --version 2>/dev/null | head -n1 || echo "unknown"
  elif command_exists qemu-img; then
    qemu-img --version 2>/dev/null | head -n1 || echo "unknown"
  else
    echo "not installed"
  fi
}

#######################################
# Get Git version and current SHA
#######################################
get_git_info() {
  if command_exists git; then
    local version
    version=$(git --version 2>/dev/null || echo "unknown")

    local sha="unknown"
    local branch="unknown"

    # Try to get current repo info
    if git rev-parse --git-dir >/dev/null 2>&1; then
      sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
      branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    fi

    jq -n \
      --arg version "$version" \
      --arg sha "$sha" \
      --arg branch "$branch" \
      '{version: $version, sha: $sha, branch: $branch}'
  else
    jq -n '{version: "not installed", sha: "unknown", branch: "unknown"}'
  fi
}

#######################################
# Get OS information
#######################################
get_os_info() {
  local os_name os_version kernel_version

  if [ -f /etc/os-release ]; then
    # Linux
    # shellcheck source=/dev/null
    source /etc/os-release
    os_name="${NAME:-unknown}"
    os_version="${VERSION:-unknown}"
  elif [ "$(uname)" = "Darwin" ]; then
    # macOS
    os_name="macOS"
    os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
  else
    os_name=$(uname -s || echo "unknown")
    os_version="unknown"
  fi

  kernel_version=$(uname -r || echo "unknown")

  jq -n \
    --arg name "$os_name" \
    --arg version "$os_version" \
    --arg kernel "$kernel_version" \
    --arg arch "$(uname -m)" \
    '{name: $name, version: $version, kernel: $kernel, arch: $arch}'
}

#######################################
# Get GitHub Actions environment info
#######################################
get_github_actions_info() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    jq -n \
      --arg runner_os "${RUNNER_OS:-unknown}" \
      --arg runner_name "${RUNNER_NAME:-unknown}" \
      --arg runner_arch "${RUNNER_ARCH:-unknown}" \
      --arg workflow "${GITHUB_WORKFLOW:-unknown}" \
      --arg run_id "${GITHUB_RUN_ID:-unknown}" \
      --arg run_number "${GITHUB_RUN_NUMBER:-unknown}" \
      '{runner_os: $runner_os, runner_name: $runner_name, runner_arch: $runner_arch, workflow: $workflow, run_id: $run_id, run_number: $run_number}'
  else
    echo "null"
  fi
}

#######################################
# Capture complete environment
#######################################
capture_environment() {
  log_info "$COMPONENT" "Capturing build environment"

  local docker_version qemu_version git_info os_info github_info timestamp

  docker_version=$(get_docker_version)
  qemu_version=$(get_qemu_version)
  git_info=$(get_git_info)
  os_info=$(get_os_info)
  github_info=$(get_github_actions_info)
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  jq -n \
    --arg ts "$timestamp" \
    --arg docker "$docker_version" \
    --arg qemu "$qemu_version" \
    --argjson git "$git_info" \
    --argjson os "$os_info" \
    --argjson github "$github_info" \
    '{
      timestamp: $ts,
      os: $os,
      docker: $docker,
      qemu: $qemu,
      git: $git,
      github_actions: $github
    }'
}

#######################################
# Main function
#######################################
main() {
  require_commands jq

  local output_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
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
        exit 1
        ;;
    esac
  done

  # Capture environment
  local env_json
  env_json=$(capture_environment)

  # Output
  if [ -n "$output_file" ]; then
    echo "$env_json" > "$output_file"
    log_info "$COMPONENT" "Environment captured to $output_file"
  else
    echo "$env_json"
  fi
}

main "$@"
