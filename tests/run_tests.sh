#!/bin/bash
# Test runner for shlock test suite
#
# Runs all test files and reports results

set -euo pipefail
shopt -s inherit_errexit

# Script metadata
SCRIPT_NAME=${0##*/}
readonly -- SCRIPT_NAME

# Directories
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly -- SCRIPT_DIR
readonly -- LOCK_SCRIPT="$SCRIPT_DIR/../shlock"

# Test state
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()

# Colors for output
readonly -- COLOR_GREEN='\033[0;32m'
readonly -- COLOR_RED='\033[0;31m'
readonly -- COLOR_YELLOW='\033[1;33m'
readonly -- COLOR_RESET='\033[0m'

# Messaging functions
info() { echo -e "${COLOR_GREEN}◉${COLOR_RESET} $*"; }
error() { echo -e "${COLOR_RED}✗${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}▲${COLOR_RESET} $*"; }
success() { echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*"; }

# Verify shlock exists
if [[ ! -x "$LOCK_SCRIPT" ]]; then
  error "shlock not found or not executable at: $LOCK_SCRIPT"
  exit 1
fi

# Run a single test file
run_test_file() {
  local -- test_file=$1
  local -- test_name=${test_file##*/}
  test_name=${test_name%.sh}

  info "Running: $test_name"

  if bash "$test_file"; then
    ((++TESTS_PASSED))
    success "$test_name passed"
  else
    ((++TESTS_FAILED))
    FAILED_TESTS+=("$test_name")
    error "$test_name failed"
  fi

  ((++TESTS_RUN))
}

# Main
main() {
  info "Starting lock.sh test suite"
  info "Lock script: $LOCK_SCRIPT"
  echo

  # Find and run all test files
  local -a test_files=()
  while IFS= read -r -d '' file; do
    test_files+=("$file")
  done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'test_*.sh' -type f -print0 | sort -z)

  if [[ ${#test_files[@]} -eq 0 ]]; then
    warn "No test files found"
    exit 1
  fi

  # Run each test file
  for test_file in "${test_files[@]}"; do
    run_test_file "$test_file"
    echo
  done

  # Print summary
  echo "================================================"
  echo "Test Summary"
  echo "================================================"
  echo "Total tests:  $TESTS_RUN"
  success "Passed:       $TESTS_PASSED"

  if ((TESTS_FAILED > 0)); then
    error "Failed:       $TESTS_FAILED"
    echo
    error "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
      echo "  - $test"
    done
    exit 1
  fi

  echo
  success "All tests passed!"
  exit 0
}

main "$@"

#fin
