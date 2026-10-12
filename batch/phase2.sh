#!/usr/bin/env bash
#
# Single entry point for a Phase 2 or Phase 3 batch (arms: runA, runB, p3;
# see run-phase2.sh).
#
#   ./batch/phase2.sh runA
#
# Starts the run detached if it is not already going, then follows progress in
# this window. Ctrl-C stops watching only -- the run keeps going. Re-running the
# same command re-attaches rather than starting a second copy, and if the run
# died (reboot, someone shut the box down) it resumes from the last completed
# chunk.
#
# Env: INTERVAL (300) seconds between refreshes.
#
# The watch loop is kept to a handful of processes per refresh (builtins
# instead of cat/clear, a fork-light progress.sh): on this Windows host every
# process that exits stays pinned in kernel memory until reboot, and the old
# 60-second loop leaked ~30 GB a day -- enough to stall chunk 4 of every run.
# Still, there is no need to leave it open for days: Ctrl-C after the first
# screen and check in with ./batch/progress.sh <arm> now and then.

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
    nohup "$REPO/batch/run-phase2.sh" "$ARM" > /dev/null 2>&1 &
    # run-phase2.sh writes its own pid; wait for it rather than recording the
    # nohup subshell, so the guard works however the driver was launched.
    for _ in 1 2 3 4 5 6 7 8 9 10; do alive && break; sleep 1; done
    if ! alive; then
        echo "driver failed to start -- see $LOG" >&2
        exit 1
    fi
    echo "started $ARM (pid $(cat "$PIDF"))"
    echo "safe to Ctrl-C: that stops the display, not the run."
    sleep 3
fi

trap 'printf "\n\nstopped watching. %s continues in the background.\n  re-attach: ./batch/phase2.sh %s\n" "$ARM" "$ARM"; exit 0' INT

while true; do
    printf '\033[H\033[2J'      # clear, without forking clear(1)
    "$REPO/batch/progress.sh" "$ARM"
    echo
    echo "refreshing every ${INTERVAL}s -- Ctrl-C stops watching, not the run"

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
