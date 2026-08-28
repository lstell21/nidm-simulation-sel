#!/usr/bin/env bash
#
# Chunked, resumable driver for a Phase 2 batch.
#
# Why chunks: run-batch.sh has no resume, so a machine restart at hour 50 of a
# 60-hour run loses the whole thing. This box auto-restarts for Windows updates
# outside active hours and is shared with other users, so that is a real
# prospect rather than a hypothetical. Splitting the same total sample into
# chunks caps the loss at one chunk.
#
# Why that is statistically free: the model draws from ThreadLocalRandom and is
# never seeded, so chunks are independent samples; and read_and_merge_csvs() in
# SelSWIDM-analysis merges every directory under data/split, reading N from each
# one's own config.properties. Five chunks of 2000 concatenate to exactly the
# same thing as one run of 10000.
#
# Resume: each finished chunk is marked with a .done file. Re-running this
# script skips them and picks up where it stopped. Safe to run repeatedly.
#
# Usage:
#   nohup ./batch/run-phase2.sh runA > /dev/null 2>&1 &
#   nohup ./batch/run-phase2.sh runB > /dev/null 2>&1 &
#
#   runA = omega ~ U[0,1]   runB = omega fixed at 0
#
# Overridable by env var:
#   CHUNKS (5)  REPS (2000)  SHARDS (16)  HEAP (2g)
#   NGRID (80,160,240,320,400,480)

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)

ARM="${1:-}"
case "$ARM" in
    runA) OMEGA_FLAG="--omega-random" ;;
    runB) OMEGA_FLAG="--omega 0" ;;
    *) echo "usage: $(basename "$0") <runA|runB>" >&2; exit 2 ;;
esac

CHUNKS="${CHUNKS:-5}"
REPS="${REPS:-2000}"
SHARDS="${SHARDS:-16}"
HEAP="${HEAP:-2g}"
NGRID="${NGRID:-80,160,240,320,400,480}"

ROOT="$REPO/batch-runs/$ARM"
STAGE="$ROOT/merged"
LOG="$ROOT/driver.log"
mkdir -p "$ROOT" "$STAGE"

say() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

say "=== $ARM: $CHUNKS chunks x $REPS reps, shards=$SHARDS heap=$HEAP ==="
say "    grid $NGRID"
say "    staging into $STAGE"

for i in $(seq 1 "$CHUNKS"); do
    OUT="$ROOT/c$i"

    if [ -f "$OUT/.done" ]; then
        say "chunk $i/$CHUNKS already complete, skipping"
        continue
    fi

    say "chunk $i/$CHUNKS starting"
    rm -rf "$OUT"

    if ! "$REPO/batch/run-batch.sh" \
            --reps "$REPS" --shards "$SHARDS" --heap "$HEAP" \
            --ngrid "$NGRID" $OMEGA_FLAG --no-centralities \
            --out "$OUT" >> "$LOG" 2>&1; then
        say "chunk $i FAILED (run-batch.sh returned non-zero)"
        say "re-run this script to resume from chunk $i"
        exit 1
    fi

    # Every shard must have written an exit code, and all must be 0. A shard
    # killed mid-flight leaves no exit.code at all, which is why we count files
    # rather than only inspecting the ones that exist.
    codes=$(find "$OUT/work" -name exit.code 2>/dev/null | wc -l)
    bad=$(cat "$OUT"/work/*/exit.code 2>/dev/null | grep -cv '^0$' || true)
    if [ "$codes" -eq 0 ] || [ "$bad" -ne 0 ]; then
        say "chunk $i INCOMPLETE: $codes exit codes present, $bad non-zero"
        say "re-run this script to redo chunk $i"
        exit 1
    fi

    # Shard names repeat across runs (n480-s1 every time), so prefix on copy or
    # the next chunk silently overwrites this one in data/split.
    n=0
    for d in "$OUT"/split/*/; do
        tgt="$STAGE/c$i-$(basename "$d")"
        # rm first: cp -r into an existing directory NESTS the copy inside it,
        # leaving the previous attempt's data at the top level where the merge
        # would read it. Only bites on resume, which is exactly when it matters.
        rm -rf "$tgt"
        cp -r "$d" "$tgt"
        n=$((n + 1))
    done

    sims=$(for f in "$OUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
               wc -l < "$f"; done | awk '{s += $1 - 1} END {print s}')
    touch "$OUT/.done"
    say "chunk $i done: $codes shards, $n dirs staged, $sims simulations"
done

total=$(for f in "$STAGE"/*/data/nunnerbuskens/simulation-summary.csv; do
            wc -l < "$f"; done | awk '{s += $1 - 1} END {print s}')
say "=== $ARM complete: $total simulations across $CHUNKS chunks ==="
say "    cp -r $STAGE/* <SelSWIDM-analysis>/data/split/"
