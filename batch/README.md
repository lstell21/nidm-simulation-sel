# Batch simulation harness

Runs NunnerBuskens Monte Carlo batches and writes them in the layout
`SelSWIDM-analysis` consumes.

## Setup (once)

`gephi-toolkit` is not on Maven Central — a fresh clone silently resolves a 4 KB
stub and then dies with `UnsupportedClassVersionError` on Java 8:

```sh
mvn install:install-file -Dfile=src/main/resources/gephi-toolkit-0.9.3.jar \
    -DgroupId=org.gephi -DartifactId=gephi-toolkit -Dversion=0.9.3 \
    -Dpackaging=jar -DgeneratePom=true
mvn package -DskipTests
```

## Run

`config.properties` now carries the Table 1 design as its default (sigma, gamma,
zeta, and phi via `--encounters 16`), so the run lines only need to say what
differs between runs.

```sh
# Phase 2 Run A — omega ~ U[0,1]. A re-run, NOT the published data: the published
# batch used a flat nb.phi, so it is not comparable at N > 80. See "phi" below.
./batch/run-batch.sh --reps 10000 --shards 16 --omega-random --no-centralities

# Phase 2 Run B — the isolating run. Identical except omega.
./batch/run-batch.sh --reps 10000 --shards 16 --omega 0 --no-centralities

# Phase 3 — paired static/dynamic epidemics, gamma narrowed to U[0.1,0.2],
# alpha left at U[0,1], omega random as in Run A. Why each of those: "Phase 3 ->
# Purpose" below. The same sample as this single call...
./batch/run-batch.sh --reps 10000 --shards 16 \
    --gamma-min 0.1 --gamma-max 0.2 --omega-random --ep-structure both --no-centralities
# ...but launch it through the chunked driver (next section), which runs it as
# 5 x 2000 with resume:
./batch/phase2.sh p3
# See "Phase 3" below for what a BOTH batch writes, the pre-flight smoke test,
# and why the analysis repo's readers must be extended before it can be read.

# Phase 4 (optional) — extend the grid. ~2.8 days at 1000 reps; 5000 reps would
# make N=1280 alone 12+ days.
./batch/run-batch.sh --reps 1000 --shards 16 --ngrid 640,1280 \
    --omega-random --no-centralities

--dry-run     # print plan and shard allocation, run nothing
```

### Chunked driver (how Runs A and B were launched; Phase 3 uses it too)

Runs A and B were not launched with the bare lines above but through the
chunked driver, because `run-batch.sh` has no resume and the Windows box
restarts for updates. Phase 3, at several days, goes the same way:

```sh
./batch/phase2.sh runA    # starts batch-runs/runA detached, or re-attaches/resumes
./batch/phase2.sh runB
./batch/phase2.sh p3      # omega random, gamma U[0.1,0.2], --ep-structure both
./batch/progress.sh p3    # one-off progress snapshot without attaching
```

| arm | flags passed to `run-batch.sh` (plus `--no-centralities`) | installs into `<SelSWIDM-analysis>/` |
|---|---|---|
| `runA` | `--omega-random` | `data/split`, **replacing** it; clears `data/*.csv` and `_targets` |
| `runB` | `--omega 0` | same as `runA` |
| `p3` | `--omega-random --gamma-min 0.1 --gamma-max 0.2 --ep-structure both` | `data/phase3/split` + `data/phase3/provenance`; **deletes nothing**, and refuses (exit 1) if `data/phase3/split` exists and is not empty |

`run-phase2.sh` (started detached by `phase2.sh`) runs the arm as `CHUNKS` ×
`REPS` (default 5 × 2,000 per N) calls to `run-batch.sh` under
`batch-runs/<arm>/c<i>/`, stages every chunk's shard directories as
`batch-runs/<arm>/merged/c<i>-n<N>-s<k>`, and keeps each chunk's
`batch-info.txt`, `shard-list.txt` and `config.properties.source` as
`batch-runs/<arm>/provenance/c<i>-*`. Chunks are independent samples (the model
is never seeded), so 5 × 2,000 is the same dataset as 1 × 10,000. The driver
writes no configs of its own: `--ep-structure`, the γ/ω overrides and the
`batch-info.txt` provenance all come from `run-batch.sh`, per chunk.
`INSTALL=0`, or no analysis repo at `ANALYSIS` (default
`../SelSWIDM-analysis`), stages only and logs the `cp` line to install by
hand. `progress.sh <arm>` prints per-shard progress and a slowest-shard ETA.

