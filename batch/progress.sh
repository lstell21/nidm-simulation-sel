#!/usr/bin/env bash
#
# Live progress for a Phase 2 batch driven by run-phase2.sh.
#
# run-batch.sh prints its per-shard results only after the wait loop returns, so
# driver.log goes quiet for the length of a chunk. The shards themselves write
# their simulation-summary.csv incrementally, so counting rows there is the way
# to see progress while it is happening.
#
# Usage:  ./batch/progress.sh [runA|runB]
#
# There is no `watch` in Git Bash on this host, so for a live view:
#   while true; do clear; ./batch/progress.sh runA; sleep 60; done

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
ARM="${1:-runA}"
ROOT="$REPO/batch-runs/$ARM"

[ -d "$ROOT" ] || { echo "no batch at $ROOT"; exit 1; }

now=$(date +%s)
hms() { printf '%d:%02d:%02d' $(($1 / 3600)) $((($1 % 3600) / 60)) $(($1 % 60)); }

done_chunks=0; active=""
for c in "$ROOT"/c*/; do
    [ -d "$c" ] || continue
    if [ -f "$c/.done" ]; then done_chunks=$((done_chunks + 1)); else active="$c"; fi
done

staged=$(for f in "$ROOT"/merged/*/data/nunnerbuskens/simulation-summary.csv; do
             [ -f "$f" ] && wc -l < "$f"; done 2>/dev/null |
         awk '{s += $1 - 1} END {print s + 0}')

echo "$ARM: $done_chunks chunk(s) complete, $staged simulations staged"

if [ -z "$active" ]; then
    echo "  no chunk in flight"
    exit 0
fi

echo "  in flight: $(basename "$active")"
tot_done=0; tot_target=0; earliest=$now
for w in "$active"/work/*/; do
    [ -d "$w" ] || continue
    name=$(basename "$w")
    target=$(grep -m1 '^nb.n=' "$w/conf/config.properties" 2>/dev/null | cut -d= -f2)
    target=${target:-0}
    f=$(ls "$w"/exports/*/data/nunnerbuskens/simulation-summary.csv 2>/dev/null | head -1)
    n=0
    [ -n "$f" ] && n=$(( $(wc -l < "$f") - 1 ))
    [ "$n" -lt 0 ] && n=0
    st=$(cat "$w/start.epoch" 2>/dev/null || echo "$now")
    [ "$st" -lt "$earliest" ] && earliest=$st
    if [ -f "$w/exit.code" ]; then
        en=$(cat "$w/end.epoch" 2>/dev/null || echo "$now")
        printf '    %-12s %4s/%-5s done  rc=%s  %s\n' \
            "$name" "$n" "$target" "$(cat "$w/exit.code")" "$(hms $((en - st)))"
    else
        printf '    %-12s %4s/%-5s running  %s\n' \
            "$name" "$n" "$target" "$(hms $((now - st)))"
    fi
    tot_done=$((tot_done + n)); tot_target=$((tot_target + target))
done

if [ "$tot_target" -gt 0 ] && [ "$tot_done" -gt 0 ]; then
    el=$((now - earliest))
    pct=$((100 * tot_done / tot_target))
    eta=$(( el * tot_target / tot_done - el ))
    echo "  chunk: $tot_done/$tot_target sims (${pct}%), elapsed $(hms $el), ETA $(hms $eta)"
    echo "  note: ETA assumes a uniform rate; the N=480 shards finish last."
fi
