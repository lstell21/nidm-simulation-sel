#!/usr/bin/env bash
#
# Live progress for a Phase 2 or Phase 3 batch driven by run-chunked.sh, or for
# the exploratory batch driven by exploratory.sh (its arms EX-A, EX-B, EX-P take
# the place of the chunks).
#
# run-batch.sh prints its per-shard results only after the wait loop returns, so
# driver.log goes quiet for the length of a chunk. The shards themselves write
# their simulation-summary.csv incrementally, so counting rows there is the way
# to see progress while it is happening.
#
# Usage:  ./batch/progress.sh [runA|runB|p3|exploratory]
#
# For a live view use ./batch/start.sh <arm>, which calls this every INTERVAL
# seconds.
#
# Written to fork as little as possible: one awk for all row counts, everything
# else bash builtins (no $(...), cat, grep, wc, ls, basename or date). On this
# Windows host every MSYS process that exits leaves a zombie process object
# pinned by a kernel-mode component (presumably security software) until the
# next reboot, at ~55 KB each. The earlier version forked ~380 processes per
# call; called every 60 s by the start.sh watcher that pinned ~30 GB of RAM
# a day and drove the box into paging on chunk 4 of runA, runB and p3
# (measured 12 Oct 2026: 200 calls -> +75,000 process objects, -4.3 GB
# available). See batch/README.md -> "Zombie processes".

set -u
REPO="${BASH_SOURCE[0]%/*}/.."
ARM="${1:-runA}"
ROOT="$REPO/batch-runs/$ARM"

[ -d "$ROOT" ] || { echo "no batch at $ROOT"; exit 1; }

printf -v now '%(%s)T' -1
hms() { printf -v "$1" '%d:%02d:%02d' $(($2 / 3600)) $((($2 % 3600) / 60)) $(($2 % 60)); }

# run-chunked.sh's chunks c<i>, or exploratory.sh's arms EX-A, EX-B, EX-P (they
# run in that order, so the last one without .done is the one in flight)
done_chunks=0; active=""; unit="chunk"
for c in "$ROOT"/c*/ "$ROOT"/EX-*/; do
    [ -d "$c" ] || continue
    case "$c" in "$ROOT"/EX-*) unit="arm" ;; esac
    if [ -f "$c/.done" ]; then done_chunks=$((done_chunks + 1)); else active="${c%/}"; fi
done

# The files whose data rows we need: every staged summary (a completed arm's
# split/ for the exploratory batch), plus the in-flight shards' own. One awk
# pass counts them all; "<file> <lines>" per file.
files=()
for f in "$ROOT"/merged/*/data/nunnerbuskens/simulation-summary.csv \
         "$ROOT"/EX-*/split/*/data/nunnerbuskens/simulation-summary.csv; do
    [ -f "$f" ] && files+=("$f")
done
if [ -n "$active" ]; then
    for f in "$active"/work/*/exports/*/data/nunnerbuskens/simulation-summary.csv; do
        [ -f "$f" ] && files+=("$f")
    done
fi
declare -A lines=()
if [ "${#files[@]}" -gt 0 ]; then
    while read -r f n; do lines["$f"]=$n; done < <(
        awk 'FNR == 1 && NR > 1 { print pf, pn } { pf = FILENAME; pn = FNR }
             END { if (NR) print pf, pn }' "${files[@]}")
fi
rows() { local _l=${lines["$1"]:-0}; printf -v "$2" '%d' $(( _l > 0 ? _l - 1 : 0 )); }

staged=0
for f in "${files[@]}"; do
    case "$f" in "$ROOT"/merged/*|"$ROOT"/EX-*/split/*) rows "$f" r; staged=$((staged + r)) ;; esac
done

echo "$ARM: $done_chunks $unit(s) complete, $staged simulations staged"

if [ -z "$active" ]; then
    echo "  no $unit in flight"
    exit 0
fi

echo "  in flight: ${active##*/}"
tot_done=0; tot_target=0; earliest=$now; worst=0
for w in "$active"/work/*/; do
    [ -d "$w" ] || continue
    w=${w%/}
    name=${w##*/}
    target=0
    while IFS= read -r l; do
        case "$l" in nb.n=*) target=${l#nb.n=}; break ;; esac
    done < "$w/conf/config.properties" 2>/dev/null
    n=0
    for f in "$w"/exports/*/data/nunnerbuskens/simulation-summary.csv; do
        [ -f "$f" ] && { rows "$f" n; break; }
    done
    st=$now; [ -f "$w/start.epoch" ] && read -r st < "$w/start.epoch"
    [ "$st" -lt "$earliest" ] && earliest=$st
    if [ -f "$w/exit.code" ]; then
        read -r rc < "$w/exit.code"
        en=$now; [ -f "$w/end.epoch" ] && read -r en < "$w/end.epoch"
        hms t $((en - st))
        printf '    %-12s %4s/%-5s done  rc=%s  %s\n' "$name" "$n" "$target" "$rc" "$t"
    else
        hms t $((now - st))
        printf '    %-12s %4s/%-5s running  %s\n' "$name" "$n" "$target" "$t"
        # The chunk ends when its SLOWEST shard does, so project each shard
        # from its own rate and take the worst. A pooled rate is dominated by
        # the small-N shards, which finish early and flatter the estimate
        # badly -- 2h against a real ~11h on the first production chunk.
        if [ "$n" -gt 0 ]; then
            rem=$(( (now - st) * (target - n) / n ))
            [ "$rem" -gt "$worst" ] && worst=$rem
        fi
    fi
    tot_done=$((tot_done + n)); tot_target=$((tot_target + target))
done

if [ "$tot_target" -gt 0 ] && [ "$tot_done" -gt 0 ]; then
    hms el $((now - earliest))
    echo "  $unit: $tot_done/$tot_target sims ($((100 * tot_done / tot_target))%), elapsed $el"
    if [ "$worst" -gt 0 ]; then
        hms eta "$worst"
        echo "  $unit ETA $eta (slowest shard)"
    fi
fi
