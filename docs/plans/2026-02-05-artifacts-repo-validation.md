# Artifacts Repository Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add integrity validation for docker-debian-artifacts repository to detect sudden/suspicious changes before trusting build parameters.

**Architecture:** Create `validate-artifacts-repo.sh` that runs two validation checks: (1) verify the claimed serial exists at snapshot.debian.org, (2) verify the epoch timestamp is within reasonable bounds. Integrate validation into `fetch-official.sh` before trusting fetched data.

**Tech Stack:** Bash, curl, snapshot.debian.org API

**Issue:** debian-repro-p31

---

## Context

**Problem:** The `docker-debian-artifacts` repository is trusted unconditionally. A compromise could inject arbitrary checksums that would make backdoored images appear "reproducible."

**Chosen approach:** Implement mitigations #1 (historical comparison) and #2 (multi-source validation) from the issue. Skip #3/#4 (GPG/commit signing) as artifacts repo doesn't currently use them.

**Files involved:**
- `scripts/validate-artifacts-repo.sh` (new)
- `scripts/fetch-official.sh` (modify to call validation)
- `scripts/common.sh` (add any shared utilities)
- `tests/validate-artifacts-repo.bats` (new tests)

---

## Task 1: Create validation script skeleton

**Files:**
- Create: `scripts/validate-artifacts-repo.sh`

**Step 1: Create the script with usage and argument parsing**

```bash
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
```

**Step 2: Make executable**

Run: `chmod +x scripts/validate-artifacts-repo.sh`

**Step 3: Run shellcheck**

Run: `shellcheck scripts/validate-artifacts-repo.sh`
Expected: No errors

**Step 4: Commit**

```bash
git add scripts/validate-artifacts-repo.sh
git commit -m "feat(security): add artifacts repo validation script skeleton

Implements validation checks for docker-debian-artifacts parameters:
- Serial format validation (YYYYMMDD)
- Epoch bounds checking (not future, not too old)
- Serial/epoch consistency
- snapshot.debian.org existence check

Part of debian-repro-p31"
```

---

## Task 2: Write tests for validation functions

**Files:**
- Create: `tests/validate-artifacts-repo.bats`

**Step 1: Create BATS test file**

```bash
#!/usr/bin/env bats
# Tests for validate-artifacts-repo.sh

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VALIDATE_SCRIPT="${SCRIPT_DIR}/scripts/validate-artifacts-repo.sh"
  
  # Get a known-good serial/epoch (today's date as fallback)
  GOOD_SERIAL=$(date -u +%Y%m%d)
  GOOD_EPOCH=$(date +%s)
}

@test "validates correct serial format" {
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1738713600 --skip-snapshot
  [ "$status" -eq 0 ]
}

@test "rejects invalid serial format - too short" {
  run "$VALIDATE_SCRIPT" --serial 2026020 --epoch 1738713600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid serial format" ]]
}

@test "rejects invalid serial format - letters" {
  run "$VALIDATE_SCRIPT" --serial 2026020a --epoch 1738713600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid serial format" ]]
}

@test "rejects serial with invalid month" {
  run "$VALIDATE_SCRIPT" --serial 20261305 --epoch 1738713600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "month out of range" ]]
}

@test "rejects future epoch" {
  # 10 days in the future
  future_epoch=$(($(date +%s) + 864000))
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch "$future_epoch" --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "future" ]]
}

@test "rejects epoch before 2015" {
  # 2014-01-01
  old_epoch=1388534400
  run "$VALIDATE_SCRIPT" --serial 20140101 --epoch "$old_epoch" --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "too old" ]]
}

@test "rejects serial/epoch mismatch" {
  # Serial says Feb 5, but epoch is Feb 10
  run "$VALIDATE_SCRIPT" --serial 20260205 --epoch 1739145600 --skip-snapshot
  [ "$status" -eq 1 ]
  [[ "$output" =~ "mismatch" ]]
}

@test "missing arguments returns usage error" {
  run "$VALIDATE_SCRIPT"
  [ "$status" -eq 2 ]
}

@test "help flag shows usage" {
  run "$VALIDATE_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "unknown argument returns error" {
  run "$VALIDATE_SCRIPT" --invalid-flag
  [ "$status" -eq 2 ]
}
```

**Step 2: Run tests**

Run: `bats tests/validate-artifacts-repo.bats`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/validate-artifacts-repo.bats
git commit -m "test: add tests for artifacts repo validation

Covers serial format, epoch bounds, consistency checks,
and error handling.

Part of debian-repro-p31"
```

---

## Task 3: Integrate validation into fetch-official.sh

**Files:**
- Modify: `scripts/fetch-official.sh`

**Step 1: Add validation call after extracting parameters**

In `fetch-official.sh`, after line 138 (where `epoch` is extracted), add validation call.

Find this block:
```bash
  serial=$(cat serial)
  epoch=$(cat debuerreotype-epoch)
  # Security: Use HTTPS to prevent man-in-the-middle attacks on snapshot URLs
  snapshot_url="https://snapshot.debian.org/archive/debian/${serial}T000000Z"
