#!/bin/bash
# Basic functionality tests for shlock

set -euo pipefail
shopt -s inherit_errexit

# Setup
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly -- SCRIPT_DIR
readonly -- LOCK_SCRIPT="$SCRIPT_DIR/../shlock"
readonly -- TEST_LOCK_DIR="/tmp/lock_tests_$$"
declare -i TEST_COUNT=0
declare -i TEST_PASSED=0

# Create test lock directory
mkdir -p "$TEST_LOCK_DIR"

# Cleanup function
cleanup() {
  rm -rf "$TEST_LOCK_DIR"
  # Clean up any locks created during tests
  rm -f /run/lock/test_*.lock /run/lock/test_*.pid 2>/dev/null || true
}
trap cleanup EXIT

# Test helpers
assert_success() {
  local -- msg=$1
  shift
  ((++TEST_COUNT))
  if "$@"; then
    ((++TEST_PASSED))
    echo "  ✓ $msg"
    return 0
  else
    echo "  ✗ $msg (expected success, got failure)"
    return 1
  fi
}

assert_failure() {
  local -- msg=$1
  shift
  ((++TEST_COUNT))
  if "$@"; then
    echo "  ✗ $msg (expected failure, got success)"
    return 1
  else
    ((++TEST_PASSED))
    echo "  ✓ $msg"
    return 0
  fi
}

assert_exit_code() {
  local -- msg=$1
  local -i expected=$2
  shift 2
  ((++TEST_COUNT))

  local -i actual=0
  set +e
  "$@"
  actual=$?
  set -e

  if ((actual == expected)); then
    ((++TEST_PASSED))
    echo "  ✓ $msg (exit code: $actual)"
    return 0
  else
    echo "  ✗ $msg (expected exit code $expected, got $actual)"
    return 1
  fi
}

# Tests
echo "Test: Basic command execution"
assert_success "Execute simple command with lock" \
  "$LOCK_SCRIPT" test_basic_1 -- echo "test"

echo
echo "Test: Command with arguments"
assert_success "Execute command with multiple arguments" \
  "$LOCK_SCRIPT" test_basic_2 -- bash -c 'echo "arg1 arg2"'

echo
echo "Test: Lock file creation"
"$LOCK_SCRIPT" test_basic_3 -- sleep 0.1 &
LOCK_PID=$!
sleep 0.05
assert_success "Lock file exists while command runs" \
  test -f /run/lock/test_basic_3.lock
assert_success "PID file exists while command runs" \
  test -f /run/lock/test_basic_3.pid
wait "$LOCK_PID" || true

echo
echo "Test: Lock file cleanup after command completes"
"$LOCK_SCRIPT" test_basic_4 -- echo "test" >/dev/null
assert_success "Lock file persists after command completes (flock behavior)" \
  test -f /run/lock/test_basic_4.lock
assert_failure "PID file removed after command completes" \
  test -f /run/lock/test_basic_4.pid

echo
echo "Test: Exit code propagation"
assert_exit_code "Exit code 0 from successful command" 0 \
  "$LOCK_SCRIPT" test_basic_5 -- true
assert_exit_code "Exit code 3 from failed command" 3 \
  "$LOCK_SCRIPT" test_basic_6 -- false

echo
echo "Test: Help option"
assert_exit_code "Help with -h" 0 \
  "$LOCK_SCRIPT" -h
assert_exit_code "Help with --help" 0 \
  "$LOCK_SCRIPT" --help

echo
echo "Test: Invalid arguments"
assert_exit_code "Auto-generated lockname from command" 0 \
  "$LOCK_SCRIPT" -- echo "test"
assert_exit_code "Missing command" 2 \
  "$LOCK_SCRIPT" test_basic_7 --
assert_exit_code "Missing -- separator" 2 \
  "$LOCK_SCRIPT" test_basic_8 echo "test"
assert_exit_code "Unknown option" 2 \
  "$LOCK_SCRIPT" --invalid-option test_basic_9 -- echo "test"

echo
echo "Test: Short option bundling (BCS0805)"
assert_exit_code "Bundled -wt (wait + timeout)" 0 \
  "$LOCK_SCRIPT" -wt 5 test_basic_bundle_1 -- echo "test"

assert_exit_code "Bundled -ws (wait + steal)" 0 \
  "$LOCK_SCRIPT" -ws test_basic_bundle_2 -- echo "test"

assert_exit_code "Bundled -sm (steal + max-age)" 0 \
  "$LOCK_SCRIPT" -sm 12 test_basic_bundle_3 -- echo "test"

assert_exit_code "Triple bundle -swt (steal + wait + timeout)" 0 \
  "$LOCK_SCRIPT" -swt 5 test_basic_bundle_4 -- echo "test"

assert_exit_code "Invalid bundle -wz (unknown -z)" 2 \
  "$LOCK_SCRIPT" -wz test_basic_bundle_5 -- echo "test"

echo
echo "Test: PID file contents"
"$LOCK_SCRIPT" test_basic_10 -- sleep 0.2 &
LOCK_PID=$!
sleep 0.1
if [[ -f /run/lock/test_basic_10.pid ]]; then
  PID_CONTENT=$(cat /run/lock/test_basic_10.pid)
  ((++TEST_COUNT))
  if [[ "$PID_CONTENT" =~ ^[0-9]+$ ]]; then
    ((++TEST_PASSED))
    echo "  ✓ PID file contains valid PID"
  else
    echo "  ✗ PID file contains invalid data: $PID_CONTENT"
  fi
fi
wait "$LOCK_PID" || true

# Summary
echo
echo "================================================"
echo "Passed: $TEST_PASSED / $TEST_COUNT tests"
echo "================================================"

if ((TEST_PASSED == TEST_COUNT)); then
  exit 0
else
  exit 1
fi

#fin
