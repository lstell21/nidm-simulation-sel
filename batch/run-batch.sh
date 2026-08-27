#!/bin/sh
# Shards a NunnerBuskens Monte Carlo batch across K independent JVM processes and
# lays the output out the way SelSWIDM-analysis expects to consume it.
#
# WHY ONE N PER SHARD:
# SelSWIDM-analysis/R/00_data-wrangling.R does not read N from the CSV. It greps
# "nb.N=" out of each run's config.properties:
#
#     nbNLine <- grep("nb.N=", configFile, value = TRUE)
#     nbN <- as.numeric(strsplit(nbNLine, "=")[[1]][2])
#
# so a config holding the whole grid (nb.N=80,160,...) yields as.numeric of a
# comma string -- NA for every row, silently. Each shard therefore gets exactly
# one N value, which is also how the preprint's data was produced (the pipeline's
# MERGE_ROOT_DIR is ./data/split, one directory per run).
#
# WHY SHARDS ARE ALLOCATED UNEVENLY:
# Cost grows as roughly N^2.9, so one replication at N=480 costs ~300x one at
# N=80. Splitting shards evenly across levels would leave the N=480 shard running
# for days after the others finished. Shards are allocated greedily in proportion
# to each level's total cost so they finish at about the same time.
#
# Usage:
#   ./run-batch.sh --reps 10000 --shards 16 --omega 0 --no-centralities
#
# Options:
#   --reps N          replications per N level (default 5000)
#   --shards K        total parallel JVM processes (default 8); must be >= number
#                     of N levels, since every level needs at least one shard
#   --ngrid "a,b,c"   N grid (default "80,160,240,320,400,480")
#   --zeta Z          override nb.zeta
#   --omega V         fix nb.omega to V and set nb.omega.random=false
#   --omega-random    force nb.omega.random=true
#   --encounters K    hold encounters per agent constant at K by setting
#                     nb.phi = K/(N-1) per level (default 16 -- the Table 1
#                     design; see the phi note below)
#   --phi V           set a flat nb.phi proportion instead; overrides
#                     --encounters
#   --sigma-random    force nb.sigma.random=true (config.properties already
#                     carries the Table 1 setting, so this is now redundant)
#   --gamma-min V / --gamma-max V   override nb.gamma.random.min/max
#   --alpha-min V / --alpha-max V   override nb.alpha.random.min/max
#   --cost-exp E      cost model exponent for shard allocation (default 3.1;
#                     measured 3.02 off / 3.17 on -- do not lower it)
#   --no-centralities  gate the unread centrality fields out of the round
#                     summary; worth 1.6-1.9x. Use it.
#   --no-round-summary  set export.summary.each.round=false (breaks C1 figures)
#   --heap SIZE       -Xmx per shard (default 1g)
#   --out DIR         output root (default batch-runs/<timestamp>)
#   --jar PATH        fat jar (default target/nidm-4.0.1.jar)
#   --dry-run         print the plan, including shard allocation, and exit

set -e

REPO=$(cd "$(dirname "$0")/.." && pwd)
NGRID="80,160,240,320,400,480"
REPS=5000
SHARDS=8
ZETA=""; OMEGA=""; OMEGA_RANDOM=""; SIGMA_RANDOM=""
# nb.phi is a PROPORTION of N-1, not a count: Agent.getNumberOfNetworkDecisions()
# computes round((nodeCount - 1) * phi). Table 1 of the manuscript specifies
# phi = 16 encounters per agent per time step, "kept constant" across N, which a
# fixed proportion does not deliver -- at nb.phi=0.20 an agent sees 16 peers at
# N=80 but 96 at N=480. --encounters K sets nb.phi = K/(N-1) per shard so the
# encounter count really is held constant.
# Constant phi ratified as the design 27 Aug 2026, so this defaults to 16 rather
# than opt-in; --phi V is the escape hatch for a deliberately flat proportion.
ENCOUNTERS=16; PHI=""
GAMMA_MIN=""; GAMMA_MAX=""; ALPHA_MIN=""; ALPHA_MAX=""; SIGMA_MIN=""; SIGMA_MAX=""
ROUND_SUMMARY=""; CENTRALITIES=""
HEAP="1g"
OUT=""
JAR="$REPO/target/nidm-4.0.1.jar"
DRY=0

