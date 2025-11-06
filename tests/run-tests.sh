#!/usr/bin/env bash
# Run all BATS tests

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if bats is installed
if ! command -v bats >/dev/null 2>&1; then
  echo "Error: bats not installed" >&2
  echo "Install with: npm install -g bats" >&2
  echo "Or: brew install bats-core (on macOS)" >&2
  exit 1
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running BATS tests..."
echo

# Run tests
if bats --formatter tap "$SCRIPT_DIR/unit" "$SCRIPT_DIR/integration"; then
  echo
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
