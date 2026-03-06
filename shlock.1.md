% SHLOCK(1) shlock 1.0.1
% Gary Dean (Biksu Okusi)
% March 2026

# NAME

shlock - file-based locking utility with stale lock detection

# SYNOPSIS

**shlock** [*OPTIONS*] [*LOCKNAME*] **--** *COMMAND* [*ARGS*...]

# DESCRIPTION

**shlock** provides exclusive file-based locking using **flock**(1) for safe concurrent script execution. It prevents multiple instances of the same operation from running simultaneously and includes automatic stale lock detection for cleanup of locks left behind by crashed processes.

The lock is held using kernel-level **flock**(1) on a lock file, ensuring atomic lock acquisition and automatic release when the process terminates. A separate PID file tracks which process holds the lock for informational purposes and stale lock validation. The lock directory is automatically determined with fallback (see **FILES**).

## Key Features

- **Exclusive locking**: Only one instance of a locked operation can run at a time
- **Stale lock detection**: Automatically removes locks from dead processes
- **Flexible waiting modes**: Non-blocking, timeout-based, or indefinite waiting
- **PID tracking**: Identifies which process holds each lock
- **Lock stealing**: Administrative override to break held locks
- **Clean exit handling**: Automatic cleanup on normal exit or signal termination
- **Safe for automation**: Designed for cron jobs, systemd services, and CI/CD pipelines

# ARGUMENTS

*LOCKNAME*
:   Unique identifier for the lock (e.g., "backup", "deployment", "sync").
    If omitted, automatically derived from the basename of *COMMAND*.
    For example, `shlock -- /usr/local/bin/backup.sh` uses lockname "backup.sh".

*COMMAND*
:   Command to execute while holding the lock.

*ARGS*
:   Optional arguments passed to *COMMAND*.

**Important**: The `--` separator is required to clearly delineate lock options from the wrapped command and its arguments.

# OPTIONS

**-m**, **--max-age** *HOURS*
:   Maximum lock age in hours before considered stale (default: 24).
    If a lock file is older than this threshold and the owning process is no longer running, the lock is automatically removed.

**-w**, **--wait**
:   Wait indefinitely for lock to become available instead of failing immediately.
    The process will block until the lock can be acquired.

**-t**, **--timeout** *SECONDS*
:   Maximum time to wait for lock acquisition in seconds.
    If the lock cannot be acquired within this time, exits with code 1.
    Works independently; does not require **--wait**.

**-s**, **--steal**
:   Forcefully remove an existing lock. If the lock holder process is dead,
    the lock is removed automatically without prompting. If the holder is still
    running, displays a warning and prompts for confirmation before stealing.
    Exits with code 1 if the user declines.

**-h**, **--help**
:   Display help message and exit.

**-V**, **--version**
:   Display version information and exit.

**Note**: Short option bundling is supported. The argument-taking option must be last in the bundle. For example: **-wt 60** or **-wm 12**.

# EXIT STATUS

**0**
:   Command executed successfully.

**1**
:   Lock acquisition failed (lock held, timeout expired, no writable lock directory, or steal cancelled).

**2**
:   Invalid arguments (wrong options, missing required arguments).

