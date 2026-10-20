# Mechanism run: brief (20 Oct 2026, v3)

> Copied on 20 Oct 2026 from SelSWIDM-analysis `reports/memo/mechanism_run_brief.md` (v3), which is not in git, without its "Coordination" section, for the sim machine to read from this repository. The laptop part (simulator code, checks 1 and 2) is done on branch `mechanism-output`; see `batch/README.md` → "Tie-level output". Part B below is the sim machine's task.

Goal: test the two explanations the manuscript currently offers as hypotheses, before the parallel
reviews by Hendrik and André start on 2 Nov. Target: code and laptop checks by Fri 23 Oct, batches
on the sim machine at the weekend, analysis by Wed 28 Oct, text by Fri 30 Oct (Hendrik meeting).

## Hypotheses and predictions

**H1 Seeding (Discussion §7, lines 24–30; Result 3).** At low baseline homophily, selective
contact reduction raises the probability that an outbreak takes off (Run B: 74.4 % vs 70.9 %).
Proposed mechanism: during the outbreak, agents with low risk perception become each other's
neighbours, so early transmission runs through ties among them.
Predictions at ω = 0, selective vs random:
1. A larger share of early transmissions (first 5 rounds of the active epidemic) runs over ties
   formed during the outbreak.
2. Early infector–infectee pairs have lower risk perception (r.sigma).
3. Both differences are larger in runs that take off (final size > 10 %).

**H2 Path redundancy (Discussion, percolation paragraph replacement; Result 8 / Figure 9).**
Adaptation is least effective at moderate clustering (adapting/frozen ratio 0.17, 0.37, 0.09 at
α < 0.1, 0.4–0.5, 0.8–0.9, γ 0.100–0.125). Proposed mechanism: a dissolved tie between an infected
and a susceptible agent often leaves a detour via shared neighbours, while long-range ties still
link groups.
Predictions in adapting runs, for *protective cuts* (a tie between an infected and a susceptible
agent dissolved while an infection is active):
1. P(the susceptible endpoint is infected within 5 rounds after the cut) peaks at α 0.4–0.5.
2. Among those later infections, the share whose infector is a common neighbour of the two
   endpoints (the detour) is highest at moderate α.
3. Descriptive: common neighbours at the time of the cut and distance between the endpoints after
   the cut, by α bin.

## New simulator output (nidm-simulation-sel)

Behind a new config flag, default off, e.g. `export.tie.events=false`; all existing writers and
outputs unchanged.

- `tie-events.csv`: one row per tie formed or dissolved while an infection is active.
  Columns: sim.uid, sim.cnt, sim.round, event (form | dissolve), initiator id, partner id, both
  agents' disease state (S/I/R) and r.sigma, nb.selective, number of common neighbours before the
  change, distance between the endpoints after a dissolution (BFS, −1 if disconnected, may be
  capped at 6), and the round in which the tie was formed (−1 if it existed before the outbreak).
- `transmissions.csv`: one row per infection. Columns: sim.uid, sim.cnt, sim.round, infectee id,
  infector id, r.sigma of both, round the infector–infectee tie was formed (−1 if pre-epidemic),
  number of infected neighbours of the infectee in that round.

Hooks: `Agent.connectTo` (Agent.java ~1190), `Agent.disconnectFrom` (~1225),
`Agent.computeDiseaseTransmission` (~1786) and `Agent.infect` (~1804). Tie formation rounds must be
tracked (for example a map from edge to formation round in the network). Check how
`computeDiseaseTransmission` decides an infection. If it does not attribute a specific infector,
attribute one infected neighbour at random using a **separate** `java.util.Random`, so that the
model's own random draws are unaffected, and document this.

## Batches

Both use dynamic structure, `--no-centralities`, 16 encounters, the same defaults as Run A, and an
absolute `--out`.

- M1 (H2): N = 240, γ ~ U[0.1, 0.2], ω ~ U[0, 1], α ~ U[0, 1], 5,000 runs.
- M2 (H1): N = 240, ω = 0, γ ~ U[0.1, 0.4], 5,000 runs.

Cost: N = 240 is about 10.7 s per simulation serially on the sim machine, so each batch takes about
2–3 h on 16 shards plus logging overhead (measure it in the smoke test). Expected volume, to be
measured: about 1–2 thousand tie events per run, i.e. several million rows and well under 1 GB per
batch before compression. Output is packaged as m1.tgz / m2.tgz and unpacked on the laptop into
`SelSWIDM-analysis/data/mechanism/{m1,m2}`. data/ is gitignored, so it belongs in the data deposit.

