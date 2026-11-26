# Codebook of the simulation output

Prepared by Claude Science (13 November 2026, updated 26 November 2026). It describes the CSV files that the final
build writes: commit `70dcf43` on branch `rerun-fixes`, batch jar SHA-256 `c4759c0d…`, bundle
`selcor-final-70dcf43`. The data deposit holds the output of the final batches `main`, `w0`,
`tie1` and `tie2`, and of the recording check. Every column below was taken from that output, in
file order, and checked against the code that writes it.

Sources are given as file:line at `70dcf43`, with these abbreviations (all under
`src/main/java/nl/uu/socnetid/nidm/`):

| abbreviation | file |
|---|---|
| SSR | `io/csv/NunnerBuskensSimulationSummaryWriterReduced.java` (writes `simulation-summary.csv`) |
| RSW | `io/csv/RoundSummaryWriter.java` (writes `round-summary.csv`, common columns) |
| NBR | `io/csv/NunnerBuskensRoundSummaryWriter.java` (writes `round-summary.csv`, model columns) |
| TEL | `io/csv/TieEventLog.java` (writes `tie-events.csv` and `transmissions.csv`) |
| GEN | `io/generator/data/NunnerBuskensDataGenerator.java` (runs a simulation and fills the values) |

Symbols are those of the paper (parameter table in the Simulation section; Supplement Table S2).

## 1. How a run proceeds

Every run builds one network of N agents, starting with no ties. It then runs these stages, each
made of rounds (time steps):

1. **Burn-in** (`pre-epidemic`): `nb.zeta` rounds of tie revision without disease. In the final
   batches this is 30 rounds. The network is never tested for stability, so the burn-in always
   runs exactly that many rounds.
2. **Outbreak** (`active-epidemic`): one agent, the index case, is chosen at random before the
   burn-in (GEN:485) and infected when the outbreak starts. Rounds run until no agent is infected
   any more. The round in which the last infected agent recovers is labelled `stopped-epidemic`.
3. **After the outbreak** (`post-epidemic`): `nb.zeta.post` rounds of tie revision, 10 in the
   final batches.

In the paired design (`nb.ep.structure` = `both`) the same network and index case go through two
outbreaks. First comes the frozen arm, in which ties do not change during the outbreak
(`static`). Then the network is reset to the tie list it had at the start of that outbreak, and
the adapting arm runs (`dynamic`), followed by the stage after the outbreak. None of the
deposited batches uses the paired design: all of them are `dynamic` and run only the adapting arm.

Rounds are counted over the whole run, starting at 1 with the first burn-in round. The same
numbering appears in `round-summary.csv`, `tie-events.csv` and `transmissions.csv`
(`sim.round`).

## 2. Files and format

### Layout

Each batch unpacks to:

```
split/<shard>/config.properties
split/<shard>/data/nunnerbuskens/simulation-summary.csv
split/<shard>/data/nunnerbuskens/round-summary.csv
split/<shard>/data/nunnerbuskens/tie-events.csv        (tie1, tie2 and recording check only)
split/<shard>/data/nunnerbuskens/transmissions.csv     (tie1, tie2 and recording check only)
batch-info.txt
shard-list.txt
config.properties.source
```

- **Shards.** A shard is one Java process that ran a set of runs at a single network size.
  - **`n<N>-s<k>`:** the k-th shard at network size N, as `batch/run-batch.sh` names it. For
    example, `n240-s3` is the third shard with N = 240.
  - **`t-<cell>-s<k>`:** a shard of a top-up job, run later on the cluster with the same bundle
    and settings and merged into the batch. The cell is `n<N>`, followed by a letter when several
    top-up jobs ran at the same N; for example, `t-n400b-s3` is shard 3 of the second top-up job
    at N = 400.
  - Merged batches carry `MERGE-INFO.txt`, written by the merge script, not by the build. It lists
    the parts, the runs per shard and the incomplete runs that were dropped.
  - Runs are unseeded, so every shard is an independent sample from the same design.
