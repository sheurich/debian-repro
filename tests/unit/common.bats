#!/usr/bin/env bats
# Unit tests for scripts/common.sh

setup() {
  # Load common functions
  load '../test_helper'
  source "${PROJECT_ROOT}/scripts/common.sh"
}

@test "timestamp returns ISO 8601 format" {
  result=$(timestamp)
  # Check format: YYYY-MM-DDTHH:MM:SSZ
  [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "log_info outputs correct format" {
  LOG_JSON=false
  result=$(log_info "test-component" "test message" 2>&1)
  [[ $result =~ \[INFO\].*\[test-component\].*test\ message ]]
}

@test "log_error outputs to stderr" {
  LOG_JSON=false
  result=$(log_error "test-component" "error message" 2>&1)
  [[ $result =~ \[ERROR\].*\[test-component\].*error\ message ]]
}

@test "log_info with JSON output" {
  skip_if_missing "jq"
  export LOG_JSON=true
  result=$(log_info "test-component" "test message" 2>&1)
  # Validate JSON structure with jq
  echo "$result" | jq -e '.level == "INFO"' >/dev/null
  echo "$result" | jq -e '.component == "test-component"' >/dev/null
  echo "$result" | jq -e '.message == "test message"' >/dev/null
}

@test "timer_start and timer_end work correctly" {
  timer_start "test-timer"
  sleep 1
  duration=$(timer_end "test-timer")
  [ "$duration" -ge 1 ]
}

@test "timer_end returns 0 for non-existent timer" {
  run timer_end "nonexistent-timer"
  [ "$status" -eq 1 ]
  # Check that "0" appears in output (warning message also present)
  [[ "$output" =~ 0$ ]]
}

@test "command_exists returns 0 for existing command" {
  run command_exists "bash"
  [ "$status" -eq 0 ]
}

@test "command_exists returns 1 for non-existing command" {
  run command_exists "nonexistent-command-xyz"
  [ "$status" -eq 1 ]
}

@test "require_commands succeeds with all commands present" {
  run require_commands "bash" "cat" "echo"
  [ "$status" -eq 0 ]
}

@test "require_commands fails with missing command" {
  run require_commands "bash" "nonexistent-command-xyz"
  [ "$status" -eq 1 ]
  [[ $output =~ "Missing required commands" ]]
}

@test "github_annotate only outputs in GitHub Actions" {
  unset GITHUB_ACTIONS
  result=$(github_annotate "notice" "test message")
  [ -z "$result" ]
}

@test "github_annotate outputs in GitHub Actions environment" {
  GITHUB_ACTIONS=true
  result=$(github_annotate "notice" "test message")
  [ "$result" = "::notice::test message" ]
}

@test "github_summary only outputs when GITHUB_STEP_SUMMARY is set" {
  unset GITHUB_ACTIONS
  unset GITHUB_STEP_SUMMARY
  result=$(github_summary "test content")
  [ -z "$result" ]
}

@test "github_output only outputs when GITHUB_OUTPUT is set" {
  unset GITHUB_ACTIONS
  unset GITHUB_OUTPUT
  result=$(github_output "key" "value")
  [ -z "$result" ]
}
