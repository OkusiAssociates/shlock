#!/bin/bash
# Error handling and edge case tests for shlock

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
  rm -f /run/lock/test_error_*.lock /run/lock/test_error_*.pid 2>/dev/null || true
  rm -f /run/lock/test-error*.lock /run/lock/test-error*.pid 2>/dev/null || true
  rm -f /run/lock/test.error*.lock /run/lock/test.error*.pid 2>/dev/null || true
  rm -f /run/lock/.hidden.lock /run/lock/.hidden.pid 2>/dev/null || true
  rm -f /run/lock/12345.lock /run/lock/12345.pid 2>/dev/null || true
}
trap cleanup EXIT

# Test helpers
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

# Tests
echo "Test: Command failure propagation"
assert_exit_code "Failed command returns exit code 3" 3 \
  "$LOCK_SCRIPT" test_error_1 -- bash -c 'exit 42'

assert_exit_code "Another failed command returns exit code 3" 3 \
  "$LOCK_SCRIPT" test_error_2 -- bash -c 'exit 1'

echo
echo "Test: Missing arguments"
assert_exit_code "No arguments returns exit code 2" 2 \
  "$LOCK_SCRIPT"

assert_exit_code "Only lockname without separator returns exit code 2" 2 \
  "$LOCK_SCRIPT" test_error_3

assert_exit_code "Lockname and separator but no command returns exit code 2" 2 \
  "$LOCK_SCRIPT" test_error_4 --

assert_exit_code "Empty lockname auto-generates from command" 0 \
  "$LOCK_SCRIPT" "" -- echo "test"

echo
echo "Test: Invalid options"
assert_exit_code "Unknown option returns exit code 2" 2 \
  "$LOCK_SCRIPT" --unknown test_error_5 -- echo "test"

assert_exit_code "Invalid short option returns exit code 2" 2 \
  "$LOCK_SCRIPT" -x test_error_6 -- echo "test"

echo
echo "Test: Invalid --max-age values"
assert_exit_code "Non-numeric max-age returns exit code 2" 2 \
  "$LOCK_SCRIPT" --max-age abc test_error_7 -- echo "test"

assert_exit_code "Empty max-age returns exit code 2" 2 \
  "$LOCK_SCRIPT" --max-age "" test_error_8 -- echo "test"

assert_exit_code "Negative max-age returns exit code 2" 2 \
  "$LOCK_SCRIPT" --max-age -5 test_error_9 -- echo "test"

assert_exit_code "Floating point max-age returns exit code 2" 2 \
  "$LOCK_SCRIPT" --max-age 12.5 test_error_10 -- echo "test"

echo
echo "Test: Lock already held"
# Start a process holding the lock
"$LOCK_SCRIPT" test_error_11 -- sleep 1 &
HOLDER_PID=$!
sleep 0.1

assert_exit_code "Attempting to acquire held lock returns exit code 1" 1 \
  "$LOCK_SCRIPT" test_error_11 -- echo "test"

wait "$HOLDER_PID" || true

echo
echo "Test: Error messages are informative"
"$LOCK_SCRIPT" test_error_12 -- sleep 0.5 &
HOLDER_PID=$!
sleep 0.1
assert_contains "Lock held error mentions lock name" "test_error_12" \
  "$LOCK_SCRIPT" test_error_12 -- echo "test"
wait "$HOLDER_PID" || true

assert_exit_code "Auto-generated lockname succeeds" 0 \
  "$LOCK_SCRIPT" -- echo "test"

assert_contains "Missing command error is clear" "COMMAND" \
  "$LOCK_SCRIPT" test_error_13 --

assert_contains "Invalid max-age error is clear" "numeric" \
  "$LOCK_SCRIPT" --max-age xyz test_error_14 -- echo "test"

echo
echo "Test: Command not found"
assert_exit_code "Non-existent command returns exit code 3" 3 \
  "$LOCK_SCRIPT" test_error_15 -- /nonexistent/command