**Resume.** A chunk is complete only if `batch-runs/<arm>/c<i>/.done` exists.
`.done` is written last, after `run-batch.sh` returned 0, every shard listed in
the chunk's `shard-list.txt` left an `exit.code` and all of them are 0, and the
chunk's shard directories and provenance files were staged. Re-running
`./batch/phase2.sh <arm>` (after a reboot, say) skips chunks with `.done`,
deletes a chunk directory without one along with its staged `c<i>-*` entries,
and re-runs that chunk from scratch. At most one chunk is lost.

### Replication volume

10,000 per level, decided 27 Aug 2026. That is ~2.5 days per Phase 2 run at
K=16, so ~5 days for both, against ~10 days at 20,000. After the 20.9% exclusion
it leaves ~47,400 usable observations, putting the `s` coefficient at roughly
5 SEs — a sqrt(2) precision loss on the one effect that was ever marginal, for
half the compute. Exact comparability with the published 94,881 is unavailable at
any volume anyway, because the phi design differs.

Then:

```sh
cp -r <out>/split/* <SelSWIDM-analysis>/data/split/
```

`read_and_merge_csvs()` merges the directories itself, reads `nb.N` from each
one's `config.properties`, and applies the exclusion
(`net.pathlength.pre.epidemic.av < 100`). Nothing else to do.

## Phase 3 — paired static/dynamic epidemics at γ ∈ [0.1, 0.2]

### Purpose

Runs A and B compare *selective* with *random* contact reduction; neither
contains a network in which nobody reduces contacts. `nb.ep.structure=both`
supplies that counterfactual within the same run: the generator grows the
pre-epidemic network, seeds one index case, runs the epidemic once on the
**frozen** network (no tie formation or dissolution while an infection is
active — `Simulation.java:300`), resets the disease states, and then runs it
again from the **same index case on the same network** with the network
dynamic (`NunnerBuskensDataGenerator.java:464-475`). Each simulation therefore
yields a paired outcome: `net.static.pct.rec` (no adaptation) against
`net.dynamic.pct.rec` (adaptation, selective or random according to `s`).
The static arm does not depend on `s` (selection acts only while an infection
is active, and the frozen network has no tie decisions), so the pairing isolates
(i) the effect of reducing contacts at all and (ii) the increment of doing so
selectively, inside one network rather than across independent draws.

γ is narrowed to U[0.1, 0.2] because the α × γ interaction the paper has to
explain lives at low γ; 10,000 outbreaks per N inside that band give three
times the density Run A has there. α stays U[0, 1] because that interaction is
read along α, and its shape depends on the model it is read through. The
preprint's linear α × γ specification (Figure 3c) gives a γ = 0.1 curve that
rises from ~0.16 at α = 0 to ~0.32 at α = 1 and crosses the other γ curves near
α ≈ 0.87 (the reading recorded here on 28 Aug 2026). The current manuscript's
spline model and binned estimates (Figure 5(c), Figure 8, Appendix Fig. B.8)
show instead a peak at α ≈ 0.4–0.5 for γ ≤ 0.25 (binned, γ 0.10–0.15:
17.0 % → 37.6 % → 7.0 %). The design decision is the same under both: γ in
[0.1, 0.2] with α left at U[0, 1] — the α ~ U[0, 0.3] first planned would miss
the high-α crossover of the one reading and the peak and decline of the other.
Phase 3 then measures the shape directly: the static arm traces outbreak size
along α with no contact adaptation, on the same networks as the dynamic arm.
ω stays random (as Run A) so the ω gradient can be re-read with the static
counterfactual alongside.

### What a BOTH batch writes

