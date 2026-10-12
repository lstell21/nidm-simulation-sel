#!/usr/bin/env bash
#
# Single entry point for a Phase 2 or Phase 3 batch (arms: runA, runB, p3;
# see run-chunked.sh).
#
#   ./batch/start.sh runA
#
# Starts the run detached if it is not already going, then follows progress in
# this window. Re-running the same command re-attaches rather than starting a
# second copy, and if the run died (reboot, someone shut the box down, Ctrl-C)
# it resumes from the last completed chunk.
#
# Detaching. A plain `nohup driver &` from this non-interactive script leaves
# the driver and its Java shards in the window's process group, so on Git Bash
# a Ctrl-C here killed every shard (exit 130) -- p3 chunk 4, 12 Oct 2026, 11 s
# after the display was interrupted. Git Bash has no setsid, so there the
# driver is started as a separate, hidden Windows process (powershell
# Start-Process); on Linux/macOS via setsid. Either way Ctrl-C or closing this
# window stops only the display. DETACH=0 restores the old attached launch,
# and the script then says so.
#
# Env: INTERVAL (300) seconds between refreshes; DETACH (1).
#
# The watch loop is kept to a handful of processes per refresh (builtins
# instead of cat/clear, a fork-light progress.sh): on this Windows host every
# process that exits stays pinned in kernel memory until reboot, and the old
# 60-second loop leaked ~30 GB a day -- enough to stall chunk 4 of every run.
# A long INTERVAL (e.g. INTERVAL=3600) keeps the leak negligible for a
# multi-day run in an open window.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)

ARM="${1:-}"
case "$ARM" in
    runA|runB|p3) ;;
    *) echo "usage: $(basename "$0") <runA|runB|p3>" >&2; exit 2 ;;
esac

ROOT="$REPO/batch-runs/$ARM"
PIDF="$ROOT/driver.pid"
LOG="$ROOT/driver.log"
INTERVAL="${INTERVAL:-300}"
DETACH="${DETACH:-1}"
# Set when the driver shares this window's process group. Re-attaching to a
# run started elsewhere cannot tell, so it assumes detached.
ATTACHED=0

mkdir -p "$ROOT"

alive() {
    local pid=
    [ -f "$PIDF" ] && read -r pid < "$PIDF" 2>/dev/null
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
finished() { grep -q "=== $ARM complete:" "$LOG" 2>/dev/null; }

if alive; then
    echo "$ARM is already running (pid $(cat "$PIDF")) -- attaching."
    sleep 2
elif finished; then
    echo "=== $ARM already finished ==="
    "$REPO/batch/progress.sh" "$ARM"
    grep "cp -r" "$LOG" | tail -1
    exit 0
else
    if [ -f "$LOG" ]; then
        echo "$ARM has an unfinished run -- resuming from the last completed chunk."
    fi
    DRIVER="$REPO/batch/run-chunked.sh"
    case "$DETACH:$(uname -s)" in
        1:MINGW*|1:MSYS*|1:CYGWIN*)
            # A separate Windows process with its own hidden console: outside
            # this window's process group, so neither Ctrl-C here nor closing
            # the window reaches the driver or its shards. The environment
            # (SHARDS, HEAP, ...) is inherited through powershell.
            powershell.exe -NoProfile -NonInteractive -Command \
                "Start-Process -WindowStyle Hidden -FilePath '$(cygpath -w /usr/bin/bash)' -ArgumentList '\"$DRIVER\" $ARM'"
            ;;
        1:*)
            if command -v setsid > /dev/null; then
                setsid nohup "$DRIVER" "$ARM" > /dev/null 2>&1 < /dev/null &
            else
                nohup "$DRIVER" "$ARM" > /dev/null 2>&1 < /dev/null &
                ATTACHED=1
            fi
            ;;
        *)
            nohup "$DRIVER" "$ARM" > /dev/null 2>&1 < /dev/null &
            ATTACHED=1
            ;;
    esac
    # run-chunked.sh writes its own pid; wait for it rather than recording the
    # launcher, so the guard works however the driver was launched.
    for _ in $(seq 1 20); do alive && break; sleep 1; done
    if ! alive; then
        echo "driver failed to start -- see $LOG" >&2
        exit 1
    fi
    echo "started $ARM (pid $(cat "$PIDF"))"
    if [ "$ATTACHED" = 1 ]; then
        echo "NOT detached: leave this window open and do not Ctrl-C it -- that kills the run."
        echo "watch from a second window with ./batch/progress.sh $ARM"
    else
        echo "detached: Ctrl-C or closing this window stops the display, not the run."
    fi
    sleep 3
fi

if [ "$ATTACHED" = 1 ]; then
    trap 'printf "\n\nstopped watching. The run was not detached, so this has most likely killed the shards too:\n  check ./batch/progress.sh %s (rc=130) and %s; resume with ./batch/start.sh %s\n" "$ARM" "$LOG" "$ARM"; exit 0' INT
else
    trap 'printf "\n\nstopped watching. %s continues in the background.\n  re-attach: ./batch/start.sh %s\n" "$ARM" "$ARM"; exit 0' INT
fi

while true; do
    printf '\033[H\033[2J'      # clear, without forking clear(1)
    "$REPO/batch/progress.sh" "$ARM"
    echo
    if [ "$ATTACHED" = 1 ]; then
        echo "refreshing every ${INTERVAL}s -- do NOT Ctrl-C or close this window: that kills the run"
    else
        echo "refreshing every ${INTERVAL}s -- Ctrl-C stops watching, not the run"
    fi

    if ! alive; then
        echo
        if finished; then
            echo "=== $ARM finished ==="
            grep "cp -r" "$LOG" | tail -1
        else
            echo "!!! the driver is no longer running but did not report completion."
            echo "    Most likely the machine restarted or the run was killed."
            echo "    Check $LOG, then re-run this script to resume."
        fi
        exit 0
    fi

    sleep "$INTERVAL"
done
