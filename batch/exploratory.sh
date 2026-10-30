#!/bin/sh
# Exploratory batch (S8, 30 Oct 2026): design diagnostics before the final re-run batches.
# Design and rules, fixed before any run: exploratory_criteria.md (Claude Science, 30 Oct 2026;
# selcor-handoff), section 2. Three arms, one after the other, from the rerun-fixes build:
#   EX-A  main design                     300 runs per N    --omega-random
#   EX-B  omega = 0                       150 runs per N    --omega 0
#   EX-P  paired (ep-structure both),     150 pairs per N   --omega-random --ep-structure both
#         gamma ~ U[0.1, 0.2]                               --gamma-min 0.1 --gamma-max 0.2
# All arms: default N grid (80, 160, 240, 320, 400, 480), --encounters 16, --no-centralities,
# round summaries on; everything else as committed in config.properties (alpha ~ U[0, 1],
# gamma ~ U[0.1, 0.4], sigma ~ U[1, 3], d ~ U[0, 1], s ~ Bernoulli(0.5), zeta = 10).
#
# Run from the root of a clean clone on branch rerun-fixes (Git Bash on Windows, or Linux):
#   mkdir -p batch-runs && nohup ./batch/exploratory.sh --shards 16 >> batch-runs/exploratory.log 2>&1 &
#   tail -f batch-runs/exploratory.log           (progress per shard: batch/progress.sh)
#
# What it does:
#   1. checks the clone: branch rerun-fixes, clean (untracked files count too);
#   2. takes the lock <out>.lock (mkdir is atomic; a second start stops at once);
#   3. builds with Maven and checks that target/classes/git.properties names HEAD, not dirty;
#   4. runs EX-A, EX-B, EX-P with run-batch.sh into <out>/<arm>/ (each run-batch.sh writes the
#      arm's batch-info.txt with git commit and dirty count; this script adds the arm line),
#      checks the number of runs and, for EX-P, that paired.start.identical is true in every
#      pair (criteria R4: anything less is a code error, so the script stops);
#   5. packs <out>/<arm>.tgz (split/, batch-info.txt, shard-list.txt, config.properties.source)
#      with <arm>.tgz.sha256.
#
# After an interruption (reboot, killed shell): an arm that finished (its .done marker) is not
# run again and a tarball that verifies is not packed again, so a new start resumes with the
# next arm. An arm that started but did not finish stops the script with a message: move that
# folder aside and start again (run-batch.sh cannot resume a batch). If the lock is left behind,
# the script says so; remove it only when no java process of this batch runs.
#
# Options:
#   --shards K   parallel JVMs per arm (default: number of cores - 1; at least 6, one per N)
#   --out DIR    output root (default <clone>/batch-runs/exploratory)
#   --reps R     runs per N in every arm instead of 300/150/150 (smoke tests only)
#   --ngrid L    N grid instead of the default (smoke tests only)
# Environment: MVN (mvn).

set -u

MVN=${MVN:-mvn}
SHARDS=""; OUT_ROOT=""; REPS_ALL=""; NGRID=""

say() { echo "[$(date '+%F %T')] $*"; }
die() { say "STOPPED: $*"; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --shards) SHARDS="$2"; shift 2 ;;
        --out)    OUT_ROOT="$2"; shift 2 ;;
        --reps)   REPS_ALL="$2"; shift 2 ;;
        --ngrid)  NGRID="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

if [ -z "$SHARDS" ]; then
    CORES=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
    SHARDS=$(( CORES - 1 ))