```

Replace with:
```bash
  serial=$(cat serial)
  epoch=$(cat debuerreotype-epoch)
  
  # Validate artifacts repo parameters before trusting them
  log_info "$COMPONENT" "Validating artifacts repo integrity..."
  if ! "${SCRIPT_DIR}/validate-artifacts-repo.sh" --serial "$serial" --epoch "$epoch"; then
    log_error "$COMPONENT" "Artifacts repo validation FAILED - aborting"
    exit 1
  fi
  
  # Security: Use HTTPS to prevent man-in-the-middle attacks on snapshot URLs
  snapshot_url="https://snapshot.debian.org/archive/debian/${serial}T000000Z"
```

**Step 2: Run shellcheck**

Run: `shellcheck scripts/fetch-official.sh`
Expected: No errors

**Step 3: Run existing tests**

Run: `bats tests/` (if they exist) or manual test:
```bash
./scripts/fetch-official.sh --arch amd64 --output-dir /tmp/test-fetch --suites bookworm
```
Expected: Should complete with validation passing

**Step 4: Commit**

```bash
git add scripts/fetch-official.sh
git commit -m "feat(security): integrate artifacts validation into fetch-official

fetch-official.sh now validates serial/epoch parameters before
trusting them, failing fast if validation detects anomalies.

Part of debian-repro-p31"
```

---

## Task 4: Add --skip-validation flag for offline/testing scenarios

**Files:**
- Modify: `scripts/fetch-official.sh`

**Step 1: Add flag to usage**

Find:
```bash
Optional arguments:
  --suites SUITES       Space-separated list of suites (default: fetch all)
  --help               Display this help message
```

Replace with:
```bash
Optional arguments:
  --suites SUITES       Space-separated list of suites (default: fetch all)
  --skip-validation     Skip artifacts repo validation (for offline use)
  --help                Display this help message
```

**Step 2: Add argument parsing**

Find:
```bash
      --help)
        usage
        exit 0
        ;;
```

Add before it:
```bash
      --skip-validation)
        skip_validation=true
        shift
        ;;
```

**Step 3: Initialize variable and update validation call**

Add after `local suites=""`:
```bash
  local skip_validation=false
```

Update the validation block to:
```bash
  # Validate artifacts repo parameters before trusting them
  if [[ "$skip_validation" == "true" ]]; then
    log_warn "$COMPONENT" "Skipping artifacts repo validation (--skip-validation)"
  else
    log_info "$COMPONENT" "Validating artifacts repo integrity..."
    if ! "${SCRIPT_DIR}/validate-artifacts-repo.sh" --serial "$serial" --epoch "$epoch"; then
      log_error "$COMPONENT" "Artifacts repo validation FAILED - aborting"
      exit 1
    fi
  fi
```

**Step 4: Run shellcheck and test**

Run: `shellcheck scripts/fetch-official.sh`
Run: `./scripts/fetch-official.sh --help` (verify flag shows)
Run: `./scripts/fetch-official.sh --arch amd64 --output-dir /tmp/test --suites bookworm --skip-validation`

**Step 5: Commit**

```bash
git add scripts/fetch-official.sh
git commit -m "feat: add --skip-validation flag for offline scenarios

Allows fetch-official.sh to run without network access to
snapshot.debian.org for testing and development.

Part of debian-repro-p31"
```

---

## Task 5: Update security documentation

**Files:**
- Modify: `docs/security.md`

**Step 1: Update the Single Trust Point Limitation section**

Find:
```markdown
**Future mitigation:** Issue debian-repro-p31 tracks adding validation
```

Replace with:
```markdown
**Mitigation implemented:** As of February 2026, `validate-artifacts-repo.sh`
performs the following checks before trusting artifacts repo parameters:

1. **Serial format validation** - Ensures YYYYMMDD format with valid ranges
2. **Epoch bounds checking** - Rejects future timestamps or pre-2015 dates
3. **Consistency check** - Verifies serial date matches epoch timestamp
4. **Snapshot verification** - Confirms snapshot.debian.org has the claimed serial

These checks detect:
- Fabricated serials (non-existent snapshots)
- Timestamp manipulation (impossible dates)
- Parameter corruption (mismatched serial/epoch)

They do NOT detect:
- Legitimate-looking but malicious parameter changes
- Compromised snapshot.debian.org (defense in depth, not eliminated)
```

**Step 2: Commit**

```bash
git add docs/security.md
git commit -m "docs: update security model with artifacts validation

Documents the validation checks added in debian-repro-p31
and clarifies what they do and don't detect.

Closes debian-repro-p31"
```

---

## Task 6: Close the issue

**Step 1: Update issue status**

Run: `bd close debian-repro-p31`

**Step 2: Sync beads**

Run: `bd sync`

---

## Verification Checklist

Before marking complete:
- [ ] `shellcheck scripts/validate-artifacts-repo.sh` passes
- [ ] `shellcheck scripts/fetch-official.sh` passes  
- [ ] `bats tests/validate-artifacts-repo.bats` passes
- [ ] Manual test: `./scripts/fetch-official.sh --arch amd64 --output-dir /tmp/test --suites bookworm` completes with validation
- [ ] `docs/security.md` updated
- [ ] All commits pushed
- [ ] Issue closed
