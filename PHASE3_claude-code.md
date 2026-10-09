# Phase 3 batch — brief for Claude Code

Written 9 Oct 2026 by Claude Science for Leonard Stellbrink. Two parts: Part A
runs on the machine that holds this working copy (sync the repository); Part B
runs on the compute machine (build, smoke-test, launch the batch, package the
output). Everything you need to know about the harness is in
`batch/README.md`; read its sections "Run", "Phase 3", "Running on another
machine" and "Why it shards" before starting. Do not change simulation
behaviour (`src/main/java/**`): Phase 3 must stay comparable with Runs A and
B, including the documented divergences in `batch/README.md` → "Known
divergences from the manuscript algorithms". Harness and documentation edits
are fine.

Design (settled by the authors, do not alter): γ ~ U[0.1, 0.2], α ~ U[0, 1],
ω ~ U[0, 1], s ~ Bernoulli(0.5), N ∈ {80, 160, 240, 320, 400, 480}, φ = 16
encounters per agent and step (`--encounters 16` default), σ ~ U[1, 3], τ = 5,
ζ = 10, `nb.ep.structure = both`, 10,000 outbreaks per N, centralities off.

## Part A — on this machine (working copy `nidm-simulation-sel`)

State established on 9 Oct 2026 (first pass, stopped before changing
anything): branch `selective-contact-reduction` at `07cf5f9`, which is on
origin; the local branch is **five commits behind** `origin` (28 Aug 2026,
`c169213` … `6e055ba`: Phase 2 drivers `batch/phase2.sh`,
`batch/run-phase2.sh`, `batch/progress.sh`, plus `.gitignore`, README and a
config comment). Uncommitted local edits: `.gitattributes`, `.gitignore`,
`batch/README.md`, `batch/run-batch.sh`, `Agent.java` (11 comment lines, no
code), untracked `PHASE3_claude-code.md`. `git merge-tree` predicts
conflicts in `.gitignore` and `batch/README.md` only.

1. Fast-forward with the edits parked — no merge commit, no force-push:
   ```sh
   git stash push -u -m "phase3 harness edits 8-9 Oct"
   git merge --ff-only origin/selective-contact-reduction
   git stash pop
   ```
2. Resolve the two conflicts:
   - `.gitignore`: keep origin's `batch-runs/` rule once, add `Rplots.pdf`;
     drop the duplicate `/batch-runs/`.
   - `batch/README.md`: keep **both** sides. Origin's Phase 2 driver
     documentation and its Phase 3 alpha guidance stay; the local "Phase 3 —
     paired static/dynamic epidemics", "Running on another machine", "Known
     divergences" sections and the Open-list changes stay. Where origin's
     alpha guidance and the local "Purpose" paragraph say the same thing,
     merge them into one passage rather than keeping two. Show Leonard the
     resulting README before committing.
3. Read `batch/run-phase2.sh`, `batch/phase2.sh` and `batch/progress.sh`
   (they are how Runs A and B were actually launched — chunked, with an ETA
   monitor). Decide whether Phase 3 should run through the same driver:
   if `run-phase2.sh` is a thin wrapper that passes options through to
   `run-batch.sh`, add a `batch/run-phase3.sh` that does the same with the
   Phase 3 options (`--gamma-min 0.1 --gamma-max 0.2 --omega-random
   --ep-structure both --no-centralities`, 10,000 reps) and make Part B
   step 4 use it; if it hard-codes Phase 2 specifics, leave it and keep the
   bare `run-batch.sh` line, but say so in the report. Make sure the driver
   respects the `--ep-structure` override and the new `batch-info.txt`
   provenance (if it generates its own configs, the same sed override must
   be applied). Update the "Run" section of the README accordingly.
4. Verify `git diff origin/selective-contact-reduction -- src/` shows
   comment-only changes, then commit everything in one commit:
   `Harness: --ep-structure, portable classpath, provenance in batch-info; document Phase 3 and known divergences`
   (`batch-runs/`, `target/`, `*.log*`, `Rplots.pdf` stay ignored).
5. `git push origin selective-contact-reduction`. Report the pushed hash.

## Part B — on the compute machine

Prerequisites: Java **8** runtime and JDK (`java -version` → 1.8.x; the
Gephi toolkit jar is Java-8 only), Maven, POSIX `sh` with GNU `sed`/`awk`
(Linux, or Git Bash on Windows; on macOS install `gnu-sed` and put it first on
PATH), ≥ 1 GB RAM per shard, and a shell that survives for days
(`tmux`/`screen`/`nohup`). `.gitattributes` pins `*.sh` to LF endings; if
`sh: run-batch.sh: $'\r': command not found` appears anyway, run
`sed -i 's/\r$//' batch/run-batch.sh`.

1. Clone and build:
   ```sh
   git clone -b selective-contact-reduction https://github.com/lstell21/nidm-simulation-sel
   cd nidm-simulation-sel
   mvn install:install-file -Dfile=src/main/resources/gephi-toolkit-0.9.3.jar \
       -DgroupId=org.gephi -DartifactId=gephi-toolkit -Dversion=0.9.3 \
       -Dpackaging=jar -DgeneratePom=true
   mvn package -DskipTests
   ls target/nidm-4.0.1.jar target/classes
   ```
   If the jar name differs, pass `--jar` to the script.