fi

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git clone; cd to the clone root first"
[ "$(cd "$TOP" && pwd -P)" = "$(pwd -P)" ] || die "run this from the root of the clone ($TOP)"
# POSIX form (/c/Users/... on Git Bash): run-batch.sh takes C:/Users/... for a relative --out
# and prefixes it with its working directory
REPO=$(pwd -P)
[ -f "$REPO/batch/run-batch.sh" ] || die "$REPO is not an nidm-simulation-sel clone"
OUT_ROOT=${OUT_ROOT:-$REPO/batch-runs/exploratory}
if command -v cygpath > /dev/null 2>&1; then OUT_ROOT=$(cygpath -u "$OUT_ROOT"); fi
case "$OUT_ROOT" in /*) ;; *) OUT_ROOT="$REPO/$OUT_ROOT" ;; esac
LOCK="$OUT_ROOT.lock"

say "=== exploratory batch EX-A, EX-B, EX-P: $SHARDS shards per arm ==="
say "clone  : $REPO"
say "output : $OUT_ROOT"
[ -n "$REPS_ALL$NGRID" ] && say "smoke settings: reps ${REPS_ALL:-as designed}, N grid ${NGRID:-default}"

# 1. clone
[ "$(git rev-parse --abbrev-ref HEAD)" = "rerun-fixes" ] \
    || die "the clone is on $(git rev-parse --abbrev-ref HEAD), not rerun-fixes"
[ -z "$(git status --porcelain)" ] || die "the clone is not clean (git status --short); untracked files count too"
say "clone ok: $(git rev-parse --short HEAD) on rerun-fixes, clean"

# 2. lock
mkdir -p "$(dirname "$OUT_ROOT")" || die "cannot create $(dirname "$OUT_ROOT")"
if ! mkdir "$LOCK" 2>/dev/null; then
    die "$LOCK exists: the batch is running already, or an earlier start was killed. Nothing started.
    If no java process of this batch runs (Task Manager, or ps -ef | grep java), remove the lock: rmdir $LOCK"
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
say "lock taken: $LOCK"

# 3. build
say "building with Maven"
"$MVN" -B -q package -DskipTests || die "Maven build failed"
[ -z "$(git status --porcelain)" ] || die "the clone is not clean after the build"
GP="$REPO/target/classes/git.properties"
grep -q "^git.commit.id=$(git rev-parse HEAD)" "$GP" || die "$GP does not name HEAD"
grep -q "^git.dirty=false" "$GP" || die "$GP says dirty"
say "build ok: $(git rev-parse --short HEAD)"

# 4. arms
run_arm() {   # $1 arm, $2 runs per N, $3 description, then run-batch.sh options
    ARM=$1; REPS=${REPS_ALL:-$2}; DESC=$3; shift 3
    OUT="$OUT_ROOT/$ARM"
    if [ -f "$OUT/.done" ]; then
        say "$ARM: already complete ($OUT/.done), not run again"
        return 0
    fi
    [ ! -e "$OUT" ] || die "$ARM: $OUT exists but is not complete (interrupted?). Move it aside, e.g.
    mv $OUT $OUT-interrupted-$(date +%Y%m%d-%H%M)
and start again; completed arms are not run again, run-batch.sh cannot resume a batch."
    say "$ARM: starting ($DESC, $REPS runs per N)"
    ./batch/run-batch.sh --reps "$REPS" --shards "$SHARDS" ${NGRID:+--ngrid "$NGRID"} \
        --encounters 16 --no-centralities "$@" --out "$OUT"
    RC=$?
    echo "exploratory arm : $ARM -- $DESC (exploratory_criteria.md, section 2)" >> "$OUT/batch-info.txt"
    [ "$RC" -eq 0 ] || die "$ARM: run-batch.sh exited $RC (see rc= per shard above)"
    EXPECTED=$(awk '{s += $3} END {print s + 0}' "$OUT/shard-list.txt")
    ROWS=$(for f in "$OUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
               wc -l < "$f"; done | awk '{s += $1 - 1} END {print s + 0}')
    [ "$ROWS" -eq "$EXPECTED" ] || die "$ARM: $ROWS runs in split/, expected $EXPECTED"
    if [ "$ARM" = "EX-P" ]; then
        # criteria R4: both arms of every pair start from the identical network
        NOT=$(for f in "$OUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
                  awk -F';' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "paired.start.identical") c = i; next }
                             { if (c == 0 || $c != "true") n++ } END { print n + 0 }' "$f"; done |
              awk '{s += $1} END {print s + 0}')
        [ "$NOT" -eq 0 ] || die "$ARM: paired.start.identical is not true in $NOT of $ROWS pairs (criteria R4: a code error, not a design question)"
        say "$ARM: paired.start.identical true in all $ROWS pairs"
    fi
    touch "$OUT/.done"
    say "$ARM: done, $ROWS runs"
}
run_arm EX-A 300 "main design" --omega-random
run_arm EX-B 150 "omega = 0" --omega 0
run_arm EX-P 150 "paired, gamma ~ U[0.1, 0.2]" --omega-random --ep-structure both --gamma-min 0.1 --gamma-max 0.2

# 5. hand-over tarballs
for ARM in EX-A EX-B EX-P; do
    T="$ARM.tgz"
    if [ -f "$OUT_ROOT/$T" ] && [ -f "$OUT_ROOT/$T.sha256" ] && (cd "$OUT_ROOT" && sha256sum -c --status "$T.sha256"); then
        say "$T: present and verified, not packed again"
        continue
    fi
    say "packing $T"
    tar czf "$OUT_ROOT/$T" -C "$OUT_ROOT/$ARM" split batch-info.txt shard-list.txt config.properties.source \
        || die "tar failed for $ARM"
    (cd "$OUT_ROOT" && sha256sum "$T" > "$T.sha256" && sha256sum -c --status "$T.sha256") || die "sha256 failed for $ARM"
done
say "hand-over files:"
(cd "$OUT_ROOT" && for ARM in EX-A EX-B EX-P; do
    echo "    $ARM.tgz  $(wc -c < "$ARM.tgz") bytes  $(cut -c1-64 "$ARM.tgz.sha256")"; done)
say "=== exploratory batch complete: $OUT_ROOT ==="
