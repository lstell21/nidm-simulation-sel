# Mechanism run (M1, M2): sim-machine hand-over report

**STATUS: ready to launch.** Part B steps 1–4 of `MECHANISM_claude-code.md`
are done. The build and smoke tests pass, and check 2 of the brief holds in
all 72 smoke runs. The launch command is in §5; Leonard runs it. Step 5
(verify, package `m1.tgz` / `m2.tgz`, completion section) is a separate
session.

Written 2026-10-20 by Claude Code on USELAB02.

## 1. Machine and repository

| | |
|---|---|
| host | USELAB02, Windows 11 Education 10.0.22631, Git Bash (MINGW64 / MSYS 3.6.10) |
| CPU / RAM | AMD Ryzen 9 7950X, 16 physical cores / 32 logical; 63.1 GB (52 GB free before launch; last boot 2026-10-16 10:21) |
| disk | C: 3.0 TB free |
| Java / Maven | `openjdk version "1.8.0_504"` (Temurin) / Maven 3.9.16 |
| branch / HEAD built | `mechanism-output` at **`27074ea86311c593baa9be979b9ccb44e7a61749`** ("Mechanism output: tie-events.csv and transmissions.csv behind export.tie.events", 2026-10-20 16:46 +0200); tree clean; `git pull --ff-only` → already up to date |

This report is committed on top of `27074ea`, so the batches will record the
report commit's hash. That commit adds only this file. The Java sources,
config and harness are those of `27074ea`, from which the jar was built.

### Commits Runs A and B were built from

`grep "git commit" batch-runs/runA/c*/batch-info.txt batch-runs/runB/c*/batch-info.txt`:

| run | chunk | commit | `git dirty` |
|---|---|---|---|
| Run A | c1 | `5950b578395a6b0d23b1cdb9f4403b32e0c5a570` | 0 |
| Run A | c2–c5 | `6e055ba14243c573b292b4b287632a453770886e` | 0 |
| Run B | c1–c5 | `6e055ba14243c573b292b4b287632a453770886e` | 0 |

`5950b57` and `6e055ba` differ only in `batch/progress.sh` (an ETA display),
so the simulation code is the same for all ten chunks. Between `6e055ba` and
`27074ea`, `src/` only gains lines (469 insertions, 0 deletions): the
tie-event logger (`TieEventLog.java`), its hooks in `Agent.connectTo`,
`disconnectFrom` and `computeDiseaseTransmission`, `Network` and generator
plumbing, the `export.tie.events=false` default, and comment blocks in
`Agent.java`. With the flag off, the code is unchanged apart from a null check.

## 2. Build

`mvn package -DskipTests` → exit 0 (2026-10-20 16:52). It produced
`target/nidm-4.0.1.jar` (159 MB), `target/classes` and the new lean
`target/nidm-4.0.1-batch.jar` (7 MB). Without `--jar`, `run-batch.sh` uses the
fat jar plus `target/classes`, as Runs A/B and Phase 3 did. The tree stayed
clean.

## 3. Smoke tests (all N = 240, `--no-centralities`, `--heap 2g`, absolute `--out`)

| directory | settings | runs | purpose |
|---|---|---|---|
| `batch-runs/mech-smoke` | M1, `--tie-events`, 4 shards | 8 | the brief's smoke test |
| `batch-runs/mech-smoke16-m1` | M1, `--tie-events`, 16 shards | 32 | s/sim under full load |
| `batch-runs/mech-smoke16-m2` | M2, `--tie-events`, 16 shards | 32 | s/sim and volume for M2 |
| `batch-runs/mech-smoke16-m1-off` | M1, flag **off**, 16 shards | 32 | logging overhead |

One deviation from the brief: `--reps 8` instead of `--reps 2` for the
4-shard test. With one N level, 2 reps over 4 shards would leave two shards
with zero runs. All 52 shards across the four tests exited 0.

**`batch-info.txt`** (`mech-smoke`) records commit `27074ea`, branch
`mechanism-output`, `git dirty : 0`, `omega : random`, `gamma range :
0.1..0.2`, `alpha range : 0..1`, `encounters : 16`, `centralities : false`,
`tie events : true`, `ep structure : config (dynamic)`, and the full command
line.