| file | change against a dynamic batch |
|---|---|
| `simulation-summary.csv` | `nb.ep.structure` is `both` in every row. The `net.static.*` block (`net.static.pct.rec`, `net.static.epidemic.duration`, `net.static.epidemic.peak.size`, `net.static.av.clustering.post`, …) is populated instead of empty; `net.dynamic.*` as before. `net.*.pre.epidemic.*` describes the one shared pre-epidemic network. |
| `round-summary.csv` | `nb.ep.structure` is `static` or `dynamic` **per round** (`NunnerBuskensRoundSummaryWriter.java:79`). Every `sim.cnt` has two `ACTIVE_EPIDEMIC` stretches in `sim.stage`: the static one directly after the burn-in, the dynamic one directly after the static one ends (no post-epidemic phase in between; `sim.round` keeps counting). The dynamic outbreak therefore does **not** start at round ζ+1 = 11. |
| `config.properties` (per shard) | `nb.ep.structure=both` |

What this means for `SelSWIDM-analysis`: `assert_dynamic_only()` in
`R/00_data-wrangling.R` stops on any value other than `dynamic`, by design.
Before Phase 3 data can be read, the analysis needs (1) a new entry in
`DESIGNS` (e.g. `p3 = list(split = "./data/phase3/split", prefix = "./data/phase3/")`
with the structure named), (2) an outcome switch in the model-fitting helpers
so `net.static.pct.rec` can be modelled alongside `net.dynamic.pct.rec`, and
(3) round-summary helpers that take the phase from the per-round
`nb.ep.structure` column and re-index time within the dynamic phase
(`sim.round − first dynamic ACTIVE_EPIDEMIC round + ζ`) instead of assuming
one active-epidemic stretch per `sim.cnt`. None of this touches the Java.

### Pre-flight smoke test (do this before the 3-day run)

```sh
./batch/run-batch.sh --reps 2 --shards 6 --gamma-min 0.1 --gamma-max 0.2 \
    --omega-random --ep-structure both --no-centralities --out batch-runs/p3-smoke
```

Then confirm, on `batch-runs/p3-smoke/split/n80-s1/data/nunnerbuskens/`:

1. `simulation-summary.csv`: 2 rows; `nb.ep.structure == both`;
   `net.static.pct.rec` and `net.dynamic.pct.rec` both numeric and generally
   different; `nb.gamma` within [0.1, 0.2]; `nb.phi` = 0.202532 at N = 80.
2. `round-summary.csv`: per `sim.cnt` (rows where `sim.round == 1` start a new
   simulation), the sequence of `nb.ep.structure` is `static…` then
   `dynamic…`; `sim.stage` shows two `ACTIVE_EPIDEMIC` stretches.
3. `batch-info.txt` in the run root records the full command line, the
   ep-structure/γ/ω overrides, and the git commit the jar was built from.

Record the per-simulation wall time from `work/*/shard.log` or
`start.epoch`/`end.epoch` and compare with the "off" column of the
centralities table below (N = 320: 31 s/sim). A BOTH run adds one static
epidemic per simulation; the static arm skips all network decisions, so the
expected overhead is well under 2× — measure it, and scale `--reps` or accept
the longer wall clock accordingly.

### After the run

If `phase2.sh p3` ran on the analysis machine itself, the driver has already
installed the data into `data/phase3/split` and `data/phase3/provenance`.
Otherwise (compute machine, no analysis repo next to the clone) it stages
only; package the staged arm and unpack it on the analysis machine:

```sh
# on the compute machine:
tar czf batch-runs/p3-split.tgz -C batch-runs/p3 merged provenance
# on the analysis machine (data/phase3/split must not exist yet):
A=<SelSWIDM-analysis>
[ ! -e "$A/data/phase3/split" ] && mkdir -p "$A/data/phase3" &&
    tar xzf p3-split.tgz -C "$A/data/phase3" &&
    mv "$A/data/phase3/merged" "$A/data/phase3/split"
```

Never into `data/split` — that is Run A. `read_and_merge_csvs()` merges the
`c<i>-n<N>-s<k>` directories itself once the design is registered. Keep
`provenance/` with the data: each chunk's `batch-info.txt` is the provenance
record (commit, platform, command line, overrides, start/finish).

## Running on another machine

Clone from `origin`, never copy a working tree: `batch-info.txt` records the
commit the jar was built from, and that hash is only meaningful if it is on
`origin`. (On 9 Oct 2026 the laptop copy was five commits behind origin with
uncommitted harness edits; it was fast-forwarded, the edits re-applied and
pushed before Phase 3 was launched.)

On the target (Linux or Windows/Git Bash; macOS needs GNU sed):

