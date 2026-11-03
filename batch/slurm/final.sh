#!/bin/sh
# Final re-run batches (S9, 2 Nov 2026) and the robustness batch (S11, 3 Nov 2026), run from an
# unpacked bundle made by batch/slurm/make-bundle.sh: on the AI-Lab cluster through
# final.sbatch, or anywhere else for a smoke test (then with --shards). Design: selcor-handoff
# exploratory_criteria.md, section 6 (fixed 1 Nov 2026), and robustness_criteria.md (approved
# 3 Nov 2026); build rerun-fixes after S11.
#
#   batch/slurm/final.sh <batch> [--reps R] [--ngrid LIST] [--out DIR] [--shards K] [--dry-run]
#                                [--zeta Z] [--runs-factor F]
#
#   main    default N grid (80-480), 10,000 runs per N, omega ~ U[0, 1]
#   w0      as main with omega = 0
#   paired  as main with ep-structure both, gamma ~ U[0.1, 0.2] (10,000 pairs per N)
#   tie1    N = 240, 5,000 runs, tie events, gamma ~ U[0.1, 0.2], omega ~ U[0, 1], heap 2g
#           (the mechanism launch's M1 options, task 3b)
#   tie2    N = 240, 5,000 runs, tie events, gamma ~ U[0.1, 0.4], omega = 0, heap 2g (M2)
#   These five: alpha ~ U[0, 0.9] (--alpha-max 0.9), 16 encounters, no centralities, random
#   agent order and each second-degree neighbour once (--fix-order --fix-d2; decided 3 Nov),
#   burn-in zeta from --zeta Z (default 10; set after the robustness batch, rule B), 10 rounds
#   after each outbreak (--zeta-post 10, S11b).
#   exa80   cluster check against the exploratory batch: exactly arm EX-A's options
#           (exploratory.sh: --encounters 16 --no-centralities --omega-random; alpha ~ U[0, 1],
#           not 0.9; switches off, zeta 10), N = 80 only, 300 runs.
#   robust  robustness batch, nine cells one after another, each a run-batch.sh batch at one N
#           with the main batch's options (--encounters 16 --no-centralities --omega-random
#           --alpha-max 0.9):
#             arm A  switches off (as 3e4e86d), zeta 10
#             arm B  --fix-order --fix-d2, zeta 10
#             arm C  --fix-order --fix-d2, zeta 30 (burn-in), 10 rounds after the outbreak
#           at N = 80 (20,000 runs per arm), 240 (5,000) and 480 (1,000). Cell order: N = 80
#           A, B, C, then N = 240 A, B, C, then N = 480 A, B, C (all arms of the cheapest N
#           first). --runs-factor F (0 < F <= 1) multiplies every cell's runs alike;
#           --ngrid restricts the N values, --reps sets every cell's runs (smoke tests).
#
# Runs through run-batch.sh in batch-jar mode (the bundle's target/nidm-4.0.1-batch.jar), so
# the shard allocation, the shard configs and the split/ layout are exactly the exploratory
# batch's. Shards: --shards K, else $SLURM_CPUS_PER_TASK; never nproc (on the cluster it
# reports all 256 CPUs of the node). Java: $JAVA_HOME/bin first on PATH (default
# $HOME/opt/jdk8u502-b07-jre); the script stops unless java -version reports 1.8.0_502.
# Every shard's JVM gets -Xms = -Xmx -XX:+UseSerialGC -XX:ActiveProcessorCount=1 (see JVM_OPTS
# below for why).
#
# Output (default --out <bundle>/batch-runs/final):
#   <out>/<batch>/            run-batch.sh's --out: split/, work/, batch-info.txt, shard-list.txt;
#                             for robust one such folder per cell: <out>/robust/<arm>-n<N>/
#   <out>/<batch>.tgz         split/, batch-info.txt, shard-list.txt, config.properties.source
#                             (robust: the same under <arm>-n<N>/ for every cell)
#   <out>/<batch>.tgz.sha256  (SelSWIDM-analysis unpacks it into data/rerun/<batch>/)
#   <out>/<batch>.lock        while it runs (mkdir is atomic, also on NFS: a second start stops)
#
# Checks: the bundle (BUNDLE-PROVENANCE.txt, no .git, the jar's SHA-256), Java 1.8.0_502, every
# shard rc = 0, the number of runs in split/ against shard-list.txt, for paired that
# paired.start.identical is true in every pair, for tie1/tie2 that every shard wrote
# tie-events.csv and transmissions.csv. Any failure stops the script with exit 1.
#
# After an interruption it does not resume a run-batch.sh batch (it cannot). A batch, or robust
# cell, with its .done marker is not run again (a resubmitted robust job goes on with the next
# cell; the tarball is packed if it is missing or does not verify); a folder without .done
# stops the script with the mv command that moves it aside, and a left-over lock stops it with
# the rmdir command. Then submit again.

