#!/bin/bash
# Stale lock detection and cleanup tests for shlock

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
  # Clean up any locks created during tests
  rm -f /run/lock/test_stale_*.lock /run/lock/test_stale_*.pid 2>/dev/null || true
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

# Create a stale lock file
create_stale_lock() {
  local -- lockname=$1
  local -i age_hours=${2:-25}  # Default 25 hours old

  local -- lockfile="/run/lock/${lockname}.lock"
  local -- pidfile="/run/lock/${lockname}.pid"

  # Create lock file
  touch "$lockfile"
  echo "99999" > "$pidfile"  # Non-existent PID

  # Make it old using touch
  local -i age_seconds=$((age_hours * 3600))
  local -- timestamp
  timestamp=$(date -d "@$(($(date +%s) - age_seconds))" '+%Y%m%d%H%M.%S')
  touch -t "$timestamp" "$lockfile" 2>/dev/null || {
    # Fallback if touch -t doesn't work
    touch "$lockfile"
    # Use Perl to set mtime if available
    if command -v perl >/dev/null 2>&1; then
      perl -e "utime(time - $age_seconds, time - $age_seconds, '$lockfile')"
    fi
  }
}

# Tests
echo "Test: Stale lock detection (default 24 hour threshold)"
create_stale_lock test_stale_1 25
assert_success "Stale lock (25 hours old) is removed and lock acquired" \
  "$LOCK_SCRIPT" test_stale_1 -- echo "test"

echo
echo "Test: Non-stale lock is not removed"
# Actually hold the lock with a background process
"$LOCK_SCRIPT" test_stale_2 -- sleep 2 &
HOLDER_PID=$!
sleep 0.2
assert_failure "Recent lock held by active process prevents lock acquisition" \
  "$LOCK_SCRIPT" test_stale_2 -- echo "test"
wait "$HOLDER_PID" 2>/dev/null || true
rm -f /run/lock/test_stale_2.lock /run/lock/test_stale_2.pid

echo
echo "Test: Custom max-age threshold"
create_stale_lock test_stale_3 13
assert_success "Lock older than custom threshold (12 hours) is removed" \
  "$LOCK_SCRIPT" --max-age 12 test_stale_3 -- echo "test"

echo
echo "Test: Custom max-age threshold - lock not stale"
# Use an active lock instead of just a stale file
"$LOCK_SCRIPT" --max-age 12 test_stale_4 -- sleep 2 &
HOLDER_PID=$!
sleep 0.2
assert_failure "Active lock younger than custom threshold is preserved" \
  "$LOCK_SCRIPT" --max-age 12 test_stale_4 -- echo "test"
wait "$HOLDER_PID" 2>/dev/null || true
rm -f /run/lock/test_stale_4.lock /run/lock/test_stale_4.pid

echo
echo "Test: Stale lock with missing PID file"
touch /run/lock/test_stale_5.lock
timestamp=$(date -d "@$(($(date +%s) - 90000))" '+%Y%m%d%H%M.%S')
touch -t "$timestamp" /run/lock/test_stale_5.lock 2>/dev/null || true
# No PID file created
assert_success "Stale lock without PID file is removed" \
  "$LOCK_SCRIPT" test_stale_5 -- echo "test"

echo
echo "Test: Stale lock with running process (simulated)"
# Create a lock with our own PID (which is definitely running)
create_stale_lock test_stale_6 25
echo "$$" > /run/lock/test_stale_6.pid
assert_failure "Stale lock with running process is not removed" \
  "$LOCK_SCRIPT" test_stale_6 -- echo "test"
rm -f /run/lock/test_stale_6.lock /run/lock/test_stale_6.pid

echo
echo "Test: Invalid --max-age values"
((++TEST_COUNT))
set +e
output=$("$LOCK_SCRIPT" --max-age abc test_stale_7 -- echo "test" 2>&1)
exit_code=$?
set -e
if ((exit_code == 2)) && [[ "$output" =~ "numeric" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Non-numeric max-age rejected"
else
  echo "  ✗ Non-numeric max-age should be rejected with exit code 2"
fi

((++TEST_COUNT))
set +e
output=$("$LOCK_SCRIPT" --max-age -- test_stale_8 -- echo "test" 2>&1)
exit_code=$?
set -e
if ((exit_code == 2)); then
  ((++TEST_PASSED))
  echo "  ✓ Missing max-age value rejected"
else
  echo "  ✗ Missing max-age value should be rejected with exit code 2"
fi

echo
echo "Test: Zero max-age"
create_stale_lock test_stale_9 0
sleep 1
assert_success "Lock with 0 max-age threshold removes any existing lock" \
  "$LOCK_SCRIPT" --max-age 0 test_stale_9 -- echo "test"

echo
echo "Test: Stale lock cleanup removes PID file"
create_stale_lock test_stale_10 30
"$LOCK_SCRIPT" test_stale_10 -- echo "test" >/dev/null 2>&1 || true
# Lock file persists (it gets truncated and recreated by exec 200>)
assert_success "Lock file persists after acquisition" \
  test -f /run/lock/test_stale_10.lock
# But PID file should be cleaned up
assert_failure "Stale PID file is removed" \
  test -f /run/lock/test_stale_10.pid

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
