#!/bin/bash
#shellcheck disable=SC2317  # Unreachable code warnings for cleanup() and helpers - called via trap
# Lock stealing tests for shlock

set -euo pipefail
shopt -s inherit_errexit

# Setup
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly -- SCRIPT_DIR
readonly -- LOCK_SCRIPT="$SCRIPT_DIR/../shlock"
declare -i TEST_COUNT=0
declare -i TEST_PASSED=0

# Cleanup function
cleanup() {
  # Kill any background processes
  jobs -p | xargs -r kill 2>/dev/null || true
  # Clean up any locks created during tests
  rm -f /run/lock/test_steal_*.lock /run/lock/test_steal_*.pid 2>/dev/null || true
  rm -f /run/lock/echo.lock /run/lock/echo.pid 2>/dev/null || true
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

assert_exit_code() {
  local -- msg=$1
  local -i expected=$2
  shift 2
  ((++TEST_COUNT))

  local -i actual=0
  set +e
  "$@" >/dev/null 2>&1
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

assert_contains() {
  local -- msg=$1
  local -- pattern=$2
  shift 2
  ((++TEST_COUNT))

  local -- output
  set +e
  output=$("$@" 2>&1)
  set -e

  if [[ "$output" =~ $pattern ]]; then
    ((++TEST_PASSED))
    echo "  ✓ $msg"
    return 0
  else
    echo "  ✗ $msg (pattern '$pattern' not found in output)"
    echo "     Output: $output"
    return 1
  fi
}

# Helper: create a fake lock with a specified PID
create_fake_lock() {
  local -- lockname=$1
  local -i pid=$2
  touch "/run/lock/${lockname}.lock"
  echo "$pid" > "/run/lock/${lockname}.pid"
}

# Tests
echo "Test: Steal with no existing lock"
assert_exit_code "Steal with no lock proceeds normally" 0 \
  "$LOCK_SCRIPT" --steal test_steal_1 -- echo "test"

echo
echo "Test: Steal auto-removes dead process lock"
create_fake_lock test_steal_2 99999
assert_contains "Dead process lock removed with 'abandoned' message" "abandoned" \
  "$LOCK_SCRIPT" --steal test_steal_2 -- echo "test"

echo
echo "Test: Steal dead lock executes command"
create_fake_lock test_steal_3 99999
((++TEST_COUNT))
set +e
output=$("$LOCK_SCRIPT" --steal test_steal_3 -- echo "stolen-ok" 2>&1)
exit_code=$?
set -e
if ((exit_code == 0)) && [[ "$output" =~ stolen-ok ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Steal dead lock executes command and outputs result"
else
  echo "  ✗ Steal dead lock executes command (exit=$exit_code, output=$output)"
fi

echo
echo "Test: Steal running process - user declines"
"$LOCK_SCRIPT" test_steal_4 -- sleep 5 &
HOLDER_PID=$!
sleep 0.3
assert_exit_code "Steal declined returns exit code 1" 1 \
  bash -c 'echo "n" | "$1" --steal test_steal_4 -- echo "test"' _ "$LOCK_SCRIPT"
kill "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

echo
echo "Test: Steal running process - user confirms"
"$LOCK_SCRIPT" test_steal_5 -- sleep 5 &
HOLDER_PID=$!
sleep 0.3
assert_exit_code "Steal confirmed returns exit code 0" 0 \
  bash -c 'echo "y" | "$1" --steal test_steal_5 -- echo "test"' _ "$LOCK_SCRIPT"
kill "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

echo
echo "Test: After steal, PID file recreated"
create_fake_lock test_steal_6 99999
"$LOCK_SCRIPT" --steal test_steal_6 -- sleep 0.2 &
LOCK_PID=$!
sleep 0.1
((++TEST_COUNT))
if [[ -f /run/lock/test_steal_6.pid ]]; then
  pid_content=$(< /run/lock/test_steal_6.pid)
  if [[ "$pid_content" =~ ^[0-9]+$ ]]; then
    ((++TEST_PASSED))
    echo "  ✓ PID file recreated with valid numeric PID"
  else
    echo "  ✗ PID file contains invalid data: $pid_content"
  fi
else
  echo "  ✗ PID file not found after steal"
fi
wait "$LOCK_PID" 2>/dev/null || true

echo
echo "Test: Steal combined with --wait"
create_fake_lock test_steal_7 99999
assert_exit_code "Steal with --wait succeeds" 0 \
  "$LOCK_SCRIPT" --steal --wait test_steal_7 -- echo "test"

echo
echo "Test: Steal combined with --timeout"
create_fake_lock test_steal_8 99999
assert_exit_code "Steal with --timeout succeeds" 0 \
  "$LOCK_SCRIPT" --steal --timeout 5 test_steal_8 -- echo "test"

echo
echo "Test: Steal with auto-generated lockname"
create_fake_lock echo 99999
assert_exit_code "Steal with auto-generated lockname succeeds" 0 \
  "$LOCK_SCRIPT" --steal -- echo "test"

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