set -u

say() { echo "[$(date '+%F %T')] $*"; }
die() { say "STOPPED: $*"; exit 1; }

usage="usage: final.sh main|w0|paired|tie1|tie2|exa80|robust [--reps R] [--ngrid LIST] [--out DIR] [--shards K] [--dry-run] [--zeta Z] [--runs-factor F]"
[ $# -ge 1 ] || die "$usage"
BATCH=$1; shift
REPS_OPT=""; NGRID_OPT=""; OUT_ROOT=""; SHARDS=""; DRY=""; ZETA_OPT=""; FACTOR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --reps)        REPS_OPT="$2"; shift 2 ;;
        --ngrid)       NGRID_OPT="$2"; shift 2 ;;
        --out)         OUT_ROOT="$2"; shift 2 ;;
        --shards)      SHARDS="$2"; shift 2 ;;
        --dry-run)     DRY=1; shift ;;
        --zeta)        ZETA_OPT="$2"; shift 2 ;;
        --runs-factor) FACTOR="$2"; shift 2 ;;
        *) die "unknown option: $1
$usage" ;;
    esac
done

# The batches. Options as in exploratory.sh and the mechanism launch (MECHANISM_REPORT.md, 5).
COMMON="--encounters 16 --no-centralities"
# decided 3 Nov 2026 (robustness_criteria.md, D1 and D2): every final batch
FIXES="--fix-order --fix-d2"
ZETA=${ZETA_OPT:-10}
case "$ZETA" in ''|*[!0-9]*) die "zeta must be a number, not '$ZETA'" ;; esac
case "$BATCH" in
    main)   REPS=10000; NGRID=""; HEAP=1g; DESC="main design, alpha ~ U[0, 0.9]"
            set -- --omega-random --alpha-max 0.9 $FIXES --zeta "$ZETA" --zeta-post 10 ;;
    w0)     REPS=10000; NGRID=""; HEAP=1g; DESC="omega = 0, alpha ~ U[0, 0.9]"
            set -- --omega 0 --alpha-max 0.9 $FIXES --zeta "$ZETA" --zeta-post 10 ;;
    paired) REPS=10000; NGRID=""; HEAP=1g; DESC="paired (ep-structure both), gamma ~ U[0.1, 0.2], alpha ~ U[0, 0.9]"
            set -- --omega-random --ep-structure both --gamma-min 0.1 --gamma-max 0.2 --alpha-max 0.9 $FIXES --zeta "$ZETA" --zeta-post 10 ;;
    tie1)   REPS=5000; NGRID=240; HEAP=2g; DESC="tie events, gamma ~ U[0.1, 0.2], omega random, alpha ~ U[0, 0.9] (M1 options)"
            set -- --gamma-min 0.1 --gamma-max 0.2 --omega-random --alpha-min 0 --alpha-max 0.9 --tie-events $FIXES --zeta "$ZETA" --zeta-post 10 ;;
    tie2)   REPS=5000; NGRID=240; HEAP=2g; DESC="tie events, gamma ~ U[0.1, 0.4], omega = 0, alpha ~ U[0, 0.9] (M2 options)"
            set -- --gamma-min 0.1 --gamma-max 0.4 --omega 0 --alpha-max 0.9 --tie-events $FIXES --zeta "$ZETA" --zeta-post 10 ;;
    exa80)  REPS=300; NGRID=80; HEAP=1g; DESC="cluster check: exploratory arm EX-A's options at N = 80 (alpha ~ U[0, 1])"
            [ -z "$ZETA_OPT" ] || die "exa80 is EX-A's design: no --zeta"
            set -- --omega-random ;;
    robust) REPS=""; NGRID=""; HEAP=1g; DESC="robustness batch: arms A, B, C at N = 80, 240, 480 (robustness_criteria.md, section 3)"
            [ -z "$ZETA_OPT" ] || die "robust sets zeta per arm (10, 10, 30): no --zeta"
            set -- ;;
    *) die "unknown batch: $BATCH