## Where things run

- Laptop: code, checks 1 and 2 at N = 80 (minutes), and the analysis.
- Sim machine (16 cores): build from `mechanism-output`, smoke test at N = 240, M1 and M2. Leonard
  launches the batches from Git Bash (nohup); Claude Code there prepares, verifies and packages.
- The laptop is several times slower; do not run M1 or M2 there.

## Checks (all must pass before analysis)

1. Smoke test with the flag on vs off (for example 200 runs each at N = 80). Final-size distributions
   by condition must be indistinguishable (Kolmogorov–Smirnov p > .05), and the existing CSVs must
   have identical columns.
2. Per run: dissolve events initiated during the epidemic = net.dynamic.ties.broken.active.epidemic,
   and form events = net.dynamic.ties.out.accepted.epidemic. Transmissions + index case = number
   ever infected.
3. M1 and M2 outcomes match Run A / Run B at N = 240 within sampling error (mean final size and
   take-off by condition).

## Analysis (SelSWIDM-analysis)

New DESIGNS entries `m1`, `m2` and targets `mech_h1`, `mech_h2`, plus one figure each:
- H2: α in 0.1 bins × γ bands (0.025 wide as in Phase 3). Report P(infected within 5 rounds |
  protective cut) with binomial CIs, the detour share, and the descriptive distributions.
- H1: by condition, and within that by take-off. Report the share of early transmissions over
  outbreak-formed ties and the mean r.sigma of early pairs, with bootstrap CIs over runs.

## Reporting

If the predictions hold: one paragraph in Results (§6.4 for H1, §6.5 for H2), an appendix figure,
and the Discussion changes "hypothesis" to "consistent with tie-level evidence". If they do not
hold: report them as tested and not supported, and revise the Discussion accordingly. Both outcomes
are informative; do not tune the definitions after looking at the results. The definitions above
(5 rounds, protective cut, early phase) are fixed now.

## Part B: sim machine

Repository ~/java-workspace/nidm-simulation-sel on this machine. Never discard local work, never
force-push.
1. git status --short must be empty (untracked files make batch-info.txt record a dirty tree). Then
   git fetch; git switch mechanism-output; git pull --ff-only; mvn package -DskipTests.
   Read MECHANISM_claude-code.md in the repository root (committed by prompt 3a). Record the commits
   Runs A and B were built from: grep "git commit" batch-runs/runA/c*/batch-info.txt
   batch-runs/runB/c*/batch-info.txt (they go into the hand-over report in step 4).
2. Smoke test: run-batch.sh --reps 2 --shards 4 --ngrid 240 --tie-events with the M1 settings and an
   absolute --out batch-runs/mech-smoke. Verify both new files, the row counts per run, and measure
   s/sim. Estimate the wall time and disk use for M1 and M2 at 16 shards.
3. Prepare, do not run, one Git Bash command for Leonard that runs M1 and then M2 sequentially,
   detached with nohup and logging to batch-runs/mech.log: --shards 16, --no-centralities,
   --tie-events, absolute --out batch-runs/m1 and batch-runs/m2, the settings from the brief
   (M1: N = 240, gamma 0.1..0.2, omega random, alpha random, 5,000 runs; M2: N = 240, omega 0,
   gamma 0.1..0.4, 5,000 runs), plus how to monitor progress.
4. Hand-over report: write MECHANISM_REPORT.md in the repository root (machine, HEAD, Run A/B commits, build,
   smoke-test results, s/sim, estimated wall time and disk use, the launch command), commit it on
   mechanism-output and push. Do this before Leonard launches: an uncommitted file would make
   batch-info.txt record a dirty tree. Then print the launch command and stop.
5. After Leonard reports completion (separate session): verify 5,000 runs per batch, merged outputs,
   batch-info.txt (clean tree, commit on mechanism-output), and check 3 of the brief if Run A/B
   summaries are available here. Package m1.tgz and m2.tgz (merged outputs plus batch-info.txt) and
   write m1.tgz.sha256 and m2.tgz.sha256 beside them (sha256sum format); Leonard copies all four files
   to the laptop. Add a completion section with sizes and SHA-256 to MECHANISM_REPORT.md, commit, push. Do not
   touch SelSWIDM-analysis data/split, data/runB or data/phase3.
