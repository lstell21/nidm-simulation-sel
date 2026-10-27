#!/bin/sh
# Bug check S6 (27 Oct 2026): how much does the known divergence at Agent.java:1087 change
# the results? Two batches, identical except for that one statement:
#   buggy  selective-contact-reduction at b903e12 (as released; the main clone)
#   fixed  branch bugfix-1087-test (the one-line fix plus a unit test; a second clone)
# both with Run B's options at N = 80:
#   run-batch.sh --reps 16000 --shards 16 --ngrid 80 --omega 0 --no-centralities
# (s stays random, Bernoulli 0.5: about 8,000 runs per build and condition). Analysis
# criteria, fixed before the runs: SelSWIDM-analysis
# reports/memo/handoff-2026-10-14/bugcheck_criteria.md.
#
# This script lives on branch bugfix-1087-test only. Run it from the root of the main clone,
# which stays on selective-contact-reduction and must be clean, from a copy outside the clone:
#   git show origin/bugfix-1087-test:batch/bugcheck.sh > ../bugcheck.sh
#   nohup sh ../bugcheck.sh >> batch-runs/bugcheck.log 2>&1 &
#
# What it does:
#   1. checks the main clone: branch selective-contact-reduction, clean, contains b903e12, and
#      src/main, pom.xml and batch/run-batch.sh identical to b903e12;
#   2. takes the lock batch-runs/bugcheck.lock (mkdir is atomic; a second start stops);
#   3. clones bugfix-1087-test next to the main clone (../nidm-simulation-sel-bugfix) from the
#      main clone's origin, or fast-forwards an existing clone; checks it is clean and differs
#      from b903e12 in src/main, pom.xml and batch/run-batch.sh only by Agent.java. (A second
#      clone rather than a git worktree: git-commit-id-plugin 3.0.0 with the pom's
#      dotGitDirectory=${project.basedir}/.git cannot build in a worktree, where .git is a file.)
#   4. builds both with Maven; checks both trees are still clean and that each build's
#      git.properties names its own HEAD, not dirty;
#   5. runs buggy, then fixed (each run-batch.sh records its tree's git commit and dirty count
#      in batch-info.txt; this script adds the build label);
#   6. packs batch-runs/bugcheck-handover/bugcheck-{buggy,fixed}.tgz (split/, batch-info.txt,
#      shard-list.txt, config.properties.source) with .sha256 files.
#
# After an interruption (reboot, killed shell): a batch that finished (its .done marker) is
# not run again; a batch that started but did not finish makes the script stop with a message
# -- move that folder aside and start again (run-batch.sh cannot resume a batch). If the lock
# is left behind, the script says so; remove it only when no java process of this check runs.
#
# Overrides (for the smoke test): REPS (16000), SHARDS (16), OUT_ROOT (<main>/batch-runs),
# MVN (mvn).

set -u

BUGGY_COMMIT=b903e121b237f4d5134dc24c4113314a8508377e
FIX_BRANCH=bugfix-1087-test
REPS=${REPS:-16000}
SHARDS=${SHARDS:-16}
MVN=${MVN:-mvn}