$usage" ;;
esac
[ -z "$FACTOR" ] || [ "$BATCH" = "robust" ] || die "--runs-factor is for robust only"
REPS=${REPS_OPT:-$REPS}
NGRID=${NGRID_OPT:-$NGRID}
if [ "$BATCH" = "robust" ]; then
    for N in $(printf '%s' "${NGRID:-80,240,480}" | tr ',' ' '); do
        case "$N" in 80|240|480) ;; *) die "robust: N must be 80, 240 or 480, not $N" ;; esac
    done
    if [ -n "$FACTOR" ]; then
        awk -v f="$FACTOR" 'BEGIN { exit !(f + 0 > 0 && f + 0 <= 1) }' || die "--runs-factor must be in (0, 1], not $FACTOR"
    fi
fi

# The JVM sizes its GC and JIT thread pools from the CPUs it sees, and on the cluster that is
# the whole node (256), not the job's share: Java 8's default parallel collector would start
# 8 + (256 - 8) * 5/8 = 163 GC threads in every shard and the JIT up to 36 compiler threads,
# thousands of threads over 64 shards contending for 64 CPUs at every collection. The
# simulation itself is single-threaded (Generator; ThreadedSimulation is GUI-only and unused),
# so each shard gets the serial collector (no GC threads) and one CPU as the JVM's processor
# count (2 JIT threads). -Xms = -Xmx fixes the heap layout whatever the node's memory, so the
# memory a shard can take is the same here and on the laptop where it was measured. None of
# this changes a simulation result: no decision depends on GC or thread counts.
JVM_OPTS="-Xms$HEAP -XX:+UseSerialGC -XX:ActiveProcessorCount=1"

# 1. bundle
BUNDLE=$(cd "$(dirname "$0")/../.." && pwd -P)
PROV="$BUNDLE/BUNDLE-PROVENANCE.txt"
[ -f "$PROV" ] || die "$BUNDLE has no BUNDLE-PROVENANCE.txt: run this from a bundle made by batch/slurm/make-bundle.sh, not from a clone"
[ ! -e "$BUNDLE/.git" ] || die "$BUNDLE is a git clone: run this from an unpacked bundle (make-bundle.sh)"
prov() { sed -n "s/^$1=//p" "$PROV" | tr -d '\r'; }
JAR="$BUNDLE/target/nidm-4.0.1-batch.jar"
[ -f "$JAR" ] || die "missing $JAR"
JAR_SHA=$(sha256sum "$JAR" | cut -c1-64)
[ "$JAR_SHA" = "$(prov jar.sha256)" ] || die "$JAR has sha256 $JAR_SHA, BUNDLE-PROVENANCE.txt says $(prov jar.sha256)"
if [ "$(prov pushed)" != "yes" ] && [ -n "${SLURM_JOB_ID:-}" ]; then
    die "$(prov bundle) was made from a commit not on origin (pushed=$(prov pushed)), for a local smoke test: make the cluster's bundle after git push"
fi
grep -q '^nb\.fix\.order=' "$BUNDLE/src/main/resources/config.properties" \
    || die "$(prov bundle) predates the switches nb.fix.order / nb.fix.d2 (S11): use a newer bundle"