**3**
:   Command failed (command's exit code was non-zero).

The distinction between exit codes 1 and 3 is important for automation: code 1 means "couldn't run because locked", code 3 means "ran but failed".

# EXAMPLES

## Basic Usage

Non-blocking lock (default):

```bash
shlock backup -- /usr/local/bin/backup.sh
```

Auto-generate lock name from command:

```bash
shlock -- /usr/local/bin/backup.sh
# Uses lockname "backup.sh"
```

## Waiting Modes

Wait indefinitely for lock:

```bash
shlock --wait deployment -- ./deploy.sh production
```

Wait up to 30 seconds:

```bash
shlock --timeout 30 sync -- rsync -av /src /dest
```

Using short options with timeout:

```bash
shlock -t 60 -m 6 backup -- /usr/local/bin/backup.sh
```

## Cron Integration

Prevent overlapping cron jobs:

```bash
# In /etc/cron.d/backup
0 2 * * * root shlock daily-backup -- /usr/local/bin/backup.sh

# If previous backup still running, this one exits immediately (code 1)
```

Handle cron job failures gracefully:

```bash
# Only alert if job ran but failed (exit 3), not if locked (exit 1)
0 2 * * * root shlock backup -- /usr/local/bin/backup.sh || \
  [ $? -eq 1 ] || mail -s "Backup failed" admin@example.com
```

## Systemd Service Integration

Prevent concurrent service executions:

```ini
# /etc/systemd/system/data-sync.service
[Unit]
Description=Data Synchronization

[Service]
Type=oneshot
ExecStart=/usr/local/bin/shlock data-sync -- /usr/local/bin/sync.sh
Restart=no

[Install]
WantedBy=multi-user.target
```

With timeout for service watchdog:

```ini
[Service]
Type=oneshot
ExecStart=/usr/local/bin/shlock --timeout 300 data-sync -- /usr/local/bin/sync.sh
TimeoutStartSec=310
```

## CI/CD Pipeline Integration

Serialize deployments to prevent conflicts:

```yaml
# GitLab CI example
deploy:
  script:
    - shlock --timeout 600 deploy-prod -- ./deploy.sh production
  only:
    - main
```

Ensure only one build per branch:

```bash
#!/bin/bash
# build.sh
BRANCH=$(git rev-parse --abbrev-ref HEAD)
shlock "build-$BRANCH" -- npm run build
```

## Stale Lock Handling

Custom stale lock threshold (12 hours):

```bash
shlock --max-age 12 critical -- /path/to/critical.sh
```

Very short-lived locks (1 hour threshold):

```bash
shlock -m 1 quick-task -- /path/to/task.sh
```

## Lock Stealing

Steal a lock from a dead or running process:

```bash
shlock --steal backup -- /usr/local/bin/backup.sh
```

Combine steal with short option bundling:

```bash
shlock -st 30 backup -- /usr/local/bin/backup.sh
```

If the lock holder is dead, the lock is removed automatically. If the holder is still running, **shlock** displays a warning and prompts for confirmation.

## Error Handling in Scripts

Distinguish between locked and failed:

```bash
#!/bin/bash
set -euo pipefail

if ! shlock myapp -- /path/to/command; then
  case $? in
    1) echo "Already running, skipping..." >&2; exit 0 ;;
    2) echo "Invalid arguments" >&2; exit 2 ;;
    3) echo "Command failed" >&2; exit 3 ;;
  esac
fi
```

Retry logic with timeout:

```bash
for i in {1..3}; do
  if shlock --timeout 10 myapp -- /path/to/command; then
    exit 0
  fi
  echo "Attempt $i failed, retrying..." >&2
  sleep 5
done
echo "All attempts failed" >&2
exit 1
```

# INTERNALS

## Locking Mechanism

**shlock** uses a multi-phase approach to lock acquisition:

1. **Argument parsing**: Resolves *LOCKNAME* from arguments or derives from *COMMAND* basename
2. **Lock directory determination**: Selects first writable directory from `/run/lock`, `/var/lock`, `/tmp/locks`
3. **Stale lock check**: Validates lock age and process liveness, removes stale locks
4. **Lock stealing** (if **--steal**): Removes existing lock, prompting only if holder is still running
5. **Lock acquisition**: Opens file descriptor 200 on **<LOCK_DIR>/<LOCKNAME>.lock** and attempts **flock**(1)
6. **PID tracking**: Writes current process ID to **<LOCK_DIR>/<LOCKNAME>.pid**
7. **Command execution**: Runs *COMMAND* while holding lock, captures exit code
8. **Cleanup**: EXIT trap removes PID file, **flock** releases when fd closes

## File Descriptor 200

**shlock** uses file descriptor 200 for lock file operations. This hardcoded descriptor is chosen to:

- Avoid conflicts with standard descriptors (0, 1, 2)
- Remain outside typical script descriptor ranges
- Provide consistent, predictable behavior

If your scripts use fd 200, this may cause conflicts. Consider modifying **shlock** or avoiding fd 200 in wrapped commands.

## Lock File Persistence

Lock files at **<LOCK_DIR>/<LOCKNAME>.lock** are NOT deleted after use. They persist (empty) for reuse on subsequent acquisitions. This is intentional and follows standard **flock**(1) behavior:

- Avoids race conditions during lock file recreation
- Reduces filesystem operations
- Enables atomic lock semantics

The PID file (**<LOCK_DIR>/<LOCKNAME>.pid**) is temporary and removed by the EXIT trap when the process terminates.

## Stale Lock Detection Algorithm

When **--max-age** threshold is exceeded:

1. Check if lock file exists and read its modification time
2. Calculate age in seconds
3. If age > **--max-age** (converted to seconds):
   - Read PID from **<LOCK_DIR>/<LOCKNAME>.pid**
   - Check if process is still running via `kill -0 <PID>`
   - If process dead: remove both **.lock** and **.pid** files (stale lock cleaned)
   - If process alive: exit with error code 1 (lock held by long-running process)

This ensures locks from crashed processes don't block future executions indefinitely, while still respecting legitimately long-running processes.

## Waiting Modes

Three distinct locking modes are supported:

**Non-blocking (default)**
:   Uses `flock -n` to fail immediately if lock is held. Exit code 1 if locked.

**Timeout mode (--timeout N)**
:   Uses `flock -w SECONDS` to wait up to specified time. Exit code 1 if timeout expires.

**Indefinite wait (--wait)**
:   Uses `flock` without flags to wait indefinitely until lock is available.

Priority order: **--timeout** > **--wait** > non-blocking. If both **--timeout** and **--wait** are specified, timeout takes precedence.

# INTEGRATION

## Systemd Timer Integration

Prevent timer-triggered services from overlapping:

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily backup timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Daily backup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/shlock backup -- /usr/local/bin/backup.sh
```

Enable with:

```bash
systemctl enable --now backup.timer
```

## Cron Best Practices

Always use explicit lock names for clarity:

```bash
# Good: explicit lock name
0 2 * * * shlock daily-backup -- /usr/local/bin/backup.sh

# Also good: auto-generated from command
0 2 * * * shlock -- /usr/local/bin/backup.sh
```

Use timeout to prevent infinite waits in cron:

```bash
# Wait max 5 minutes, then fail
*/15 * * * * shlock --timeout 300 sync -- /usr/local/bin/sync.sh
```

## CI/CD Best Practices

Use branch-specific locks to allow parallel builds:

```bash
LOCK="deploy-$(git rev-parse --abbrev-ref HEAD)"
shlock --timeout 900 "$LOCK" -- ./deploy.sh
```

Combine with deployment gates:

```yaml
deploy:
  stage: deploy
  script:
    - shlock --timeout 600 deploy-prod -- ./deploy.sh production
  when: manual
  only:
    - main
```

# FILES

**<LOCK_DIR>/<LOCKNAME>.lock**
:   Lock file used for **flock**(1) operations. Persists (empty) after use for reuse.
    The location of <LOCK_DIR> is automatically determined (see Lock Directory Selection below).

**<LOCK_DIR>/<LOCKNAME>.pid**
:   PID file containing process ID of lock holder. Removed by EXIT trap.
    Used for informational error messages and stale lock validation.

## Lock Directory Selection

**shlock** automatically selects the first writable directory from this list:

**/run/lock/**
:   Standard Linux lock directory (tmpfs). World-writable with sticky bit set.
    Automatically managed by **systemd-tmpfiles**(8). Cleared on reboot.
    **This is the preferred location.**

**/var/lock/**
:   Traditional lock directory. May persist across reboots on some systems.
    Used as fallback if `/run/lock` is unavailable or not writable.

**/tmp/locks/**
:   Last resort directory. Automatically created if it doesn't exist.
    Usually cleared on reboot. Only used if both above directories are unavailable.

If none of these directories are writable, **shlock** exits with error code 1.

# NOTES

- Lock names should be unique within your system to prevent unintended conflicts.
- Lock directories on tmpfs are cleared on reboot, automatically removing all locks.
- Locks are automatically released when the process terminates (normal exit, signal, or crash).
- For very long-running commands, consider adjusting **--max-age** to prevent premature stale lock detection.
- PID reuse is possible but extremely rare; stale lock detection validates process identity.

# BUGS

No known bugs. Report issues at <https://github.com/Open-Technology-Foundation/bash-coding-standard/issues>.

# SEE ALSO

**flock**(1), **systemd-tmpfiles**(8), **flock**(2), **cron**(8), **systemd.service**(5), **systemd.timer**(5)

# AUTHOR

Gary Dean (Biksu Okusi) <https://garydean.id>