# Exponent for the cost model used only to balance shards; a wrong value costs
# load imbalance, nothing else. 3.1 is the six-point fit on the current branch
# config. Re-fit and pass --cost-exp after re-measuring with the real config:
# the batch finishes when its slowest shard does, so this directly sets how much
# of the theoretical speed-up you actually get.
COST_EXP=3.1

while [ $# -gt 0 ]; do
    case "$1" in
        --reps)             REPS="$2"; shift 2 ;;
        --shards)           SHARDS="$2"; shift 2 ;;
        --ngrid)            NGRID="$2"; shift 2 ;;
        --zeta)             ZETA="$2"; shift 2 ;;
        --omega)            OMEGA="$2"; shift 2 ;;
        --omega-random)     OMEGA_RANDOM=1; shift ;;
        --sigma-random)     SIGMA_RANDOM=1; shift ;;
        --sigma-min)        SIGMA_MIN="$2"; shift 2 ;;
        --sigma-max)        SIGMA_MAX="$2"; shift 2 ;;
        --gamma-min)        GAMMA_MIN="$2"; shift 2 ;;
        --gamma-max)        GAMMA_MAX="$2"; shift 2 ;;
        --alpha-min)        ALPHA_MIN="$2"; shift 2 ;;
        --alpha-max)        ALPHA_MAX="$2"; shift 2 ;;
        --encounters)       ENCOUNTERS="$2"; shift 2 ;;
        --phi)              PHI="$2"; ENCOUNTERS=""; shift 2 ;;
        --cost-exp)         COST_EXP="$2"; shift 2 ;;
        --no-round-summary) ROUND_SUMMARY=false; shift ;;
        --no-centralities)  CENTRALITIES=false; shift ;;
        --heap)             HEAP="$2"; shift 2 ;;
        --out)              OUT="$2"; shift 2 ;;
        --jar)              JAR="$2"; shift 2 ;;
        --dry-run)          DRY=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[ -n "$OUT" ] || OUT="$REPO/batch-runs/$(date +%Y%m%d-%H%M%S)"
SRC_CONF="$REPO/src/main/resources/config.properties"

[ -f "$SRC_CONF" ] || { echo "missing $SRC_CONF" >&2; exit 1; }
[ -f "$JAR" ] || { echo "missing jar: $JAR -- run 'mvn package -DskipTests'" >&2; exit 1; }

# target/classes must precede the jar on the classpath. PropertiesHandler
# resolves the age-structure CSVs with Paths.get(resource.toURI()), which throws
# FileSystemNotFoundException when the resource resolves to a jar:file: URI, so
# the shaded jar cannot supply them -- they must be readable as real files.
CLASSES="$REPO/target/classes"
[ -d "$CLASSES" ] || { echo "missing $CLASSES -- run 'mvn package -DskipTests'" >&2; exit 1; }

NLEVELS=$(printf '%s' "$NGRID" | tr ',' '\n' | grep -c .)
[ "$SHARDS" -ge "$NLEVELS" ] || {
    echo "shards ($SHARDS) < N levels ($NLEVELS): every level needs its own shard" >&2
    exit 1
}