```sh
git clone -b selective-contact-reduction https://github.com/lstell21/nidm-simulation-sel
cd nidm-simulation-sel
java -version    # must report 1.8.x: the sources target Java 8 and the Gephi toolkit jar is Java-8 only
mvn -version
mvn install:install-file -Dfile=src/main/resources/gephi-toolkit-0.9.3.jar \
    -DgroupId=org.gephi -DartifactId=gephi-toolkit -Dversion=0.9.3 \
    -Dpackaging=jar -DgeneratePom=true
mvn package -DskipTests
ls target/nidm-4.0.1.jar target/classes
./batch/run-batch.sh --dry-run --reps 10000 --shards 16 \
    --gamma-min 0.1 --gamma-max 0.2 --omega-random --ep-structure both --no-centralities
```

`run-batch.sh` picks the classpath separator from `uname`, records the
platform in `batch-info.txt`, and copies the source `config.properties` next
to it. Launch the full run with `./batch/phase2.sh p3` (set `SHARDS=<physical
cores>` in the environment if that is not 16; it must be ≥ 6). The driver
detaches itself with `nohup`, so closing the window or Ctrl-C stops only the
progress display; after a reboot, re-run the same command to resume (see
"Chunked driver"). A bare `run-batch.sh` call, by contrast, needs a shell that
survives the whole run (`nohup`/`tmux`/`screen`) and loses everything on a
restart. `--shards` / `SHARDS` should not exceed the number of physical cores
(see "Why it shards").

## Published configuration

Recovered from `40_simulation.tex` Table 1 unless noted. Independently confirmed
by the appendix descriptives (`APP_B`): σ M=2.00/SD=0.58, γ M=0.25/SD=0.09,
d and ω M≈0.50/SD=0.29, and 47,231 + 47,650 = 94,881.

| Parameter | Value | `config.properties` |
|---|---|---|
| `b₁` / `b₂` | 1.00 / 0.50 | `nb.b1` / `nb.b2` |
| `c₁` / `c₂` | 0.20 / 0.05 | `nb.c1` / `nb.c2` |
| `α` | U[0,1] | `nb.alpha.random=true`, 0.0–1.0 |
| `d` | U[0,1] | `nb.d.random=true`, 0.0–1.0 |
| `r` | N(1.22, 0.46) truncated | hardcoded in generator |
| `N` | {80,160,240,320,400,480} | `nb.N`, one level per run |
| `φ` | 16 encounters, constant | `nb.phi`, per level — see below |
| `ψ` / `ξ` | 0.40 / 0.20 | `nb.psi` / `nb.xi` |
| `ω` | U[0,1] | `nb.omega.random=true`, 0.0–1.0 |
| `s` | Bernoulli(0.5) | `nb.selective.random=true` |
| `σ` | U[1.0, 3.0] | `nb.sigma.random=true`, 1.0–3.0 |
| `γ` | U[0.1, 0.4] | `nb.gamma.random=true`, 0.1–0.4 |
| `τ` | 5 | `nb.tau=5` |
| epidemic structure | dynamic | `nb.ep.structure=dynamic` |
| outbreaks per N | 20,000 | `nb.n=20000` |
| burn-in | 10 time steps | `nb.zeta=10` |

Burn-in source: `50_analysis.tex:5`, `60_results.tex:18`, `APP_A:73,96`.
6 × 20,000 = 120,000 runs, minus 25,119 disconnected = 94,881. Exclusion 20.9%.

### Deltas from the committed `config.properties`

The config as inherited was post-preprint exploration (`c281878` onwards), not
the published design. These are now fixed in `config.properties` itself, so the
corresponding flags are no longer load-bearing — every one of them defaulted to
empty in `run-batch.sh`, and a forgotten flag diverged from Table 1 silently.

| | was | now | fixed in |
|---|---|---|---|
| `nb.sigma.random` / `.max` | `false` (pinned 2.0) / `100.0` | `true` / `3.0` | config |
| `nb.gamma.random.min` | `0.05` | `0.1` | config |
| `nb.zeta` | `5` | `10` | config |
| `nb.phi` | `0.20` flat | 16/(N-1) per level | `--encounters`, now default 16 |
| `nb.n` | `10000` | per run | `--reps` |
| `nb.N` | `80` | one level per shard | `--ngrid` |