echo
echo "Test: Command with insufficient permissions"
# Create a non-executable file
TEST_SCRIPT="/tmp/test_noexec_$$"
echo "#!/bin/bash" > "$TEST_SCRIPT"
echo "echo 'test'" >> "$TEST_SCRIPT"
chmod -x "$TEST_SCRIPT"

assert_exit_code "Non-executable command returns exit code 3" 3 \
  "$LOCK_SCRIPT" test_error_16 -- "$TEST_SCRIPT"

rm -f "$TEST_SCRIPT"

echo
echo "Test: Special characters in lock names"
# These should work
assert_exit_code "Lock name with underscore works" 0 \
  "$LOCK_SCRIPT" test_error_with_underscore -- echo "test"

assert_exit_code "Lock name with dash works" 0 \
  "$LOCK_SCRIPT" test-error-with-dash -- echo "test"

assert_exit_code "Lock name with dots works" 0 \
  "$LOCK_SCRIPT" test.error.dots -- echo "test"

echo
echo "Test: Very long lock name"
LONG_NAME="test_error_$(printf 'a%.0s' {1..200})"
assert_exit_code "Very long lock name works" 0 \
  "$LOCK_SCRIPT" "$LONG_NAME" -- echo "test"
rm -f "/run/lock/${LONG_NAME}.lock" "/run/lock/${LONG_NAME}.pid"

echo
echo "Test: LOCKNAME sanitization (invalid names rejected)"
assert_exit_code "Path traversal '../evil' rejected" 2 \
  "$LOCK_SCRIPT" '../evil' -- echo "test"

assert_exit_code "Slash in lockname 'foo/bar' rejected" 2 \
  "$LOCK_SCRIPT" 'foo/bar' -- echo "test"

assert_exit_code "Space in lockname 'foo bar' rejected" 2 \
  "$LOCK_SCRIPT" 'foo bar' -- echo "test"

assert_exit_code "At-sign in lockname 'foo@bar' rejected" 2 \
  "$LOCK_SCRIPT" 'foo@bar' -- echo "test"

assert_exit_code "Single dot '.' rejected (creates hidden files)" 2 \
  "$LOCK_SCRIPT" '.' -- echo "test"

assert_exit_code "Double dot '..' rejected (creates hidden files)" 2 \
  "$LOCK_SCRIPT" '..' -- echo "test"

assert_exit_code "Triple dot '...' rejected (creates hidden files)" 2 \
  "$LOCK_SCRIPT" '...' -- echo "test"

echo
echo "Test: LOCKNAME sanitization (valid names accepted)"
assert_exit_code "Dotfile lockname '.hidden' accepted" 0 \
  "$LOCK_SCRIPT" '.hidden' -- echo "test"

assert_exit_code "Numeric lockname '12345' accepted" 0 \
  "$LOCK_SCRIPT" '12345' -- echo "test"

echo
echo "Test: Command with complex arguments"
assert_exit_code "Command with quotes and spaces works" 0 \
  "$LOCK_SCRIPT" test_error_17 -- bash -c 'echo "test with spaces"'

assert_exit_code "Command with multiple arguments works" 0 \
  "$LOCK_SCRIPT" test_error_18 -- bash -c 'test "$1" = "arg1" && test "$2" = "arg2"' _ arg1 arg2

echo
echo "Test: Signal handling during lock hold"
# Start a process with lock
"$LOCK_SCRIPT" test_error_19 -- sleep 10 &
VICTIM_PID=$!
sleep 0.3

# Send SIGTERM and wait for it to die
kill -TERM "$VICTIM_PID" 2>/dev/null || true
wait "$VICTIM_PID" 2>/dev/null || true
sleep 0.3

# Clean up orphaned files - flock releases but files may remain
rm -f /run/lock/test_error_19.pid /run/lock/test_error_19.lock 2>/dev/null || true

# Lock should be acquirable after cleanup
assert_exit_code "Lock is acquirable after killed process cleanup" 0 \
  "$LOCK_SCRIPT" test_error_19 -- echo "test"

echo
echo "Test: Empty command"
assert_exit_code "Empty string as command fails" 3 \
  "$LOCK_SCRIPT" test_error_20 -- ""

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