**New files.** Every shard writes `tie-events.csv` and `transmissions.csv`
next to the two summaries, with the documented columns
(`sim.uid;sim.cnt;sim.round;event;initiator.id;partner.id;initiator.disease.state;partner.disease.state;initiator.r.sigma;partner.r.sigma;nb.selective;common.neighbours;distance.after;tie.formed.round`
and
`sim.uid;sim.cnt;sim.round;infectee.id;infector.id;infectee.r.sigma;infector.r.sigma;tie.formed.round;infectee.infected.neighbours`).
Every row's `sim.uid` exists in the shard's simulation summary.

**Row counts per run (brief check 2): all 72 tie-event runs match exactly.**
Dissolve events = `net.dynamic.ties.broken.active.epidemic`, form events =
`net.dynamic.ties.out.accepted.epidemic`, and transmissions + 1 =
`net.dynamic.pct.rec` × N / 100. The 4-shard test, run by run:

| shard | run | s | α | γ | ω | dissolve | form | transmissions + 1 |
|---|---|---|---|---|---|---|---|---|
| n240-s1 | 1#1#1 | true | 0.39 | 0.138 | 0.51 | 1152 = 1152 | 1150 = 1150 | 26 = 26 |
| n240-s1 | 1#2#1 | false | 0.49 | 0.108 | 0.53 | 942 = 942 | 957 = 957 | 86 = 86 |
| n240-s2 | 1#1#1 | true | 0.50 | 0.128 | 0.17 | 950 = 950 | 921 = 921 | 236 = 236 |
| n240-s2 | 1#2#1 | true | 0.38 | 0.165 | 0.23 | 1389 = 1389 | 1405 = 1405 | 240 = 240 |
| n240-s3 | 1#1#1 | true | 0.80 | 0.147 | 0.29 | 325 = 325 | 324 = 324 | 138 = 138 |
| n240-s3 | 1#2#1 | false | 0.59 | 0.120 | 0.90 | 1407 = 1407 | 1406 = 1406 | 125 = 125 |
| n240-s4 | 1#1#1 | false | 0.55 | 0.109 | 0.91 | 1480 = 1480 | 1478 = 1478 | 203 = 203 |
| n240-s4 | 1#2#1 | true | 0.99 | 0.129 | 0.31 | 117 = 117 | 84 = 84 | 1 = 1 |

The 16-shard tests: 32/32 runs match for M1 and 32/32 for M2.

### Time per simulation (16 shards at once, 2 runs per shard, JVM startup included)

