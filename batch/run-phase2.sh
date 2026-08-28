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
# On completion the staged output is installed into the analysis repo, replacing
# whatever was there, because read_and_merge_csvs() merges EVERY directory under
# data/split -- leaving runA in place while copying runB in would silently pool
# two different designs into one dataset.
#
# Overridable by env var:
#   CHUNKS (5)  REPS (2000)  SHARDS (16)  HEAP (2g)
#   NGRID (80,160,240,320,400,480)
#   ANALYSIS (../SelSWIDM-analysis)   INSTALL (1; set 0 to stage only)

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
ANALYSIS="${ANALYSIS:-$REPO/../SelSWIDM-analysis}"
INSTALL="${INSTALL:-1}"

ROOT="$REPO/batch-runs/$ARM"
STAGE="$ROOT/merged"
LOG="$ROOT/driver.log"
PIDF="$ROOT/driver.pid"
mkdir -p "$ROOT" "$STAGE"

# Two drivers writing the same staging directory would corrupt it. The guard has
# to live here rather than in phase2.sh, or launching run-phase2.sh directly
# leaves no record and the wrapper cheerfully starts a second copy on top.
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
    echo "$ARM is already running as pid $(cat "$PIDF") -- refusing to start a second driver" >&2
    exit 1
fi
echo $$ > "$PIDF"
trap 'rm -f "$PIDF"' EXIT

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

if [ "$INSTALL" != "1" ]; then
    say "INSTALL=0, staged only. To install by hand:"
    say "    cp -r $STAGE/* <SelSWIDM-analysis>/data/split/"
elif [ ! -d "$ANALYSIS" ]; then
    say "analysis repo not found at $ANALYSIS -- staged only. Install by hand:"
    say "    cp -r $STAGE/* <SelSWIDM-analysis>/data/split/"
else
    prev=$(cat "$ANALYSIS/data/split/.arm" 2>/dev/null || echo none)
    say "installing $ARM into $ANALYSIS/data/split (replacing: $prev)"
    rm -rf "$ANALYSIS/data/split"
    mkdir -p "$ANALYSIS/data/split"
    cp -r "$STAGE"/* "$ANALYSIS/data/split/"
    echo "$ARM" > "$ANALYSIS/data/split/.arm"
    # read_ss_data() short-circuits on these, so they would shadow the new data;
    # and the targets store has no dependency on them, so it would not notice.
    rm -f "$ANALYSIS"/data/*.csv
    rm -rf "$ANALYSIS/_targets"
    say "installed. cached merges and targets store cleared."
    say "next:  cd $ANALYSIS && Rscript run_targets.R"
fi