- **`split/<shard>/config.properties`:** the full configuration that shard ran with (written by
  `run-batch.sh` from the tracked configuration).
  - **The CSV files have no column for N.** The analysis reads `nb.N=` from this file.
  - Other keys that describe the run: `nb.n` (runs in the shard), `nb.phi` (16 / (N − 1), so
    that every agent has 16 encounters per round), `nb.zeta` (burn-in rounds), `nb.zeta.post`,
    `nb.fix.order`, `nb.fix.d2`, `nb.ep.structure`, and the ranges of the parameters drawn per
    run (`nb.<parameter>.random.min` and `.max`).
- **`batch-info.txt`:** provenance of the batch or part, one `key : value` per line:
  - git commit, branch, number of modified files, bundle name and jar SHA-256;
  - Java version and JVM options;
  - N grid, runs per N and number of shards;
  - the batch options (omega, gamma and alpha ranges, encounters, zeta, zeta post, fix order,
    fix d2, tie events);
  - start and end time, and the Slurm job and node.
- **`shard-list.txt`:** one line per shard: `<shard> <N> <runs>`.
- **`config.properties.source`:** the tracked configuration that the shard configurations were
  made from.
- **The recording check** (`recording-check.tgz`) holds two such batch folders, `on/` (tie events
  recorded) and `off/`, plus the launch logs and `finalsize.csv`. That file holds the input of the
  check's KS tests (`arm,selective,final.size`, comma-separated), was written by the check
  script, and is not covered further here.

### Format of the four CSV files

- **Structure:** separator `;`; one header row; no quoting; lines end in LF.
- **Numbers:** decimal point `.`, independent of the locale (Java `String.valueOf`). Decimal
  numbers use Java's shortest form, so values below 0.001 are written in E-notation (for example
  `3.5E-4`). Counts are integers, except `index.degree`, which is written with one decimal
  (`8.0`).
- **Logical values:** `true` or `false`, except `net.stable.pre` and `nb.rs.equal`, which are
  `1` or `0`.
- **Missing values:**
  - `NA` where a column does not apply: the eleven `net.static.*` columns in every deposited
    batch, `distance.after` for form events, and the infector columns if an infection had no
    infected neighbour (does not occur).
  - `NaN` where a computation is undefined: a correlation without variance, or a mean over no
    neighbours. None occurred in the files checked for this codebook.
- **Keys:** `sim.uid` is unique only within one shard folder. A run is identified by shard folder
  and `sim.uid`. Within a shard, `sim.cnt` numbers the runs 1, 2, …
- **Constant columns:** columns that are constant in the deposited batches are marked "constant"
  in the tables. Section 7 lists them, with the columns the deposited batches do not use.

## 3. `simulation-summary.csv`

One row per run, written when the run is complete (GEN:523). 57 columns in every deposited batch.

- **"At the start of the outbreak":** after the burn-in and the infection of the index case,
  before the first outbreak round (GEN:585-589).
- **"Frozen arm" and "adapting arm":** the paired design's two outbreaks (Section 1). The
  `net.dynamic.*` columns describe the outbreak of the deposited batches (the adapting arm). The
  `net.static.*` columns would describe a frozen arm; no deposited batch has one, so they are
  `NA`.