2. Dry run — check the shard allocation and that the plan echoes
   `ep structure : both`, `gamma range : 0.1..0.2`, `omega : random`:
   ```sh
   ./batch/run-batch.sh --dry-run --reps 10000 --shards 16 \
       --gamma-min 0.1 --gamma-max 0.2 --omega-random --ep-structure both --no-centralities
   ```
   Set `--shards` to the number of physical cores if that is not 16; it must
   be ≥ 6.
3. Smoke test (minutes):
   ```sh
   ./batch/run-batch.sh --reps 2 --shards 6 --gamma-min 0.1 --gamma-max 0.2 \
       --omega-random --ep-structure both --no-centralities --out batch-runs/p3-smoke
   ```
   Verify, as listed in `batch/README.md` → "Pre-flight smoke test":
   `simulation-summary.csv` has `nb.ep.structure == both`, numeric
   `net.static.pct.rec` and `net.dynamic.pct.rec`, `nb.gamma` in [0.1, 0.2],
   `nb.phi` = 16/(N−1) per shard; `round-summary.csv` has, per `sim.cnt`, a
   `static` stretch followed by a `dynamic` stretch in `nb.ep.structure` and
   two `ACTIVE_EPIDEMIC` stretches in `sim.stage`; `batch-info.txt` holds the
   full command line and overrides; all `work/*/exit.code` are 0. A short
   `awk`/`python` check is enough — do not install R for this. Record the
   per-simulation wall time per N from `start.epoch`/`end.epoch` and compare
   with the "off" column of the centralities table (N = 320: 31 s/sim). If
   anything fails, stop and write it into the report; do not patch Java.
4. Full run through the chunked driver (Part A step 3 added a `p3` arm to
   `batch/run-phase2.sh` rather than a separate `run-phase3.sh`; README →
   "Chunked driver"). It runs 5 chunks × 2,000 reps per N with the Phase 3
   flags, detaches itself with `nohup`, and resumes after a reboot:
   ```sh
   SHARDS=16 ./batch/phase2.sh p3      # SHARDS = physical cores, >= 6
   ```
   Ctrl-C stops only the progress display. Re-attach or resume with the same
   command; one-off status with `./batch/progress.sh p3`; full log in
   `batch-runs/p3/driver.log` (each chunk's `run-batch.sh` output, including
   its collect table, is appended there). A chunk is complete only when
   `batch-runs/p3/c<i>/.done` exists. Expected wall clock: Phase 2 took
   ~2.5 days at K = 16 on a 7950X; the static arm adds less than that again
   — scale from the smoke-test timings.
5. When finished (`=== p3 complete: 60000 simulations across 5 chunks ===` in
   `driver.log`, five `c*/.done` files). There is no analysis repo next to the
   clone here, so the driver stages only (`analysis repo not found … staged
   only`); if one *is* present it installs into its `data/phase3/` and never
   touches `data/split`. Package the staged arm:
   ```sh
   cd batch-runs/p3
   ls c*/.done                                      # c1 … c5
   for f in merged/*/data/nunnerbuskens/simulation-summary.csv; do
       d=${f%%/data/*}; n=${d#merged/c*-n}; echo "${n%%-s*} $(( $(wc -l < "$f") - 1 ))"
   done | awk '{s[$1] += $2; t += $2} END {for (n in s) print "N=" n, s[n]; print "total", t}'
   tar czf ../p3-split.tgz merged provenance
   sha256sum ../p3-split.tgz
   ```
   Data rows must total 60,000 and be 10,000 per N level. Hand
   `p3-split.tgz` to the analysis machine; it is unpacked into
   `SelSWIDM-analysis/data/phase3/` with `merged/` renamed to `split/` (see
   README → "After the run"). Do not copy it into `data/split/` — that is
   Run A.
6. Write `PHASE3_REPORT.md` in the repository root on the compute machine
   (and paste it back to Leonard): STATUS line (done / stopped at step N),
   machine (`uname -a`, cores, `java -version`), commit hash built, dry-run
   plan, smoke-test checks with the actual values, per-N seconds per
   simulation from the smoke test, full-run start/end timestamps (first
   chunk's `started` and last chunk's `finished` in
   `provenance/c*-batch-info.txt`), any chunk that had to be redone
   (`driver.log`: `FAILED` / `INCOMPLETE`), per-shard exit codes and elapsed
   times from each chunk's collect table in `driver.log`, row counts per N,
   tarball SHA-256. Do not push data to GitHub (`data/` and `batch-runs/`
   are gitignored; the tarball is ~GBs).

## What happens next (not part of this brief)

`SelSWIDM-analysis` has to be made design-aware before the Phase 3 data can be
read: register the design in `DESIGNS`, let the model helpers take the outcome
column as an argument (`net.static.pct.rec` as the no-adaptation counterfactual
next to `net.dynamic.pct.rec`), and re-index round-summary time within the
dynamic phase. That work can start on the smoke-test output while the batch
runs; `assert_dynamic_only()` is the guard that will fail until it is done.