`nb.N` deliberately stays a single value in the source config: the analysis
greps `nb.N=` from each run directory, so a grid there yields `NA` silently.

### φ is a proportion, not a count

`Agent.getNumberOfNetworkDecisions()` returns `round((nodeCount - 1) * phi)`.
The manuscript specifies φ as a count of 16, "kept constant"; `APP_A:172` treats
it as a capacity. A flat `nb.phi=0.20` delivers that only at N=80:

| N | 80 | 160 | 240 | 320 | 400 | 480 |
|---|---|---|---|---|---|---|
| encounters at `nb.phi=0.20` | 16 | 32 | 48 | 64 | 80 | 96 |
| `nb.phi` for φ=16 | 0.202532 | 0.100629 | 0.066946 | 0.050157 | 0.040100 | 0.033403 |

`--encounters 16` sets this per shard, and is now the **default** in
`run-batch.sh` rather than opt-in. Constant phi was ratified as the design on
27 Aug 2026: it is what Table 1 documents, and
the choice is low-risk either way — measured at N=480, 40 runs per arm, the two
regimes are statistically indistinguishable (disconnected 22.5% vs 32.5%,
z=1.00, p=0.32; mean degree 7.69 vs 7.82). Agents converge to the ~8-tie optimum
regardless; extra candidates only speed convergence to the same structure.

## Why it shards

1. `NunnerBuskensDataGenerator.generate()` has no threading — one process, one core.
2. The analysis reads N by grepping `nb.N=` from each run's `config.properties`,
   so **each run must hold exactly one N**. A config with the whole grid gives
   `as.numeric("80,160,...")` → `NA` silently. Six levels means six runs
   regardless of parallelism.

Shards are allocated across levels in proportion to cost (`--cost-exp` to tune);
the batch finishes when its slowest shard does.

Measured scaling, 32 simulations at N=320, centralities off, 1g heap per shard:

| shards | wall | speed-up | efficiency |
|---|---|---|---|
| 1 | 884 s | 1.00× | 100% |
| 2 | 511 s | 1.73× | 87% |
| 4 | 247 s | 3.58× | 90% |
| 8 | 133 s | 6.65× | 83% |
| 16 | 92 s | 9.61× | 60% |
| 32 | 90 s | 9.82× | 31% |

Past 16 you are on SMT siblings and the work is memory-bandwidth-bound, so K=32
buys 2%. **K=8 is the efficiency choice, K=16 the wall-clock choice; nothing
above 16 is worth the core-hours.** Running 10-wide rather than serially costs a
roughly flat 1.25-1.47× contention tax, which shifts the cost curve without
tilting it.

## `--no-centralities` — use it

The round summary otherwise writes path length, betweenness and closeness — a
Dijkstra from every agent plus a Gephi pass, **every round**.
`SelSWIDM-analysis` reads only `net.assortativity.risk.perception` and
`net.clustering.av`, so none of them are used.

Measured on a Ryzen 9 7950X (16C/32T, 63 GB), contention-free serial control,
startup-corrected, 3 reps per point, uniform 3g heap:

| N | off (s/sim) | on (s/sim) | gain |
|---|---|---|---|
| 80 | 0.67 | — | — |
| 160 | 4.00 | 6.33 | 1.58× |
| 240 | 10.67 | — | — |
| 320 | 31.00 | 59.00 | 1.90× |
| 400 | 55.67 | — | — |
| 480 | 107.33 | 203.67 | 1.90× |

**It is a constant factor, not a change in complexity class.** Least-squares fits
put both arms near cubic — off 3.02 (R²=0.995, N≥160), on 3.17 (R²=0.9998) --
and the two curves run parallel on log-log axes. One replication across
N=80…480 costs 209 s with centralities off. Keep the trim: 1.6–1.9× is worth
having.

Earlier revisions of this file claimed N^1.96 off against N^3.0 on, and a 3.06×
gain at N=320. Those were two-point fits taken on a 4 P-core + 4 LP-E mobile
chip and did not reproduce. `--cost-exp 3.1` was right by luck and stays.

Budget large-N work at cubic. Projected from the N=480 off-arm measurement:
N=640 ≈ 255 s/sim, N=1280 ≈ 2,050 s/sim (~34 minutes each).