say() { echo "[$(date '+%F %T')] $*"; }
die() { say "STOPPED: $*"; exit 1; }

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git clone; cd to the main clone root first"
[ "$(cd "$TOP" && pwd -P)" = "$(pwd -P)" ] || die "run this from the root of the main clone ($TOP)"
# POSIX form (/c/Users/... on Git Bash): git rev-parse gives C:/Users/..., which
# run-batch.sh would take for a relative --out and prefix with its working directory
MAIN=$(pwd -P)
[ -f "$MAIN/batch/run-batch.sh" ] || die "$MAIN is not an nidm-simulation-sel clone"
OUT_ROOT=${OUT_ROOT:-$MAIN/batch-runs}
if command -v cygpath > /dev/null 2>&1; then OUT_ROOT=$(cygpath -u "$OUT_ROOT"); fi
case "$OUT_ROOT" in /*) ;; *) OUT_ROOT="$MAIN/$OUT_ROOT" ;; esac
case "$OUT_ROOT" in /*) ;; *) die "output root $OUT_ROOT is not an absolute POSIX path" ;; esac
FIX_DIR="$(dirname "$MAIN")/nidm-simulation-sel-bugfix"
LOCK="$OUT_ROOT/bugcheck.lock"
HANDOVER="$OUT_ROOT/bugcheck-handover"

say "=== bug check Agent.java:1087: buggy vs fixed, N = 80, omega = 0, $REPS runs x 2, $SHARDS shards ==="
say "main clone  : $MAIN"
say "fixed clone : $FIX_DIR"
say "output      : $OUT_ROOT"

# 1. main clone = the buggy build
cd "$MAIN" || die "cannot cd to $MAIN"
[ "$(git rev-parse --abbrev-ref HEAD)" = "selective-contact-reduction" ] \
    || die "main clone is on $(git rev-parse --abbrev-ref HEAD), not selective-contact-reduction"
[ -z "$(git status --porcelain)" ] || die "main clone is not clean (git status --short); untracked files count too"
git merge-base --is-ancestor "$BUGGY_COMMIT" HEAD 2>/dev/null || die "main clone does not contain $BUGGY_COMMIT (git pull --ff-only?)"
git diff --quiet "$BUGGY_COMMIT" HEAD -- src/main pom.xml batch/run-batch.sh \
    || die "main clone's model code, pom.xml or run-batch.sh differ from $BUGGY_COMMIT"
say "main clone ok: $(git rev-parse --short HEAD) on selective-contact-reduction, clean, code = $(echo $BUGGY_COMMIT | cut -c1-7)"

# 2. lock
mkdir -p "$OUT_ROOT"
if ! mkdir "$LOCK" 2>/dev/null; then
    die "$LOCK exists: the check is running already, or an earlier start was killed. Nothing started.
    If no java process of this check runs (Task Manager), remove the lock: rmdir $LOCK"
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
say "lock taken: $LOCK"

# 3. fixed clone
if [ ! -d "$FIX_DIR" ]; then
    URL=$(git remote get-url origin) || die "main clone has no origin"
    say "cloning $FIX_BRANCH from $URL into $FIX_DIR"
    git clone -q -b "$FIX_BRANCH" "$URL" "$FIX_DIR" || die "git clone failed"
else
    say "updating existing $FIX_DIR"
    [ -z "$(git -C "$FIX_DIR" status --porcelain)" ] || die "$FIX_DIR is not clean"
    [ "$(git -C "$FIX_DIR" rev-parse --abbrev-ref HEAD)" = "$FIX_BRANCH" ] || die "$FIX_DIR is not on $FIX_BRANCH"
    git -C "$FIX_DIR" pull -q --ff-only || die "git pull --ff-only failed in $FIX_DIR"
fi
CHANGED=$(git -C "$FIX_DIR" diff --name-only "$BUGGY_COMMIT" HEAD -- src/main pom.xml batch/run-batch.sh)
[ "$CHANGED" = "src/main/java/nl/uu/socnetid/nidm/agents/Agent.java" ] \
    || die "fixed clone differs from $BUGGY_COMMIT in more than Agent.java: $CHANGED"
git -C "$FIX_DIR" grep -q "^        allAgentsShuffled.removeAll(distance2AgentsShuffled);" HEAD -- src/main/java/nl/uu/socnetid/nidm/agents/Agent.java \
    || die "fixed clone does not contain the fix"
say "fixed clone ok: $(git -C "$FIX_DIR" rev-parse --short HEAD) on $FIX_BRANCH, differs from $(echo $BUGGY_COMMIT | cut -c1-7) only in Agent.java"

# 4. builds
for TREE in "$MAIN" "$FIX_DIR"; do
    say "building $TREE"
    (cd "$TREE" && "$MVN" -B -q package -DskipTests) || die "Maven build failed in $TREE"
    [ -z "$(git -C "$TREE" status --porcelain)" ] || die "$TREE is not clean after the build"
    GP="$TREE/target/classes/git.properties"
    grep -q "^git.commit.id=$(git -C "$TREE" rev-parse HEAD)" "$GP" || die "$GP does not name HEAD"
    grep -q "^git.dirty=false" "$GP" || die "$GP says dirty"
    [ -f "$TREE/target/nidm-4.0.1.jar" ] || die "no target/nidm-4.0.1.jar in $TREE"
done
say "both builds ok"

# 5. batches
run_batch() {   # $1 label, $2 tree, $3 description
    OUT="$OUT_ROOT/bugcheck-$1"
    if [ -f "$OUT/.done" ]; then
        say "$1: already complete ($OUT/.done), not run again"
        return 0
    fi
    [ ! -e "$OUT" ] || die "$1: $OUT exists but is not complete (interrupted?). Move it aside, e.g.
    mv $OUT $OUT-interrupted-$(date +%Y%m%d-%H%M)
and start again; run-batch.sh cannot resume a batch."
    say "$1: starting ($3)"
    (cd "$2" && ./batch/run-batch.sh --reps "$REPS" --shards "$SHARDS" --ngrid 80 --omega 0 \
        --no-centralities --out "$OUT")
    RC=$?
    echo "bug-check build : $1 -- $3" >> "$OUT/batch-info.txt"
    [ "$RC" -eq 0 ] || die "$1: run-batch.sh exited $RC (see rc= per shard above)"
    ROWS=$(for f in "$OUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
               wc -l < "$f"; done | awk '{s += $1 - 1} END {print s + 0}')
    [ "$ROWS" -eq "$REPS" ] || die "$1: $ROWS runs in split/, expected $REPS"
    touch "$OUT/.done"
    say "$1: done, $ROWS runs"
}
run_batch buggy "$MAIN" "selective-contact-reduction $(git -C "$MAIN" rev-parse --short HEAD), Agent.java:1087 as released"
run_batch fixed "$FIX_DIR" "$FIX_BRANCH $(git -C "$FIX_DIR" rev-parse --short HEAD), Agent.java:1087 fixed"

# 6. hand-over tarballs
mkdir -p "$HANDOVER"
for L in buggy fixed; do
    T="bugcheck-$L.tgz"
    if [ -f "$HANDOVER/$T" ] && [ -f "$HANDOVER/$T.sha256" ] && (cd "$HANDOVER" && sha256sum -c --status "$T.sha256"); then
        say "$T: present and verified, not packed again"
        continue
    fi
    say "packing $T"
    tar czf "$HANDOVER/$T" -C "$OUT_ROOT/bugcheck-$L" split batch-info.txt shard-list.txt config.properties.source \
        || die "tar failed for $L"
    (cd "$HANDOVER" && sha256sum "$T" > "$T.sha256" && sha256sum -c --status "$T.sha256") || die "sha256 failed for $L"
done
say "hand-over files:"
(cd "$HANDOVER" && for f in bugcheck-buggy.tgz bugcheck-fixed.tgz; do
    echo "    $f  $(wc -c < "$f") bytes  $(cut -c1-64 "$f.sha256")"; done)
say "=== bug check complete: $HANDOVER ==="
