#!/bin/bash
# Edge case and stress tests for shlock

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
  rm -f /run/lock/test_edge_*.lock /run/lock/test_edge_*.pid 2>/dev/null || true
  rm -f /tmp/test_edge_* 2>/dev/null || true
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

# Tests
echo "Test: Zero-duration command"
assert_exit_code "Command that completes instantly" 0 \
  "$LOCK_SCRIPT" test_edge_1 -- true

echo
echo "Test: Command that produces no output"
assert_exit_code "Silent command succeeds" 0 \
  "$LOCK_SCRIPT" test_edge_2 -- bash -c ':'

echo
echo "Test: Command that produces large output"
assert_exit_code "Command with large output succeeds" 0 \
  "$LOCK_SCRIPT" test_edge_3 -- bash -c 'for i in {1..1000}; do echo "line $i"; done'

echo
echo "Test: Command with stderr output"
OUTPUT_FILE="/tmp/test_edge_stderr_$$"
set +e
"$LOCK_SCRIPT" test_edge_4 -- bash -c 'echo "error" >&2; exit 0' 2>"$OUTPUT_FILE"
EXIT_CODE=$?
set -e

((++TEST_COUNT))
if ((EXIT_CODE == 0)) && grep -q "error" "$OUTPUT_FILE"; then
  ((++TEST_PASSED))
  echo "  ✓ Command stderr is preserved"
else
  echo "  ✗ Command stderr should be preserved"
fi
rm -f "$OUTPUT_FILE"

echo
echo "Test: Command with both stdout and stderr"
assert_exit_code "Command with mixed output succeeds" 0 \
  "$LOCK_SCRIPT" test_edge_5 -- bash -c 'echo "out"; echo "err" >&2'

echo
echo "Test: Command that creates files"
TEST_FILE="/tmp/test_edge_file_$$"
assert_exit_code "Command can create files" 0 \
  "$LOCK_SCRIPT" test_edge_6 -- bash -c "echo 'content' > $TEST_FILE"