Do **not** use `--no-round-summary` instead — that removes the whole file and
breaks the C1 figures. Controlled by `export.summary.each.round.centralities`,
which defaults to `true` when absent, so the CIDM writer is unaffected.

A further trim is available but low value: `net.betweenness.pre.epidemic.av`,
`net.closeness.pre.epidemic.av` and the index-case centralities in the
*simulation* summary are also unread. That is one Gephi pass per simulation
rather than per round — worth roughly 7% at N=320, against a change to the main
summary schema.

## Known divergences from the manuscript algorithms

- **`Agent.java` line 1076 (line 1086 since the explanatory comment block was
  added on 8 Oct 2026) removes from the wrong list.** The statement reads
  `allAgentsAssorted.removeAll(distance2AgentsShuffled);` where
  `allAgentsShuffled.removeAll(distance2AgentsShuffled);` was evidently intended
  (lines 1073-1076 build the shuffled pool; line 1071 already stripped the
  distance-2 agents from the assorted one). Consequence: in the non-assorted
  branch (`randOmega > omega`) the "random others" pool still contains
  second-degree neighbours, while the assorted pool has them removed twice.
  Effect: the effective ξ is slightly above 0.20 in the random branch, and the
  encounter-set composition depends weakly on ω. Runs A and B (2 Sep 2026) and,
  if inherited from `hnunner/nidm-simulation`, the preprint batch were generated
  with this behaviour. Decision 8 Oct 2026: document, do not change, so that
  Phase 3 stays comparable with Runs A and B. A matching comment sits above the
  statement in `Agent.java`.
- **Encounter category is drawn per decision, not as Binomial counts.** The
  code draws one category per network decision with probabilities ψ, ξ and
  1−ψ−ξ (`randPsi` at `Agent.java` 1116/1125/1134) and falls through to "all
  agents" when the chosen list is empty, whereas manuscript Algorithm 5 draws
  Binomial(φ, ψ) and Binomial(φ, ξ) counts up front. The two are the same in
  expectation but not in realisation (the per-decision draw has larger
  variance in the category counts and the empty-list fall-through shifts mass
  toward "all agents" for sparsely connected agents).
- **`Agent.java` line 1123 (now 1134) duplicates a condition.** The test reads
  `(randPsi > psi+xi) && (randPsi > psi+xi)`; the second conjunct repeats the
  first. Harmless — it evaluates identically to the single condition.

## Open

- **Confirm the preprint's φ design from Hendrik's run directories.** Confirm
  from Hendrik's run directories that the preprint batch used flat
  `nb.phi = 0.20`. This README currently states it as fact (Run A comment,
  Deltas table), but the claim is "most likely" at best: it rests on the
  committed `config.properties`, not on the preprint's own run configs.
- **`nb.d1` vs `nb.d`.** The analysis regresses on `nb.d1` and builds its
  descriptives from `nb.d1` and `nb.d2`; `_targets.R` plots `pred = "nb.d1"` for
  the manuscript's Figures 1a/1b. None of those exist after `3ad9972`
  (18 Jul 2024), which emits `nb.d`. Both Phase 2 runs are regenerated from this
  branch, so they carry `nb.d`: the analysis needs porting either way, and draft
  Table 3 is replaced rather than reproduced. No longer conditional.
- **Phase 3 readers.** `SelSWIDM-analysis` cannot read a BOTH batch yet
  (see "Phase 3 — what a BOTH batch writes"). The reader work can proceed on
  the smoke-test output while the full batch runs.
- **Phase 3 adaptivity measure.** The Discussion's explanation, that tightly
  knit structures hamper contact adjustment and let disease persist locally,
  is testable from data already collected: sim.stage marks the active-epidemic
  window, sim.cnt joins to gamma, and degree/clustering/homophily are recorded
  per round. No new instrumentation needed, but the measure is not yet a
  target in SelSWIDM-analysis. In a BOTH batch the window is the *dynamic*
  `ACTIVE_EPIDEMIC` stretch, not the first one (see the round-summary row of
  the table above).
- **Phase 3 cost.** Not yet measured; the smoke test gives it. Budget
  < 2× a Phase 2 run (~2.5 days at K = 16) until then.

Closed: cost of Phase 2 is measured (see above); phi is ratified as a constant
16; Phase 3 alpha range settled at U[0,1], gamma at U[0.1, 0.2].
