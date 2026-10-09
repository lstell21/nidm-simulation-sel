#!/usr/bin/env bash
#
# Chunked, resumable driver for a Phase 2 or Phase 3 batch.
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
# Resume: a chunk counts as complete only when its .done file exists, and .done
# is written last -- after run-batch.sh returned 0, every shard listed in
# shard-list.txt left an exit.code of 0, and the chunk's shard directories and
# provenance were staged. A chunk without .done is deleted and re-run from
# scratch. Re-running this script skips completed chunks. Safe to run repeatedly.
#
# Usage:
#   nohup ./batch/run-phase2.sh runA > /dev/null 2>&1 &
#   nohup ./batch/run-phase2.sh runB > /dev/null 2>&1 &
#   nohup ./batch/run-phase2.sh p3   > /dev/null 2>&1 &
#
#   runA = omega ~ U[0,1]   runB = omega fixed at 0
#   p3   = omega ~ U[0,1], gamma ~ U[0.1,0.2], nb.ep.structure=both
#
# On completion the staged output is installed into the analysis repo. For runA
# and runB it REPLACES data/split, because read_and_merge_csvs() merges EVERY
# directory under data/split -- leaving runA in place while copying runB in
# would silently pool two different designs into one dataset. p3 deletes
# nothing: it installs into data/phase3/split and refuses if that directory
# already holds anything.
#
# Each chunk's batch-info.txt, shard-list.txt and config.properties.source are
# kept as provenance/c<i>-*, next to the staged data.
#
# Overridable by env var:
#   CHUNKS (5)  REPS (2000)  SHARDS (16)  HEAP (2g)
#   NGRID (80,160,240,320,400,480)
#   ANALYSIS (../SelSWIDM-analysis)   INSTALL (1; set 0 to stage only)

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)

ARM="${1:-}"
case "$ARM" in
    runA) ARM_FLAGS="--omega-random" ;;
    runB) ARM_FLAGS="--omega 0" ;;
    p3)   ARM_FLAGS="--omega-random --gamma-min 0.1 --gamma-max 0.2 --ep-structure both" ;;
    *) echo "usage: $(basename "$0") <runA|runB|p3>" >&2; exit 2 ;;
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
PROV="$ROOT/provenance"
LOG="$ROOT/driver.log"
PIDF="$ROOT/driver.pid"
mkdir -p "$ROOT" "$STAGE" "$PROV"

case "$ARM" in
    p3) DEST_REL="data/phase3/split" ;;
    *)  DEST_REL="data/split" ;;
esac

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
say "    flags $ARM_FLAGS --no-centralities"
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
            --ngrid "$NGRID" $ARM_FLAGS --no-centralities \
            --out "$OUT" >> "$LOG" 2>&1; then
        say "chunk $i FAILED (run-batch.sh returned non-zero)"
        say "re-run this script to resume from chunk $i"
        exit 1
    fi

    # Every shard must have written an exit code, and all must be 0. A shard
    # killed mid-flight leaves no exit.code at all, which is why the count is
    # checked against shard-list.txt rather than only inspecting what exists.
    expected=$(grep -c . "$OUT/shard-list.txt" 2>/dev/null || echo 0)
    codes=$(find "$OUT/work" -name exit.code 2>/dev/null | wc -l)
    bad=$(cat "$OUT"/work/*/exit.code 2>/dev/null | grep -cv '^0$' || true)
    if [ "$codes" -eq 0 ] || [ "$codes" -ne "$expected" ] || [ "$bad" -ne 0 ]; then
        say "chunk $i INCOMPLETE: $codes of $expected exit codes present, $bad non-zero"
        say "re-run this script to redo chunk $i"
        exit 1
    fi

    # Shard names repeat across runs (n480-s1 every time), so prefix on copy or
    # the next chunk silently overwrites this one in data/split. Clear this
    # chunk's earlier staging first: cp -r into an existing directory NESTS the
    # copy inside it, and a redo with a different --shards would leave stale
    # shard directories behind. Only bites on resume, which is exactly when it
    # matters.
    rm -rf "$STAGE"/c$i-* "$PROV"/c$i-*
    n=0
    for d in "$OUT"/split/*/; do
        cp -r "$d" "$STAGE/c$i-$(basename "$d")"
        n=$((n + 1))
    done
    for f in batch-info.txt shard-list.txt config.properties.source; do
        cp "$OUT/$f" "$PROV/c$i-$f"
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
    say "    cp -r $STAGE/* <SelSWIDM-analysis>/$DEST_REL/"
elif [ ! -d "$ANALYSIS" ]; then
    say "analysis repo not found at $ANALYSIS -- staged only. Install by hand:"
    say "    cp -r $STAGE/* <SelSWIDM-analysis>/$DEST_REL/"
elif [ "$ARM" = "p3" ]; then
    # Phase 3 is a separate design with its own directory; it must never touch
    # Run A/B data or the caches built from them, so nothing is deleted here.
    DEST="$ANALYSIS/data/phase3"
    if [ -d "$DEST/split" ] && [ -n "$(ls -A "$DEST/split" 2>/dev/null)" ]; then
        say "NOT installed: $DEST/split exists and is not empty. Nothing was deleted."
        say "move it aside, then install by hand:"
        say "    cp -r $STAGE/* $DEST/split/ && mkdir -p $DEST/provenance && cp $PROV/* $DEST/provenance/"
        exit 1
    fi
    mkdir -p "$DEST/split" "$DEST/provenance"
    cp -r "$STAGE"/* "$DEST/split/"
    cp "$PROV"/* "$DEST/provenance/"
    echo "$ARM" > "$DEST/split/.arm"
    say "installed $ARM into $DEST/split (provenance in $DEST/provenance). nothing deleted."
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