# 2. Java
JAVA_HOME=${JAVA_HOME:-$HOME/opt/jdk8u502-b07-jre}
command -v cygpath > /dev/null 2>&1 && JAVA_HOME=$(cygpath -u "$JAVA_HOME")
# this java and no other: without the check, a missing $JAVA_HOME/bin would let PATH find
# whatever java comes next (found in the laptop smoke test)
[ -x "$JAVA_HOME/bin/java" ] || die "no java in $JAVA_HOME/bin (set JAVA_HOME to the Java 8u502 runtime)"
PATH="$JAVA_HOME/bin:$PATH"; export PATH JAVA_HOME
JV=$("$JAVA_HOME/bin/java" -version 2>&1 | tr -d '\r')
case "$(printf '%s\n' "$JV" | sed -n 1p)" in
    *'"1.8.0_502"'*) ;;
    *) die "java from $JAVA_HOME/bin reports: $(printf '%s\n' "$JV" | sed -n 1p); 1.8.0_502 needed (set JAVA_HOME)" ;;
esac

# 3. shards
if [ -z "$SHARDS" ]; then
    [ -n "${SLURM_CPUS_PER_TASK:-}" ] || die "not in a Slurm job with --cpus-per-task: pass --shards K"
    SHARDS=$SLURM_CPUS_PER_TASK; SHARDS_FROM="SLURM_CPUS_PER_TASK"
else
    SHARDS_FROM="--shards"
fi
case "$SHARDS" in ''|*[!0-9]*) die "shards must be a number, not '$SHARDS'" ;; esac