# Greedy cost-proportional allocation: give every level one shard, then hand the
# remaining shards one at a time to whichever level currently has the highest
# cost per shard.
ALLOC=$(printf '%s' "$NGRID" | tr ',' '\n' | awk -v K="$SHARDS" -v reps="$REPS" -v e="$COST_EXP" '
    { n[NR] = $1; cost[NR] = reps * ($1 ^ e); s[NR] = 1; L = NR }
    END {
        for (given = L; given < K; given++) {
            worst = 1
            for (i = 2; i <= L; i++) if (cost[i]/s[i] > cost[worst]/s[worst]) worst = i
            s[worst]++
        }
        for (i = 1; i <= L; i++) print n[i], s[i]
    }')

echo "batch plan"
echo "  N grid          : $NGRID  ($NLEVELS levels)"
echo "  reps per N      : $REPS"
echo "  total sims      : $(( REPS * NLEVELS ))"
echo "  shards          : $SHARDS  (allocated by cost, ~N^$COST_EXP)"
echo "  heap per shard  : $HEAP"
echo "  output          : $OUT"
[ -n "$ZETA" ]          && echo "  zeta override   : $ZETA"
[ -n "$OMEGA" ]         && echo "  omega fixed at  : $OMEGA"
[ -n "$SIGMA_RANDOM" ]  && echo "  sigma           : random"
[ -n "$ROUND_SUMMARY" ] && echo "  round summary   : $ROUND_SUMMARY"
echo
echo "  shard allocation:"
echo "$ALLOC" | while read -r N S; do
    printf "    N=%-5s %2s shard(s)  %s reps each\n" "$N" "$S" "$(( REPS / S ))"
done
echo

[ "$DRY" -eq 1 ] && exit 0

mkdir -p "$OUT/work" "$OUT/split"

{
    echo "started         : $(date -Iseconds)"
    echo "git commit      : $(cd "$REPO" && git rev-parse HEAD)"
    echo "git branch      : $(cd "$REPO" && git rev-parse --abbrev-ref HEAD)"
    echo "git dirty       : $(cd "$REPO" && git status --porcelain | wc -l) modified files"
    echo "java            : $(java -version 2>&1 | head -1)"
    echo "ngrid           : $NGRID"
    echo "reps per N      : $REPS"
    echo "shards          : $SHARDS"
    echo "command         : $0 $*"
} > "$OUT/batch-info.txt"

CLASSESW=$(cygpath -w "$CLASSES" 2>/dev/null | tr '\\' '/' || echo "$CLASSES")
JARW=$(cygpath -w "$JAR" 2>/dev/null | tr '\\' '/' || echo "$JAR")

NAMES=""
echo "$ALLOC" | while read -r N S; do
    BASE=$(( REPS / S ))
    EXTRA=$(( REPS % S ))
    k=1
    while [ "$k" -le "$S" ]; do
        SHARD_REPS=$BASE
        [ "$k" -le "$EXTRA" ] && SHARD_REPS=$(( BASE + 1 ))
        echo "n${N}-s${k} $N $SHARD_REPS"
        k=$(( k + 1 ))
    done
done > "$OUT/shard-list.txt"

while read -r NAME N SHARD_REPS; do
    SDIR="$OUT/work/$NAME"
    mkdir -p "$SDIR/conf"

    # Build this shard's config from the tracked one. Only what was asked for is
    # overridden; everything else is inherited, so config.properties stays the
    # single source of truth. Commented-out nb.N lines are stripped because the
    # analysis greps "nb.N=" and would happily match "#nb.N=1000".
    sed -e "s|^nb\.N=.*|nb.N=$N|" \
        -e "s|^nb\.n=.*|nb.n=$SHARD_REPS|" \
        -e "s|^nb\.N\.random=.*|nb.N.random=false|" \
        -e "/^#[[:space:]]*nb\.N=/d" \
        "$SRC_CONF" > "$SDIR/conf/config.properties"

    C="$SDIR/conf/config.properties"
    if [ -n "$ENCOUNTERS" ]; then
        # phi is a proportion of N-1, so hold the encounter count constant by
        # scaling it per level.
        PHI_N=$(awk -v k="$ENCOUNTERS" -v n="$N" 'BEGIN{printf "%.6f", k/(n-1)}')
        sed -i -e "s|^nb\.phi\.random=.*|nb.phi.random=false|" \
               -e "s|^nb\.phi=.*|nb.phi=$PHI_N|" \
               -e "/^#[[:space:]]*nb\.phi=/d" "$C"
    elif [ -n "$PHI" ]; then
        sed -i -e "s|^nb\.phi\.random=.*|nb.phi.random=false|" \
               -e "s|^nb\.phi=.*|nb.phi=$PHI|" \
               -e "/^#[[:space:]]*nb\.phi=/d" "$C"
    fi
    [ -n "$ZETA" ] && sed -i "s|^nb\.zeta=.*|nb.zeta=$ZETA|" "$C"
    if [ -n "$OMEGA" ]; then
        sed -i -e "s|^nb\.omega\.random=.*|nb.omega.random=false|" \
               -e "s|^nb\.omega=.*|nb.omega=$OMEGA|" "$C"
    fi
    [ -n "$OMEGA_RANDOM" ] && sed -i "s|^nb\.omega\.random=.*|nb.omega.random=true|" "$C"
    [ -n "$SIGMA_RANDOM" ] && sed -i "s|^nb\.sigma\.random=.*|nb.sigma.random=true|" "$C"
    [ -n "$SIGMA_MIN" ] && sed -i "s|^nb\.sigma\.random\.min=.*|nb.sigma.random.min=$SIGMA_MIN|" "$C"
    [ -n "$SIGMA_MAX" ] && sed -i "s|^nb\.sigma\.random\.max=.*|nb.sigma.random.max=$SIGMA_MAX|" "$C"
    [ -n "$GAMMA_MIN" ] && sed -i "s|^nb\.gamma\.random\.min=.*|nb.gamma.random.min=$GAMMA_MIN|" "$C"
    [ -n "$GAMMA_MAX" ] && sed -i "s|^nb\.gamma\.random\.max=.*|nb.gamma.random.max=$GAMMA_MAX|" "$C"
    [ -n "$ALPHA_MIN" ] && sed -i "s|^nb\.alpha\.random\.min=.*|nb.alpha.random.min=$ALPHA_MIN|" "$C"
    [ -n "$ALPHA_MAX" ] && sed -i "s|^nb\.alpha\.random\.max=.*|nb.alpha.random.max=$ALPHA_MAX|" "$C"
    [ -n "$ROUND_SUMMARY" ] && sed -i "s|^export\.summary\.each\.round=.*|export.summary.each.round=$ROUND_SUMMARY|" "$C"
    [ -n "$CENTRALITIES" ] && sed -i "s|^export\.summary\.each\.round\.centralities=.*|export.summary.each.round.centralities=$CENTRALITIES|" "$C"

    CONFW=$(cygpath -w "$SDIR/conf" 2>/dev/null | tr '\\' '/' || echo "$SDIR/conf")

    (
        date +%s > "$SDIR/start.epoch"
        cd "$SDIR"
        # 'if' rather than a bare call: under set -e a non-zero java exit would
        # abort the subshell before the exit code and end time were recorded.
        if java -Xmx"$HEAP" -cp "$CONFW;$CLASSESW;$JARW" \
                nl.uu.socnetid.nidm.mains.Generator > "$SDIR/shard.log" 2>&1
        then RC=0; else RC=$?; fi
        echo "$RC" > "$SDIR/exit.code"
        date +%s > "$SDIR/end.epoch"
    ) &

    echo "  launched $NAME  (N=$N, reps=$SHARD_REPS, pid $!)"
done < "$OUT/shard-list.txt"

echo
echo "waiting for $SHARDS shards..."
wait
echo

# Collect into the layout SelSWIDM-analysis consumes: one directory per run,
# each holding config.properties and data/nunnerbuskens/*.csv.
FAILED=0
while read -r NAME N SHARD_REPS; do
    SDIR="$OUT/work/$NAME"
    RC=$(cat "$SDIR/exit.code" 2>/dev/null || echo "?")
    S=$(cat "$SDIR/start.epoch" 2>/dev/null || echo 0)
    E=$(cat "$SDIR/end.epoch" 2>/dev/null || echo 0)
    printf "  %-12s N=%-5s rc=%-3s elapsed=%ss\n" "$NAME" "$N" "$RC" "$(( E - S ))"
    if [ "$RC" = "0" ]; then
        EXPORT=$(find "$SDIR/exports" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
        if [ -n "$EXPORT" ]; then
            rm -rf "$OUT/split/$NAME"
            cp -r "$EXPORT" "$OUT/split/$NAME"
        else
            echo "    WARNING: no export directory found" >&2
            FAILED=$(( FAILED + 1 ))
        fi
    else
        FAILED=$(( FAILED + 1 ))
    fi
done < "$OUT/shard-list.txt"

echo "finished        : $(date -Iseconds)" >> "$OUT/batch-info.txt"

if [ "$FAILED" -gt 0 ]; then
    echo
    echo "WARNING: $FAILED shard(s) failed -- check work/*/shard.log" >&2
    exit 1
fi

echo
echo "done. analysis-ready layout: $OUT/split"
echo "  cp -r $OUT/split/* <SelSWIDM-analysis>/data/split/"