((++TEST_COUNT))
if [[ -f "$TEST_FILE" ]] && [[ "$(cat "$TEST_FILE")" == "content" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Created file has expected content"
else
  echo "  ✗ File should be created with correct content"
fi
rm -f "$TEST_FILE"

echo
echo "Test: Command that reads from stdin"
assert_exit_code "Command with stdin input" 0 \
  bash -c 'echo "test input" | '"$LOCK_SCRIPT"' test_edge_7 -- grep -q "test"'

echo
echo "Test: Command with pipe"
assert_exit_code "Command in pipeline" 0 \
  "$LOCK_SCRIPT" test_edge_8 -- bash -c 'echo "hello world" | grep -q world'

echo
echo "Test: Command with redirection"
REDIR_FILE="/tmp/test_edge_redir_$$"
assert_exit_code "Command with output redirection" 0 \
  "$LOCK_SCRIPT" test_edge_9 -- bash -c "echo 'redirected' > $REDIR_FILE"

((++TEST_COUNT))
if [[ -f "$REDIR_FILE" ]] && [[ "$(cat "$REDIR_FILE")" == "redirected" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Redirected output written correctly"
else
  echo "  ✗ Redirection should work correctly"
fi
rm -f "$REDIR_FILE"

echo
echo "Test: Nested lock attempts (should fail)"
NESTED_SCRIPT="/tmp/test_edge_nested_$$"
cat > "$NESTED_SCRIPT" <<'EOF'
#!/bin/bash
LOCK_SCRIPT="$1"
# Try to acquire the same lock within a locked command
"$LOCK_SCRIPT" test_edge_nested -- echo "inner"
EOF
chmod +x "$NESTED_SCRIPT"

assert_exit_code "Nested lock attempt fails" 3 \
  "$LOCK_SCRIPT" test_edge_nested -- "$NESTED_SCRIPT" "$LOCK_SCRIPT"

rm -f "$NESTED_SCRIPT"

echo
echo "Test: Lock with max-age of 1 hour"
assert_exit_code "Custom max-age (1 hour) works" 0 \
  "$LOCK_SCRIPT" --max-age 1 test_edge_10 -- echo "test"

echo
echo "Test: Lock with max-age of 168 hours (1 week)"
assert_exit_code "Large max-age (168 hours) works" 0 \
  "$LOCK_SCRIPT" --max-age 168 test_edge_11 -- echo "test"

echo
echo "Test: Command that changes directory"
ORIG_DIR=$(pwd)
assert_exit_code "Command that changes directory" 0 \
  "$LOCK_SCRIPT" test_edge_12 -- bash -c 'cd /tmp && pwd'

((++TEST_COUNT))
if [[ "$(pwd)" == "$ORIG_DIR" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Directory change in command doesn't affect caller"
else
  echo "  ✗ Directory should be unchanged after command"
fi

echo
echo "Test: Command with environment variables"
assert_exit_code "Command with custom environment variable" 0 \
  "$LOCK_SCRIPT" test_edge_13 -- bash -c 'export TEST_VAR=value && test "$TEST_VAR" = "value"'

echo
echo "Test: Command that spawns background process"
BG_FILE="/tmp/test_edge_bg_$$"
"$LOCK_SCRIPT" test_edge_14 -- bash -c "(sleep 0.2 && echo 'bg' > $BG_FILE) &" >/dev/null 2>&1
sleep 0.3

((++TEST_COUNT))
if [[ -f "$BG_FILE" ]] && [[ "$(cat "$BG_FILE")" == "bg" ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Background process spawned by command completes"
else
  echo "  ✗ Background process should complete"
fi
rm -f "$BG_FILE"

echo
echo "Test: Rapid sequential acquisitions (stress test)"
STRESS_COUNT=20
STRESS_SUCCESS=0
for i in $(seq 1 $STRESS_COUNT); do
  if "$LOCK_SCRIPT" test_edge_15 -- echo "iteration $i" >/dev/null 2>&1; then
    ((++STRESS_SUCCESS))
  fi
done

((++TEST_COUNT))
if ((STRESS_SUCCESS == STRESS_COUNT)); then
  ((++TEST_PASSED))
  echo "  ✓ $STRESS_COUNT rapid sequential acquisitions succeeded"
else
  echo "  ✗ Expected $STRESS_COUNT successes, got $STRESS_SUCCESS"
fi

echo
echo "Test: PID file accuracy"
"$LOCK_SCRIPT" test_edge_16 -- sleep 0.3 &
LOCK_HOLDER=$!
sleep 0.1

if [[ -f /run/lock/test_edge_16.pid ]]; then
  PID_FROM_FILE=$(cat /run/lock/test_edge_16.pid)
  ((++TEST_COUNT))

  # The PID in the file should be for a child of the lock holder
  if ps -p "$PID_FROM_FILE" >/dev/null 2>&1; then
    ((++TEST_PASSED))
    echo "  ✓ PID in pidfile is valid and running"
  else
    echo "  ✗ PID in pidfile should be running"
  fi
fi

wait "$LOCK_HOLDER" || true

echo
echo "Test: Lock name with numeric prefix"
assert_exit_code "Lock name starting with number" 0 \
  "$LOCK_SCRIPT" 123test_edge -- echo "test"

echo
echo "Test: Lock cleanup on normal exit"
"$LOCK_SCRIPT" test_edge_17 -- echo "test" >/dev/null
sleep 0.1

((++TEST_COUNT))
if [[ -f /run/lock/test_edge_17.lock ]] && [[ ! -f /run/lock/test_edge_17.pid ]]; then
  ((++TEST_PASSED))
  echo "  ✓ Lock file persists but PID file cleaned up after exit"
else
  echo "  ✗ Lock file should persist but PID file should be removed"
fi

echo
echo "Test: Command with exit trap"
assert_exit_code "Command with its own exit trap" 0 \
  "$LOCK_SCRIPT" test_edge_18 -- bash -c 'trap "echo trapped" EXIT; true'

echo
echo "Test: Command that uses file descriptor 200"
# This tests that our lock mechanism doesn't break if command uses same FD
assert_exit_code "Command using FD 200" 0 \
  "$LOCK_SCRIPT" test_edge_19 -- bash -c 'exec 200>/dev/null; echo "test" >&200'

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
