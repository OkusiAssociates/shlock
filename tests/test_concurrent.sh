#!/bin/bash
# Concurrent lock acquisition tests for shlock

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
  rm -f /run/lock/test_concurrent_*.lock /run/lock/test_concurrent_*.pid 2>/dev/null || true
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

# Tests
echo "Test: Two processes cannot hold same lock simultaneously"
# Start first process with lock
"$LOCK_SCRIPT" test_concurrent_1 -- sleep 0.5 &
FIRST_PID=$!
sleep 0.1  # Give first process time to acquire lock

# Try to acquire same lock
((++TEST_COUNT))
set +e
"$LOCK_SCRIPT" test_concurrent_1 -- echo "should fail" 2>/dev/null
EXIT_CODE=$?
set -e

if ((EXIT_CODE == 1)); then
  ((++TEST_PASSED))
  echo "  ✓ Second process cannot acquire held lock"
else
  echo "  ✗ Second process should fail with exit code 1, got $EXIT_CODE"
fi

wait "$FIRST_PID" || true

echo
echo "Test: Lock is released after first process completes"
# First process acquires and releases
"$LOCK_SCRIPT" test_concurrent_2 -- echo "first" >/dev/null
# Second process should now succeed
assert_success "Lock can be acquired after first process releases" \
  "$LOCK_SCRIPT" test_concurrent_2 -- echo "second"

echo
echo "Test: Multiple sequential lock acquisitions"
for i in {1..5}; do
  ((++TEST_COUNT))
  if "$LOCK_SCRIPT" test_concurrent_3 -- echo "iteration $i" >/dev/null; then
    ((++TEST_PASSED))
  else
    echo "  ✗ Failed on iteration $i"
  fi
done
echo "  ✓ Five sequential lock acquisitions succeeded"

echo
echo "Test: Second process fails when lock is held (non-blocking)"
# Create a counter file
COUNTER_FILE="/tmp/lock_test_counter_$$"
echo "0" > "$COUNTER_FILE"

# Start first process holding lock for 1 second
"$LOCK_SCRIPT" test_concurrent_4 -- bash -c "echo 1 > $COUNTER_FILE; sleep 1" &
FIRST_PID=$!

sleep 0.2  # Let first process acquire lock

# Try to acquire same lock (should fail immediately)
((++TEST_COUNT))
set +e
"$LOCK_SCRIPT" test_concurrent_4 -- bash -c "echo 2 > $COUNTER_FILE" 2>/dev/null
SECOND_EXIT=$?
set -e

# Wait for first to complete
wait "$FIRST_PID" || true

# Check that second process failed to acquire lock
FINAL_VALUE=$(cat "$COUNTER_FILE")
if ((SECOND_EXIT == 1)) && [[ "$FINAL_VALUE" == "1" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Second process failed immediately when lock was held"
else
  echo "  ✗ Expected second process to fail with exit 1, got $SECOND_EXIT, counter=$FINAL_VALUE"
fi
rm -f "$COUNTER_FILE"

echo
echo "Test: Error message includes PID when lock is held"
"$LOCK_SCRIPT" test_concurrent_5 -- sleep 0.5 &
HOLDER_PID=$!
sleep 0.1

((++TEST_COUNT))
set +e
ERROR_OUTPUT=$("$LOCK_SCRIPT" test_concurrent_5 -- echo "test" 2>&1)
set -e

if [[ "$ERROR_OUTPUT" =~ PID ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Error message includes PID information"
else
  echo "  ✗ Error message should mention PID: $ERROR_OUTPUT"
fi

wait "$HOLDER_PID" || true

echo
echo "Test: Rapid lock acquisition attempts"
# Test that lock mechanism is robust under rapid requests
SUCCESS_COUNT=0
for i in {1..10}; do
  if "$LOCK_SCRIPT" test_concurrent_6 -- echo "rapid $i" >/dev/null 2>&1; then
    ((++SUCCESS_COUNT))
  fi
done

((++TEST_COUNT))
if ((SUCCESS_COUNT == 10)); then
  ((++TEST_PASSED))
  echo "  ✓ All 10 rapid sequential acquisitions succeeded"
else
  echo "  ✗ Expected 10 successes, got $SUCCESS_COUNT"
fi

echo
echo "Test: Different locks do not interfere"
# Start processes with different lock names
"$LOCK_SCRIPT" test_concurrent_7a -- sleep 0.3 &
PID_A=$!
"$LOCK_SCRIPT" test_concurrent_7b -- sleep 0.3 &
PID_B=$!

sleep 0.1

# Both should be holding their respective locks
((++TEST_COUNT))
if [[ -f /run/lock/test_concurrent_7a.lock ]] && [[ -f /run/lock/test_concurrent_7b.lock ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Different locks can be held simultaneously"
else
  echo "  ✗ Both lock files should exist simultaneously"
fi

wait "$PID_A" "$PID_B" || true

echo
echo "Test: Lock survives during long-running command"
OUTPUT_FILE="/tmp/lock_test_output_$$"
"$LOCK_SCRIPT" test_concurrent_8 -- bash -c 'for i in {1..5}; do sleep 0.1; echo $i; done' > "$OUTPUT_FILE" &
LONG_PID=$!

# Verify lock exists throughout execution
sleep 0.2
((++TEST_COUNT))
if [[ -f /run/lock/test_concurrent_8.lock ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Lock persists during command execution"
else
  echo "  ✗ Lock file should exist during execution"
fi

wait "$LONG_PID" || true

# Verify command completed successfully
((++TEST_COUNT))
if [[ $(wc -l < "$OUTPUT_FILE") -eq 5 ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Long-running command completed successfully"
else
  echo "  ✗ Command output incomplete"
fi
rm -f "$OUTPUT_FILE"

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