# 4. output (POSIX path: run-batch.sh treats C:/... as relative)
OUT_ROOT=${OUT_ROOT:-$BUNDLE/batch-runs/final}
command -v cygpath > /dev/null 2>&1 && OUT_ROOT=$(cygpath -u "$OUT_ROOT")
case "$OUT_ROOT" in /*) ;; *) OUT_ROOT="$PWD/$OUT_ROOT" ;; esac
OUT="$OUT_ROOT/$BATCH"
LOCK="$OUT_ROOT/$BATCH.lock"

say "=== final batch $BATCH: $DESC ==="
say "bundle : $BUNDLE ($(prov bundle), commit $(prov commit), branch $(prov branch), dirty $(prov dirty), on origin: $(prov pushed))"
say "jar    : sha256 $JAR_SHA (matches BUNDLE-PROVENANCE.txt)"
say "java   : $(printf '%s\n' "$JV" | sed -n 1p), $JAVA_HOME; JVM options -Xmx$HEAP $JVM_OPTS"
say "shards : $SHARDS (from $SHARDS_FROM)"
[ -n "${SLURM_JOB_ID:-}" ] && say "slurm  : job ${SLURM_JOB_ID} (${SLURM_JOB_NAME:-}) on ${SLURMD_NODENAME:-?}, ${SLURM_CPUS_PER_TASK:-?} CPUs, ${SLURM_MEM_PER_NODE:-?} MB"
say "output : $OUT"
if [ -n "$REPS_OPT$NGRID_OPT" ]; then
    say "smoke settings: reps ${REPS:-design} per N, N grid ${NGRID:-default}"
fi

# The robust cells: "<arm> <N> <runs> <zeta> <switch options>", in the order they run
# (N and the runs factor are checked above).
robust_cells() {
    for N in $(printf '%s' "${NGRID:-80,240,480}" | tr ',' ' '); do
        case "$N" in
            80)  R=20000 ;;
            240) R=5000 ;;
            480) R=1000 ;;
        esac
        if [ -n "$REPS_OPT" ]; then
            R=$REPS_OPT
        elif [ -n "$FACTOR" ]; then
            R=$(awk -v r="$R" -v f="$FACTOR" 'BEGIN { printf "%d", r * f + 0.5 }')
        fi
        echo "A $N $R 10"
        echo "B $N $R 10 $FIXES"
        echo "C $N $R 30 $FIXES --zeta-post 10"
    done
}

if [ -n "$DRY" ]; then
    if [ "$BATCH" = "robust" ]; then
        robust_cells | while read -r ARM N R Z F; do
            say "cell $ARM-n$N: $R runs, zeta $Z${F:+, $F}"
            sh "$BUNDLE/batch/run-batch.sh" --reps "$R" --shards "$SHARDS" --ngrid "$N" $COMMON \
                --omega-random --alpha-max 0.9 $F --zeta "$Z" --heap "$HEAP" --jvm-opts "$JVM_OPTS" \
                --jar "$JAR" --out "$OUT/$ARM-n$N" --dry-run | sed -n '/shard allocation/,$p'
        done
        exit 0
    fi
    sh "$BUNDLE/batch/run-batch.sh" --reps "$REPS" --shards "$SHARDS" ${NGRID:+--ngrid "$NGRID"} \
        $COMMON "$@" --heap "$HEAP" --jvm-opts "$JVM_OPTS" --jar "$JAR" --out "$OUT" --dry-run
    exit $?
fi

# 5. lock
mkdir -p "$OUT_ROOT" || die "cannot create $OUT_ROOT"
if ! mkdir "$LOCK" 2>/dev/null; then
    die "$LOCK exists: batch $BATCH is running already, or an earlier job was killed. Nothing started.
    If no job of this batch runs (squeue -u \$USER), remove the lock: rmdir $LOCK"
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
trap 'say "signal received (scancel or time limit?): stopping"; exit 143' INT TERM
say "lock taken: $LOCK"

# 6. one run-batch.sh batch, checked: run_cell NAME DIR RUNS NGRID LABEL run-batch.sh options
run_cell() {
    CELL=$1; COUT=$2; CREPS=$3; CNGRID=$4; CLABEL=$5; shift 5
    if [ -f "$COUT/.done" ]; then
        say "$CELL: already complete ($COUT/.done), not run again"
        return 0
    fi
    [ ! -e "$COUT" ] || die "$CELL: $COUT exists but is not complete (interrupted?). Move it aside, e.g.
    mv $COUT $COUT-interrupted-$(date +%Y%m%d-%H%M)
and submit again; run-batch.sh cannot resume a batch, completed cells are not run again."
    case "$CNGRID" in
        *,*|'') ;;
        *) [ "$CREPS" -ge "$SHARDS" ] || die "$CELL: $CREPS runs at one N cannot fill $SHARDS shards" ;;
    esac
    say "$CELL: starting ($CREPS runs per N)"
    sh "$BUNDLE/batch/run-batch.sh" --reps "$CREPS" --shards "$SHARDS" ${CNGRID:+--ngrid "$CNGRID"} \
        $COMMON "$@" --heap "$HEAP" --jvm-opts "$JVM_OPTS" --jar "$JAR" --out "$COUT"
    RC=$?
    {
        echo "$CLABEL"
        echo "bundle jar      : sha256 $JAR_SHA (BUNDLE-PROVENANCE.txt: built $(prov jar.build.time) from $(prov jar.git.commit.id), $(prov build.java))"
        echo "java runtime    : $(printf '%s\n' "$JV" | sed -n 2p)"
        echo "shards from     : $SHARDS_FROM"
        if [ -n "${SLURM_JOB_ID:-}" ]; then
            echo "slurm job       : ${SLURM_JOB_ID} (${SLURM_JOB_NAME:-}) on ${SLURMD_NODENAME:-?}, ${SLURM_CPUS_PER_TASK:-?} CPUs, ${SLURM_MEM_PER_NODE:-?} MB"
        else
            echo "slurm job       : none ($(hostname))"
        fi
    } >> "$COUT/batch-info.txt"
    [ "$RC" -eq 0 ] || die "$CELL: run-batch.sh exited $RC (see rc= per shard above)"

    # checks
    EXPECTED=$(awk '{s += $3} END {print s + 0}' "$COUT/shard-list.txt")
    ROWS=$(for f in "$COUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
               wc -l < "$f"; done | awk '{s += $1 - 1} END {print s + 0}')
    [ "$ROWS" -eq "$EXPECTED" ] || die "$CELL: $ROWS runs in split/, expected $EXPECTED"
    if [ "$BATCH" = "paired" ]; then
        # both arms of every pair start from the identical network (criteria R4: a code error otherwise)
        NOT=$(for f in "$COUT"/split/*/data/nunnerbuskens/simulation-summary.csv; do
                  awk -F';' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "paired.start.identical") c = i; next }
                             { if (c == 0 || $c != "true") n++ } END { print n + 0 }' "$f"; done |
              awk '{s += $1} END {print s + 0}')
        [ "$NOT" -eq 0 ] || die "$CELL: paired.start.identical is not true in $NOT of $ROWS pairs (a code error, not a design question)"
        say "$CELL: paired.start.identical true in all $ROWS pairs"
    fi
    if [ "$BATCH" = "tie1" ] || [ "$BATCH" = "tie2" ]; then
        for d in "$COUT"/split/*/; do
            for f in tie-events.csv transmissions.csv; do
                [ -f "$d/data/nunnerbuskens/$f" ] || die "$CELL: $d has no $f"
            done
        done
        say "$CELL: tie-events.csv and transmissions.csv in every shard"
    fi
    touch "$COUT/.done"
    say "$CELL: done, $ROWS runs (expected $EXPECTED)"
}

# 7. run
if [ "$BATCH" = "robust" ]; then
    mkdir -p "$OUT" || die "cannot create $OUT"
    CELLS=$(robust_cells)
    say "cells (in this order): $(printf '%s\n' "$CELLS" | awk '{printf "%s%s-n%s (%s runs, zeta %s)", (NR > 1 ? ", " : ""), $1, $2, $3, $4}')"
    # a here-document, not a pipe: run_cell's die must end this shell, not a subshell
    while read -r ARM N R Z F; do
        case "$ARM" in
            A) ADESC="switches off (order and second-degree draw as 3e4e86d), zeta 10" ;;
            B) ADESC="random agent order, each second-degree neighbour once, zeta 10" ;;
            C) ADESC="random agent order, each second-degree neighbour once, zeta 30 (burn-in), zeta.post 10" ;;
        esac
        run_cell "$ARM-n$N" "$OUT/$ARM-n$N" "$R" "$N" \
            "robust cell     : $ARM-n$N -- arm $ARM: $ADESC (robustness_criteria.md, section 3)" \
            --omega-random --alpha-max 0.9 $F --zeta "$Z"
    done <<EOF
$CELLS
EOF
    PACK_DIRS=$(printf '%s\n' "$CELLS" | awk '{print $1 "-n" $2}')
else
    run_cell "$BATCH" "$OUT" "$REPS" "$NGRID" \
        "final batch     : $BATCH -- $DESC (exploratory_criteria.md, section 6)" "$@"
    PACK_DIRS=""
fi

# 8. hand-over tarball
T="$BATCH.tgz"
if [ -f "$OUT_ROOT/$T" ] && [ -f "$OUT_ROOT/$T.sha256" ] && (cd "$OUT_ROOT" && sha256sum -c --status "$T.sha256"); then
    say "$T: present and verified, not packed again"
else
    say "packing $T"
    if [ -n "$PACK_DIRS" ]; then
        PACK=$(for d in $PACK_DIRS; do
                   printf '%s ' "$d/split" "$d/batch-info.txt" "$d/shard-list.txt" "$d/config.properties.source"
               done)
        # shellcheck disable=SC2086 # one word per path (no spaces in cell names)
        tar czf "$OUT_ROOT/$T" -C "$OUT" $PACK || die "tar failed for $BATCH"
    else
        tar czf "$OUT_ROOT/$T" -C "$OUT" split batch-info.txt shard-list.txt config.properties.source \
            || die "tar failed for $BATCH"
    fi
    (cd "$OUT_ROOT" && sha256sum "$T" > "$T.sha256" && sha256sum -c --status "$T.sha256") || die "sha256 failed for $BATCH"
fi
say "hand-over: $OUT_ROOT/$T  $(wc -c < "$OUT_ROOT/$T") bytes  $(cut -c1-64 "$OUT_ROOT/$T.sha256")"
say "=== final batch $BATCH complete ==="
