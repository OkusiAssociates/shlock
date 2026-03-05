#!/bin/bash
# Wait and timeout feature tests for shlock

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
  rm -f /run/lock/test_wait_*.lock /run/lock/test_wait_*.pid 2>/dev/null || true
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

assert_duration() {
  local -- msg=$1
  local -i min_seconds=$2
  local -i max_seconds=$3
  shift 3

  ((++TEST_COUNT))

  local -i start_time=$(date +%s)
  set +e
  "$@" >/dev/null 2>&1
  set -e
  local -i end_time=$(date +%s)
  local -i duration=$((end_time - start_time))

  if ((duration >= min_seconds && duration <= max_seconds)); then
    ((++TEST_PASSED))
    echo "  ✓ $msg (took ${duration}s, expected ${min_seconds}-${max_seconds}s)"
    return 0
  else
    echo "  ✗ $msg (took ${duration}s, expected ${min_seconds}-${max_seconds}s)"
    return 1
  fi
}

# Tests
echo "Test: Basic --wait functionality"
# Start a process holding lock for 2 seconds
"$LOCK_SCRIPT" test_wait_1 -- sleep 2 &
HOLDER_PID=$!
sleep 0.2

# Try to acquire with --wait (should succeed after ~2 seconds)
START_TIME=$(date +%s)
"$LOCK_SCRIPT" --wait test_wait_1 -- echo "acquired" >/dev/null &
WAITER_PID=$!

# Wait for holder to finish
wait "$HOLDER_PID" || true
# Wait for waiter to finish
wait "$WAITER_PID" || true
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

((++TEST_COUNT))
if ((DURATION >= 1 && DURATION <= 4)); then
  ((++TEST_PASSED))
  echo "  ✓ --wait blocks and acquires lock after holder releases (${DURATION}s)"
else
  echo "  ✗ Expected duration 1-4s, got ${DURATION}s"
fi

echo
echo "Test: --timeout with available lock"
assert_exit_code "--timeout succeeds when lock is available" 0 \
  "$LOCK_SCRIPT" --wait --timeout 5 test_wait_2 -- echo "test"

echo
echo "Test: --timeout expires when waiting"
# Start a process holding lock for 10 seconds
"$LOCK_SCRIPT" test_wait_3 -- sleep 10 &
HOLDER_PID=$!
sleep 0.2

# Try to acquire with 2 second timeout (should fail)
assert_duration "--timeout 2 fails after ~2 seconds" 1 4 \
  "$LOCK_SCRIPT" --wait --timeout 2 test_wait_3 -- echo "should timeout"

assert_exit_code "--timeout returns exit code 1 on timeout" 1 \
  "$LOCK_SCRIPT" --wait --timeout 1 test_wait_3 -- echo "should timeout"

kill -TERM "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

echo
echo "Test: --timeout works independently"
assert_exit_code "--timeout without --wait succeeds" 0 \
  "$LOCK_SCRIPT" --timeout 10 test_wait_4 -- echo "test"

echo
echo "Test: --timeout with invalid value"
assert_exit_code "Non-numeric timeout rejected" 2 \
  "$LOCK_SCRIPT" --wait --timeout abc test_wait_5 -- echo "test"

assert_exit_code "Empty timeout rejected" 2 \
  "$LOCK_SCRIPT" --wait --timeout "" test_wait_6 -- echo "test"

echo
echo "Test: --wait without timeout (indefinite wait)"
# Start holder for 1 second
"$LOCK_SCRIPT" test_wait_7 -- sleep 1 &
HOLDER_PID=$!
sleep 0.2

# Wait indefinitely (should succeed within 2 seconds)
assert_duration "--wait without timeout waits indefinitely" 0 3 \
  "$LOCK_SCRIPT" --wait test_wait_7 -- echo "acquired"

wait "$HOLDER_PID" 2>/dev/null || true

echo
echo "Test: Multiple waiters in sequence"
COUNTER_FILE="/tmp/test_wait_counter_$$"
echo "0" > "$COUNTER_FILE"

# Start first holder
"$LOCK_SCRIPT" test_wait_8 -- bash -c "echo 1 > $COUNTER_FILE; sleep 1" &
PID1=$!
sleep 0.2

# Start second waiter
"$LOCK_SCRIPT" --wait test_wait_8 -- bash -c "echo 2 > $COUNTER_FILE; sleep 0.5" &
PID2=$!
sleep 0.1

# Start third waiter
"$LOCK_SCRIPT" --wait test_wait_8 -- bash -c "echo 3 > $COUNTER_FILE" &
PID3=$!

# Wait for all to complete
wait "$PID1" "$PID2" "$PID3" 2>/dev/null || true

FINAL_VALUE=$(cat "$COUNTER_FILE")
((++TEST_COUNT))
if [[ "$FINAL_VALUE" == "3" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Multiple waiters execute in sequence"
else
  echo "  ✗ Expected final value 3, got $FINAL_VALUE"
fi
rm -f "$COUNTER_FILE"

echo
echo "Test: --wait with stale lock"
# Create a stale lock
touch /run/lock/test_wait_9.lock
echo "99999" > /run/lock/test_wait_9.pid
TIMESTAMP=$(date -d "@$(($(date +%s) - 90000))" '+%Y%m%d%H%M.%S')
touch -t "$TIMESTAMP" /run/lock/test_wait_9.lock 2>/dev/null || true

# Should acquire immediately after removing stale lock
assert_duration "--wait with stale lock doesn't actually wait" 0 2 \
  "$LOCK_SCRIPT" --wait test_wait_9 -- echo "acquired"

echo
echo "Test: Zero timeout"
"$LOCK_SCRIPT" test_wait_10 -- sleep 2 &
HOLDER_PID=$!
sleep 0.2

# flock -w 0 actually tries once and may succeed immediately if lock just became available
# So this test just ensures zero timeout is accepted
assert_duration "Zero timeout returns quickly" 0 2 \
  "$LOCK_SCRIPT" --wait --timeout 0 test_wait_10 -- echo "test"

kill -TERM "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

echo
echo "Test: Large timeout value"
assert_exit_code "Large timeout (999999) accepted" 0 \
  "$LOCK_SCRIPT" --wait --timeout 999999 test_wait_11 -- echo "test"

echo
echo "Test: --wait mode error messages"
"$LOCK_SCRIPT" test_wait_12 -- sleep 2 &
HOLDER_PID=$!
sleep 0.2

((++TEST_COUNT))
set +e
OUTPUT=$("$LOCK_SCRIPT" --wait --timeout 1 test_wait_12 -- echo "test" 2>&1)
set -e

if [[ "$OUTPUT" =~ "Timeout" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Timeout error message is informative"
else
  echo "  ✗ Expected timeout message in: $OUTPUT"
fi

kill -TERM "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true

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
