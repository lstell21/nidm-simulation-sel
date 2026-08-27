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

```sh
# Phase 2 Run A -- reproduces the published design, regenerates draft Table 3
./batch/run-batch.sh --reps 20000 --shards 32 --encounters 16 --zeta 10 \
    --sigma-random --sigma-min 1.0 --sigma-max 3.0 \
    --gamma-min 0.1 --gamma-max 0.4 --omega-random --no-centralities

# Phase 2 Run B -- the extension. Identical except omega.
./batch/run-batch.sh ... --omega 0

# Phase 3 -- narrowed gamma, alpha stays U[0,1].
#   omega must match whichever run the anomaly figure is drawn from:
#   --omega 0 if Fig 3c comes from Run B, --omega-random if from Run A.
./batch/run-batch.sh ... --gamma-min 0.1 --gamma-max 0.2 --omega <match>

# Phase 4 -- extend the grid
./batch/run-batch.sh ... --ngrid 640,1280 --reps <scaled>

--dry-run     # print plan and shard allocation, run nothing
```

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

The committed config is post-preprint exploration (`c281878` onwards), not the
published design. Everything not listed already matches.

| | committed | published |
|---|---|---|
| `nb.sigma.random` / `.max` | `false` (pinned 2.0) / `100.0` | `true` / `3.0` |
| `nb.gamma.random.min` | `0.05` | `0.1` |
| `nb.n` | `10000` | `20000` |
| `nb.zeta` | `5` | `10` |
| `nb.N` | `80` | the six-level grid |
| `nb.phi` | `0.20` flat | per level |

### φ is a proportion, not a count

`Agent.getNumberOfNetworkDecisions()` returns `round((nodeCount - 1) * phi)`.
The manuscript specifies φ as a count of 16, "kept constant"; `APP_A:172` treats
it as a capacity. A flat `nb.phi=0.20` delivers that only at N=80:

| N | 80 | 160 | 240 | 320 | 400 | 480 |
|---|---|---|---|---|---|---|
| encounters at `nb.phi=0.20` | 16 | 32 | 48 | 64 | 80 | 96 |
| `nb.phi` for φ=16 | 0.202532 | 0.100629 | 0.066946 | 0.050157 | 0.040100 | 0.033403 |

`--encounters 16` sets this per shard. Use it: it is the documented design, and
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

## `--no-centralities` — use it

The round summary otherwise writes path length, betweenness and closeness — a
Dijkstra from every agent plus a Gephi pass, **every round**.
`SelSWIDM-analysis` reads only `net.assortativity.risk.perception` and
`net.clustering.av`, so none of them are used.

Measured A/B, identical recovered config, single shard, sequential:

| N | on | off | gain |
|---|---|---|---|
| 160 | 14.7 s/sim | 9.9 | 1.48× |
| 320 | 117.4 s/sim | 38.4 | 3.06× |

It changes the scaling exponent, not just the constant: **N^3.0 with, N^1.96
without**. One replication across N=80…480 drops from roughly 1058 s to ~217 s.
Projected from N=320: N=480 ≈ 85 s/sim, N=640 ≈ 149, N=1280 ≈ 581.

(Laptop, 4 P-core + 4 LP-E mobile chip. The exponent and ratio should transfer;
the absolute times will not.)

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
  (18 Jul 2024), which emits `nb.d`. If the published data predates that commit,
  the analysis needs porting to `nb.d` and draft Table 3 gets replaced rather
  than reproduced.
- **Cost.** Not yet measured against this config, and the laptop figures do not
  transfer (4 P-core + 4 LP-E mobile chip, 2.3× on 8 processes). Measure on the
  target machine before fixing replication volumes.
