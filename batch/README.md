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

# Phase 3 — narrowed gamma. alpha stays U[0,1]: Figure 3c IS the alpha x gamma
# crossover, and narrowing alpha would shrink the range it is read from.
# Draw it from Run A, so omega stays random.
./batch/run-batch.sh --reps 10000 --shards 16 \
    --gamma-min 0.1 --gamma-max 0.2 --omega-random --no-centralities

# Phase 4 (optional) — extend the grid. ~2.8 days at 1000 reps; 5000 reps would
# make N=1280 alone 12+ days.
./batch/run-batch.sh --reps 1000 --shards 16 --ngrid 640,1280 \
    --omega-random --no-centralities

--dry-run     # print plan and shard allocation, run nothing
```

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

## Open

- **`nb.d1` vs `nb.d`.** The analysis regresses on `nb.d1` and builds its
  descriptives from `nb.d1` and `nb.d2`; `_targets.R` plots `pred = "nb.d1"` for
  the manuscript's Figures 1a/1b. None of those exist after `3ad9972`
  (18 Jul 2024), which emits `nb.d`. Both Phase 2 runs are regenerated from this
  branch, so they carry `nb.d`: the analysis needs porting either way, and draft
  Table 3 is replaced rather than reproduced. No longer conditional.
- **Phase 3 alpha range.** Gamma narrowing is settled at U[0.1, 0.2]. Alpha
  stays U[0,1] — see the Phase 3 run line for why.

Closed: cost is now measured (see above); phi is ratified as a constant 16.