| # | column | meaning | type, unit | symbol | source |
|---|---|---|---|---|---|
| 1 | `sim.uid` | Run identifier `<sim.upc>#<sim.cnt>#<sim.it>`; unique within a shard folder. | text | | SSR:166 |
| 2 | `sim.upc` | Number of the parameter combination. Every parameter that varies is drawn per run, so this is 1 in every run. Constant. | count | | SSR:167 |
| 3 | `sim.cnt` | Number of the run within the shard (1, 2, …). | count | | SSR:168 |
| 4 | `sim.it` | Repetition of the same drawn parameters; 1 in every run. Constant. | count | | SSR:169 |
| 5 | `nb.ep.structure` | Design: `dynamic` (adapting arm only) in every deposited batch. The code also has `both`, the paired design (Section 1), which no deposited batch uses. Constant. | text | | SSR:171 |
| 6 | `nb.alpha` | Preferred proportion of closed triads, drawn per run, U[0, 0.9]. | 0–1 | α | SSR:173 |
| 7 | `nb.omega` | Likelihood that an encounter is drawn by similarity in risk perception, drawn per run, U[0, 1]; 0 in w0 and tie2. | 0–1 | ω | SSR:174 |
| 8 | `nb.selective` | Whether the agents of this run are selective during an outbreak; drawn per run, Bernoulli(0.5), the same for all agents. | true/false | s | SSR:175 |
| 9 | `nb.d` | Weight of local over global perceived infection risk, drawn per run, U[0, 1]. | 0–1 | d | SSR:176 |
| 10 | `nb.sigma` | Disease severity, drawn per run, U[1, 3]. | ≥ 1 | σ | SSR:177 |
| 11 | `nb.gamma` | Infectivity: transmission probability per contact and round, drawn per run; U[0.1, 0.4] in main, w0, tie2; U[0.1, 0.2] in tie1. | 0–1 | γ | SSR:178 |
| 12 | `nb.r.min` | Smallest risk perception among the run's N agents. Each agent draws r from N(1.2237, 0.4625) truncated to [0.4474, 2.0]; perceived severity and perceived infectivity are equal (r_σ = r_π). | 0.45–2.0 | r | SSR:179 (GEN:421) |
| 13 | `nb.r.max` | Largest risk perception among the run's agents. | 0.45–2.0 | r | SSR:180 (GEN:422) |
| 14 | `nb.r.sigma.av` | Mean risk perception of the run's agents. | 0.45–2.0 | r | SSR:181 (GEN:424) |
| 15 | `net.degree.pre.epidemic.av` | Mean number of ties per agent at the start of the outbreak. | ties per agent | D_G | SSR:185 |
| 16 | `net.clustering.pre.epidemic.av` | Clustering at the start of the outbreak: mean of the agents' local clustering coefficients (GraphStream `Toolkit.averageClusteringCoefficient`). | 0–1 | C_G | SSR:186 |
| 17 | `net.pathlength.pre.epidemic.av` | Mean shortest-path length over all ordered pairs of agents at the start of the outbreak. A pair without a path counts as 2,147,483,647 (Java `Integer.MAX_VALUE`), so any disconnected network gets a very large value; the analysis treats values ≥ 100 as disconnected (Network.java:1524-1551). | ties (path length) | | SSR:187 |
| 18 | `net.betweenness.pre.epidemic.av` | Mean normalized betweenness at the start of the outbreak: shortest paths through an agent divided by ((N − 1) / 2)(N − 2), averaged over agents (Network.java:1197, Agent.java:809). Computed although the batches run with `--no-centralities`, which only removes columns from the round summary. | 0–1 | | SSR:188 |
| 19 | `net.closeness.pre.epidemic.av` | Mean closeness at the start of the outbreak, as in Buechel and Buskens (2013): M/(M − 1) − Σd / ((M − 1)(N − 1)) with M = N, where an unreachable agent counts as distance N (StatsComputer.java:86-112). | 0–1 | | SSR:189 |
| 20 | `net.assortativity.risk.perception.pre.epidemic` | Homophily at the start of the outbreak: Pearson correlation of r_σ + r_π between the two ends of every tie. Each tie enters once, in GraphStream's order of its two ends (StatsComputer.java `computeAssortativity`). | −1–1 | H_G | SSR:190 |
| 21 | `net.assortativity.age.pre.epidemic` | The same for the agents' ages. Ages are drawn per agent but play no role in the model in these batches. Unused. | −1–1 | | SSR:191 |
| 22 | `net.assortativity.profession.pre.epidemic` | Share of ties between agents with the same profession. Every agent's profession is `NA`, so 1.0 in every run. Constant. | 0–1 | | SSR:192 |
| 23 | `net.stable.pre` | 1 if the network was pairwise stable at the start of the outbreak. The stability check is switched off (Network.java:2142, 2152), so 0 in every run. Constant. | 0/1 | | SSR:193 (NetworkStatsPre.java:68) |
| 24 | `index.degree` | Number of ties of the index case at the start of the outbreak. | count (written as `8.0`) | t_i | SSR:195 |
| 25 | `index.clustering` | Local clustering coefficient of the index case at the start of the outbreak. | 0–1 | x_i | SSR:196 |
| 26 | `index.betweenness.normalized` | Normalized betweenness of the index case at the start of the outbreak (as in column 18). | 0–1 | | SSR:197 |
| 27 | `index.assortativity.perception` | Pearson correlation of r_σ + r_π between the two ends of the index case's own ties. One end is always the index case itself, and each tie enters in GraphStream's order. What this is meant to measure is unclear from the code. | −1–1 | | SSR:198 (Agent.java:896, 941) |
| 28 | `index.assortativity.age` | The same for ages. Unused. | −1–1 | | SSR:199 |
| 29 | `index.assortativity.profession` | Share of the index case's ties to agents with the same profession: 1.0. Constant. | 0–1 | | SSR:200 |
| 30 | `index.closeness` | Closeness of the index case at the start of the outbreak (as in column 19). | 0–1 | | SSR:201 |
| 31 | `index.r.sigma` | Risk perception of the index case. | 0.45–2.0 | r | SSR:202 |
| 32 | `index.r.sigma.neighborhood` | Mean risk perception of the index case's neighbours at the start of the outbreak. | 0.45–2.0 | r | SSR:203 (Agent.java:420) |
| 33 | `net.static.pct.rec` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's share of agents recovered when its outbreak ended, i.e. its final outbreak size. | % of N | \|R\| | SSR:212 (NA: SSR:207-210) |
| 34 | `net.static.pct.inf` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's share of agents infected when its outbreak ended (0, as column 45). | % of N | \|I\| | SSR:213 |
| 35 | `net.static.epidemic.duration` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's outbreak duration, as column 46. | rounds | | SSR:214 (GEN:769) |
| 36 | `net.static.epidemic.peak` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's peak round, as column 47. | round | | SSR:215 (GEN:723) |
| 37 | `net.static.epidemic.peak.size` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's peak number of infected agents, as column 48. | count | \|I\| | SSR:216 (GEN:722) |
| 38 | `net.static.ties.broken.active.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 49; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:233 |
| 39 | `net.static.ties.broken.passive.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 50; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:234 |
| 40 | `net.static.ties.out.accepted.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 51; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:235 |
| 41 | `net.static.ties.out.declined.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 52; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:236 |
| 42 | `net.static.ties.in.accepted.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 53; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:237 |
| 43 | `net.static.ties.in.declined.epidemic` | `NA` in every deposited batch. In the paired design (Section 1) it holds the frozen arm's counter, as column 54; 0 there, because ties do not change during a frozen outbreak. | count | | SSR:238 |
| 44 | `net.dynamic.pct.rec` | Adapting arm: share of agents recovered when the outbreak ended, i.e. the final outbreak size (every infected agent recovers). The analysis's outcome; an outbreak "takes off" above 10 %. | % of N | \|R\| | SSR:242 |
| 45 | `net.dynamic.pct.inf` | Adapting arm: share infected when the outbreak ended: 0 in every run. Constant. | % of N | \|I\| | SSR:243 |
| 46 | `net.dynamic.epidemic.duration` | Adapting arm: number of outbreak rounds, from the first to the round in which the last infected agent recovered, inclusive (the `active-epidemic` rounds plus the `stopped-epidemic` round of the round summary). | rounds | | SSR:244 (GEN:771) |
| 47 | `net.dynamic.epidemic.peak` | Adapting arm: outbreak round (1 = first) with the most infected agents; the first such round if several tie. | round | | SSR:245 (GEN:730) |
| 48 | `net.dynamic.epidemic.peak.size` | Adapting arm: the number of infected agents in that round. | count | \|I\| | SSR:246 (GEN:729) |
| 49 | `net.dynamic.ties.broken.active.epidemic` | Adapting arm: ties cut while any agent was infected, counted for the agent that cut them; i.e. the number of ties cut during the outbreak (Agent.java:964-970). | count | | SSR:263 |
| 50 | `net.dynamic.ties.broken.passive.epidemic` | The same ties counted for the agent on the other end; equal to column 49 in every run (Agent.java:978-984). | count | | SSR:264 |
| 51 | `net.dynamic.ties.out.accepted.epidemic` | Tie requests sent and accepted while any agent was infected, i.e. ties formed during the outbreak (Agent.java:992-998). | count | | SSR:265 |
| 52 | `net.dynamic.ties.out.declined.epidemic` | Tie requests sent and declined while any agent was infected (Agent.java:1006-1012). | count | | SSR:266 |
| 53 | `net.dynamic.ties.in.accepted.epidemic` | Requests received and accepted; equal to column 51 in every run. | count | | SSR:267 |
| 54 | `net.dynamic.ties.in.declined.epidemic` | Requests received and declined; equal to column 52 in every run. | count | | SSR:268 |
| 55 | `nb.fix.order` | `true`: agents act in a random order in every round (correction of code check S10). `true` in every deposited batch. Constant. | true/false | | SSR:281 |
| 56 | `nb.fix.d2` | `true`: each second-degree neighbour is a candidate for an encounter once, not once per shared neighbour (correction of code check S10). `true` in every deposited batch. Constant. | true/false | | SSR:282 |
| 57 | `nb.zeta.post` | Rounds of the stage after the outbreak: 10. The burn-in length (`nb.zeta`, 30) is in `config.properties` and `batch-info.txt`, not in this file. Constant. | rounds | | SSR:283 |

The six tie counters (columns 38–43 and 49–54) count events only while at least one agent is
infected. Each event is counted once for each of the two agents, so "active" equals "passive",
and "out" equals "in", over the whole network.

## 4. `round-summary.csv`

One row per round of every stage of every run, written at the end of the round (GEN:753).
28 columns in every batch. With `--no-centralities` the writer leaves out five columns:
`net.pathlength.av`, `net.betweenness.av`, `net.closeness.av`, `index.betweenness.normalized` and
`index.closeness` (RSW:105-108, 155-158, 119-121, 169-171).

| # | column | meaning | type, unit | symbol | source |
|---|---|---|---|---|---|
| 1 | `sim.uid` | Run identifier, as in the summary. | text | | RSW:140 |
| 2 | `sim.upc` | As in the summary: 1. Constant. | count | | RSW:141 |
| 3 | `sim.cnt` | Number of the run within the shard. | count | | RSW:142 |
| 4 | `sim.it` | As in the summary: 1. Constant. | count | | RSW:143 |
| 5 | `sim.round` | Round number, counted over the whole run from 1 (first burn-in round) across all stages. | round | | RSW:144 (GEN:713) |
| 6 | `nb.ep.structure` | The arm the round belongs to: `dynamic` in every round of every deposited batch. (In the paired design, which no deposited batch uses, the burn-in and the frozen arm are `static`.) | text | | NBR:79 |
| 7 | `nb.alpha` | As in the summary. | 0–1 | α | NBR:80 |
| 8 | `nb.sigma` | As in the summary. | ≥ 1 | σ | NBR:81 |
| 9 | `nb.rs.equal` | 1 if perceived severity and perceived infectivity are equal for every agent (r_σ = r_π): 1. Constant. | 0/1 | | NBR:82 |
| 10 | `nb.r.sigma.av` | Mean risk perception of the run's agents, as in the summary. | 0.45–2.0 | r | NBR:83 |
| 11 | `nb.r.pi.av` | Mean perceived infectivity r_π; equal to column 10. | 0.45–2.0 | r | NBR:84 |
| 12 | `nb.omega` | As in the summary. | 0–1 | ω | NBR:85 |
| 13 | `nb.selective` | As in the summary. | true/false | s | NBR:86 |
| 14 | `nb.d` | As in the summary. | 0–1 | d | NBR:87 |
| 15 | `sim.stage` | Stage of the round: `pre-epidemic` (burn-in), `active-epidemic`, `stopped-epidemic` (the round in which the last infected agent recovered; one per outbreak), `post-epidemic`. | text | | RSW:151 |
| 16 | `net.degree.av` | Mean number of ties per agent after the round. | ties per agent | D_G | RSW:153 |
| 17 | `net.clustering.av` | Mean local clustering coefficient after the round, as in the summary. | 0–1 | C_G | RSW:154 |
| 18 | `net.assortativity.risk.perception` | Homophily after the round, as in the summary. | −1–1 | H_G | RSW:160 |
| 19 | `net.assortativity.age` | The same for ages. Unused. | −1–1 | | RSW:161 |
| 20 | `net.assortativity.profession` | Share of ties within a profession: 1.0. Constant. | 0–1 | | RSW:162 |
| 21 | `net.pct.sus` | Share of agents susceptible after the round. | % of N | \|S\| | RSW:163 |
| 22 | `net.pct.inf` | Share of agents infected after the round. | % of N | \|I\| | RSW:164 |
| 23 | `net.pct.rec` | Share of agents recovered after the round. | % of N | \|R\| | RSW:165 |
| 24 | `index.degree` | Number of ties of the index case after the round. The index case is chosen before the burn-in, so burn-in rows describe the agent that will become the index case. | count (written as `8.0`) | t_i | RSW:167 |
| 25 | `index.clustering` | Local clustering coefficient of the index case. Cached per stage round number: from the first outbreak round on, it repeats the value of the last burn-in round until a stage runs longer than the burn-in. In the runs checked it stayed constant through the outbreak and the stage after it, while `index.degree` changed. Not current after the burn-in. | 0–1 | x_i | RSW:168 (Agent.java:762-772) |
| 26 | `index.assortativity.perception` | As in the summary (meaning unclear from the code), with the same caching as column 25. | −1–1 | | RSW:173 (Agent.java:941-946) |
| 27 | `index.assortativity.age` | The same for ages, with the same caching. Unused. | −1–1 | | RSW:174 |
| 28 | `index.assortativity.profession` | 1.0, with the same caching. Constant. | 0–1 | | RSW:175 |

## 5. `tie-events.csv`

Written only when tie events are recorded (`export.tie.events=true`): in tie1, tie2 and the
recording check (`on/`). One row per tie formed or cut while at least one agent was infected, that
is, in the outbreak rounds. Agent ids run from `1` to `N` within a run. 14 columns.

| # | column | meaning | type, unit | symbol | source |
|---|---|---|---|---|---|
| 1 | `sim.uid` | Run identifier, as in the summary. | text | | TEL:220 |
| 2 | `sim.cnt` | Number of the run within the shard. | count | | TEL:221 |
| 3 | `sim.round` | Round in which the tie changed, numbered as in the round summary (TEL:240-242). | round | | TEL:222 |
| 4 | `event` | `form`: a requested tie was accepted; `dissolve`: a tie was cut. | text | | TEL:223 |
| 5 | `initiator.id` | Agent that requested the tie (form) or cut it (dissolve). | id | | TEL:224 |
| 6 | `partner.id` | Agent on the other end. | id | | TEL:225 |
| 7 | `initiator.disease.state` | Disease state of the initiator at that moment: `S`, `I` or `R` (`V`, vaccinated, does not occur). | text | δ | TEL:226 |
| 8 | `partner.disease.state` | Disease state of the partner. | text | δ | TEL:227 |
| 9 | `initiator.r.sigma` | Risk perception of the initiator. | 0.45–2.0 | r | TEL:228 |
| 10 | `partner.r.sigma` | Risk perception of the partner. | 0.45–2.0 | r | TEL:229 |
| 11 | `nb.selective` | Whether the run's agents are selective, as in the summary. | true/false | s | TEL:230 |
| 12 | `common.neighbours` | Number of agents tied to both. Forming or cutting the tie itself does not change it. | count | | TEL:231 (TEL:261-270) |
| 13 | `distance.after` | Dissolve: shortest-path distance between the two agents after the cut, by breadth-first search; −1 if no path remains. `NA` for form events. | ties (path length) | | TEL:232 (TEL:273-293) |
| 14 | `tie.formed.round` | Form: the round of this event (equal to `sim.round`). Dissolve: the round in which this tie was formed during the outbreak; −1 if it existed before the outbreak or was formed while no agent was infected. | round | | TEL:233 (TEL:120-148) |

## 6. `transmissions.csv`

Written with `tie-events.csv`: one row per infection of an agent other than the index case, in
the round the infection happened. 9 columns.

| # | column | meaning | type, unit | symbol | source |
|---|---|---|---|---|---|
| 1 | `sim.uid` | Run identifier, as in the summary. | text | | TEL:175 |
| 2 | `sim.cnt` | Number of the run within the shard. | count | | TEL:176 |
| 3 | `sim.round` | Round of the infection, numbered as in the round summary. | round | | TEL:177 |
| 4 | `infectee.id` | The newly infected agent. | id | | TEL:178 |
| 5 | `infector.id` | One of the infectee's infected neighbours, chosen at random with equal probability. The model decides an infection with one draw against the probability given the number of infected neighbours and names no infector, so this is an attribution, made with a separate random-number generator that does not affect the simulation (TEL:77, 170-171). `NA` if no infected neighbour was found (does not occur). | id | | TEL:179 |
| 6 | `infectee.r.sigma` | Risk perception of the infectee. | 0.45–2.0 | r | TEL:180 |
| 7 | `infector.r.sigma` | Risk perception of the attributed infector (`NA` without infector). | 0.45–2.0 | r | TEL:181 |
| 8 | `tie.formed.round` | Round in which the tie between infector and infectee was formed during the outbreak; −1 if it existed before the outbreak or was formed while no agent was infected. | round | | TEL:182 |
| 9 | `infectee.infected.neighbours` | Number of infected neighbours the infection probability was computed with. | count | t_{i_I} | TEL:183 |

Checks of these two files on the final build (batch/README.md, "Checked 5 Nov 2026 on
`70dcf43`"):
- dissolve events equal column 49 of the summary, form events column 51;
- transmissions + 1 (the index case) equal the agents ever infected.

## 7. Columns that are constant or unused in the deposited batches

- **Constant in every run:**
  - `sim.upc`, `sim.it` (1);
  - `nb.ep.structure` (`dynamic`);
  - `net.stable.pre` (0);
  - `net.assortativity.profession.pre.epidemic`, `index.assortativity.profession`,
    `net.assortativity.profession` (1.0);
  - `net.dynamic.pct.inf` (0);
  - `nb.fix.order`, `nb.fix.d2` (`true`);
  - `nb.zeta.post` (10);
  - `nb.rs.equal` (1).
- **`NA` in every deposited batch:** all eleven `net.static.*` columns (they would hold the frozen
  arm of the paired design, which no deposited batch uses).
- **Equal to another column by construction:**
  - `net.dynamic.ties.broken.passive.epidemic` (= active);
  - `net.dynamic.ties.in.accepted.epidemic` (= out accepted);
  - `net.dynamic.ties.in.declined.epidemic` (= out declined);
  - `nb.r.pi.av` (= `nb.r.sigma.av`).
- **Unused by the model in these batches:** the age assortativity columns (ages are drawn but
  play no role).
- **Not current after the burn-in:** `index.clustering` and the three `index.assortativity.*`
  columns of `round-summary.csv` (Section 4, column 25).
- **Written by the build, but not by the deposited batches:**
  - `paired.start.identical` (summary, only with `nb.ep.structure` = `both`, after column 54:
    `true` if both arms of a pair started from the same network);
  - `check.infected.cost.n` and `check.infected.cost.diff` (summary, only with
    `check.infected.cost=true`);
  - the five centrality columns of the round summary (only without `--no-centralities`);
  - `agent-details.csv` (only with `export.agent.details=true`).