| test | mean shard wall | s/sim |
|---|---|---|
| M1, tie events on | 35.4 s | 17.7 |
| M1, tie events **off** | 38.4 s | 19.2 |
| M2, tie events on | 39.1 s | 19.6 |
| M1, 4 shards (brief's test) | 28.3 s | 14.1 |

Logging overhead is **not measurable**: flag-on was faster than flag-off here,
so the difference is run-to-run noise. That matches the laptop's finding at
N = 80. Running 16 shards at once costs ~1.6–1.8× the brief's 10.7 s serial
figure, the contention tax the README describes for K = 16.

### Output volume

| | M1 (pooled 40 runs) | M2 (32 runs) |
|---|---|---|
| tie events per run | 1,936 (4-shard) / 975 (16-shard) | 1,761 |
| transmissions per run | 131 / 57 | 149 |
| `split/` per run | ~115 KiB | ~165 KiB |
| whole run directory per run (`work/` copy + `split/` + logs) | ~2.05 × `split/` | ~2.05 × `split/` |
| gzip ratio of `split/` | 5.7× | 5.5× |

Volume per run varies a lot between runs (outbreak size and duration depend
on γ and α). The M1 figures from 8 and 32 runs differ by a factor of 2, so
the estimates below are ±50 %.

## 4. Estimates for the full batches (16 shards, 312–313 runs per shard)

| | M1 | M2 | both |
|---|---|---|---|
| wall time | ~1.5–2 h | ~1.7–2.2 h | **~3.5–4 h**, sequential |
| `split/` (merged output) | ~0.55 GB | ~0.8 GB | ~1.4 GB |
| on disk incl. `work/` | ~1.2 GB | ~1.7 GB | ~2.9 GB (3.0 TB free) |
| `.tgz` (split + batch-info) | ~100 MB | ~150 MB | |

Wall time = 313 runs × 17.7–19.6 s/sim, plus ~10 % for the slowest shard. Disk
use is well under the brief's "under 1 GB per batch before compression".

## 5. Launch (for Leonard)

From a Git Bash window:

```sh
cd ~/java-workspace/nidm-simulation-sel
git status --short          # must print nothing
if mkdir batch-runs/mech.lock 2>/dev/null; then
  nohup bash -c '
    R="$PWD/batch-runs"
    ./batch/run-batch.sh --reps 5000 --shards 16 --heap 2g --ngrid 240 \
        --gamma-min 0.1 --gamma-max 0.2 --omega-random --alpha-min 0 --alpha-max 1 \
        --no-centralities --tie-events --out "$R/m1"
    echo "=== M1 exit $? at $(date -Iseconds) ==="
    ./batch/run-batch.sh --reps 5000 --shards 16 --heap 2g --ngrid 240 \
        --gamma-min 0.1 --gamma-max 0.4 --omega 0 \
        --no-centralities --tie-events --out "$R/m2"
    echo "=== M2 exit $? at $(date -Iseconds) ==="
  ' > batch-runs/mech.log 2>&1 &
  echo "LAUNCHED: M1, then M2. Do not paste this again. Checking in 20 s ..."
  sleep 20
  echo "$(grep -c '^  launched' batch-runs/mech.log) of 16 M1 shards started. OK if 16. Leave this window open; check progress from a second window."
else
  echo "ALREADY LAUNCHED (batch-runs/mech.lock exists) -- nothing started."
fi
```

Expected output: `[1] <pid>` (bash's job notice; the number is a process
ID, not an error), then `LAUNCHED: …`, and after 20 s `16 of 16 M1 shards
started`. Pasting it a second time prints `ALREADY LAUNCHED` and starts
nothing: `mkdir` of the lock directory is atomic and fails if it exists.
Tested with `--dry-run` substituted, pasted twice in a row. To launch again
after a failure, move `batch-runs/m1`, `m2` and `mech.log` aside and remove
`batch-runs/mech.lock`.

**First launch attempt, 20 Oct 17:01: discarded.** The earlier version of
this command (no lock, no confirmation) was pasted twice, at 17:01:04 and
17:01:35. Two `run-batch.sh` runs then wrote into the same `batch-runs/m1`,
with two Java processes per shard directory, and the second overwrote
`batch-info.txt`. Claude Code stopped both runs at ~17:04 (2 wrapper shells,
66 `run-batch.sh` processes, 32 Java processes; M2 had not started) and moved
`m1` and `mech.log` to
`batch-runs/broken-20261020-1701-double-launch/`. Nothing from it is used.

M1 runs first; M2 starts when M1 ends, whatever M1's exit code. Both write
their plan, per-shard results and `done.` / `WARNING` into
`batch-runs/mech.log`. Checked with `--dry-run` substituted (16 shards ×
312–313 runs, N = 240, the settings above). α and γ are passed explicitly,
though they equal the config defaults (α ~ U[0, 1]; M2's γ 0.1–0.4), so
`batch-info.txt` records them. The epidemic structure is the config default,
`dynamic`.

**Rules from Phase 3 (see `batch/README.md`):**
- **Leave the launch window open and do not press Ctrl-C in it** until both
  `=== M… exit` lines are in the log. On 12 Oct a Ctrl-C in a launch window
  killed every Java shard, and it is not established whether `nohup … &` from
  an interactive shell is safe from that.
- **Check progress from a second Git Bash window**, a few times at most. Do
  not leave a watch loop running: on this machine every exited process stays
  pinned in RAM until reboot.

  ```sh
  cd ~/java-workspace/nidm-simulation-sel
  grep -E '^===|WARNING|rc=[^0]' batch-runs/mech.log
  awk 'FNR > 1 { n[FILENAME ~ /\/m1\// ? "M1" : "M2"]++ } END { printf "M1 %d/5000  M2 %d/5000\n", n["M1"], n["M2"] }' \
      batch-runs/m[12]/work/*/exports/*/data/nunnerbuskens/simulation-summary.csv 2>/dev/null
  ```
- Done when the log shows `=== M1 exit 0` and `=== M2 exit 0`. A non-zero
  exit means some shard failed; `rc=` per shard is in the log. To redo a batch,
  move its directory (`batch-runs/m1` or `m2`) aside first: `run-batch.sh`
  does not clear an existing `--out`. There is no resume, but at ~2 h a batch
  a restart costs little.

## 6. Completion (separate session, Part B step 5)

To do: verify 5,000 runs per batch, the merged `split/` outputs and
`batch-info.txt` (clean tree, commit on `mechanism-output`), and check 3 if
the Run A/B summaries are available here. Package `m1.tgz` / `m2.tgz`
(merged outputs plus `batch-info.txt`) with `.sha256` files, and add sizes and
SHA-256 here.
