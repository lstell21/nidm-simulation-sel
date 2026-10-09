# Phase 3 batch — compute-machine report

**STATUS: stopped at step 6 (launch).** Steps 1–5 are done and the smoke test
passed. The full run is **not started**. Claude Code's permission classifier
blocked the detached launch (details in §6), so you need to start it from a
Git Bash window yourself, using the one command in §6. §8 (completion) is for
a separate session.

Written 2026-10-09 by Claude Code on USELAB02.

## 1. Machine and repository

| | |
|---|---|
| host | USELAB02 (Windows 11 Education 10.0.22631) |
| `uname -a` | `MINGW64_NT-10.0-22631 USELAB02 3.6.10-5a1665c8.x86_64 2026-09-28 10:40 UTC x86_64 Msys` (Git for Windows bash; GNU sed 4.9) |
| CPU / RAM | AMD Ryzen 9 7950X, 16 physical cores / 32 logical; 63.1 GB |
| `java -version` | `openjdk version "1.8.0_504"` (Temurin 1.8.0_504-b01) |
| Maven | 3.9.16 |
| tmux / screen | not installed (see §6) |
| branch / HEAD | `selective-contact-reduction` at **`c3de40adba7ab70ce1f7b1b7d9e1c55adcf75cb8`** ("Harness: --ep-structure, portable classpath, provenance in batch-info; document Phase 3 and known divergences", 2026-10-09 15:47 +0200) |

Step 1: the working tree was clean (no uncommitted or untracked files, no
stash). `git fetch` + `git pull --ff-only` reported "Already up to date"
because this clone was already at `c3de40a`, the same as
`origin/selective-contact-reduction`. That commit contains the `p3` arm in
`batch/phase2.sh` and `batch/run-phase2.sh`.

## 2. Build

`mvn package -DskipTests` → exit 0. `target/nidm-4.0.1.jar` (159,189,126 B,
2026-10-09 17:00) and `target/classes` are present (`Agent.class` rebuilt
16:56). The tree was still clean after the build. The smoke test's
`batch-info.txt` records `git commit c3de40a…`, `git dirty : 0`.

## 3. Dry run

`./batch/run-batch.sh --dry-run --reps 2000 --shards 16 --gamma-min 0.1 --gamma-max 0.2 --omega-random --ep-structure both --no-centralities`
(the machine has 16 physical cores, so K = 16):

```
batch plan
  N grid          : 80,160,240,320,400,480  (6 levels)
  reps per N      : 2000
  total sims      : 12000
  shards          : 16  (allocated by cost, ~N^3.1)
  heap per shard  : 1g
  omega           : random
  gamma range     : 0.1..0.2
  encounters      : 16 per agent and step (nb.phi = 16/(N-1))
  centralities    : false
  ep structure    : both

  shard allocation:
    N=80     1 shard(s)  2000 reps each
    N=160    1 shard(s)  2000 reps each
    N=240    1 shard(s)  2000 reps each
    N=320    2 shard(s)  1000 reps each
    N=400    4 shard(s)  500 reps each
    N=480    7 shard(s)  285 reps each
```

The required lines all appear: `ep structure : both`, `gamma range : 0.1..0.2`,
`omega : random`. On "285 reps each": the display rounds down, but
`shard-list.txt` gives the remainder to the first shards (5 × 286 + 2 × 285 =
2000). The driver uses `HEAP=2g`, not the 1g shown here.

## 4. Smoke test

### 4a. The documented command fails as written (harness bug, not Java)

With the relative `--out batch-runs/p3-smoke` from Part B step 3 and the
README, **all 6 shards failed before Java started**:

```
./batch/run-batch.sh: line 283: batch-runs/p3-smoke/work/n80-s1/shard.log: No such file or directory
./batch/run-batch.sh: line 286: batch-runs/p3-smoke/work/n80-s1/exit.code: No such file or directory
  ... (all six shards) ...  rc=?  elapsed=-1791558036s
```

Cause: the shard subshell runs `cd "$SDIR"` and then redirects into
`"$SDIR/shard.log"`. `$SDIR` is still relative at that point, and the
`conf` classpath entry is relative too. Any relative `--out` breaks every
shard. The chunked driver always passes an absolute `--out`
(`$REPO/batch-runs/<arm>/c<i>`), so Runs A/B never hit this, and the `p3`
arm won't either.

I did **not** patch `run-batch.sh`. A local edit would make every chunk's
`batch-info.txt` record a dirty tree, and then `c3de40a` would no longer
describe the code that ran. I reran the same command with an absolute
`--out "$PWD/batch-runs/p3-smoke"`, which is the code path the driver uses.
The failed attempt is kept as `batch-runs/p3-smoke-failed-relative-out/`
(configs and `start.epoch` only; safe to delete).

Suggested fix for a later, laptop-side harness commit (after Phase 3, so
every chunk records the same commit), near the argument parsing in
`run-batch.sh`:

```sh
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
```

### 4b. Checks (absolute `--out`), all passed

Run `2026-10-09T17:01:02+02:00` → `17:04:30`. The checks were done with a
short Python script reading every shard, not just `n80-s1`.

| shard | exit.code | wall (s) | s/sim | `nb.gamma` (min..max) | `nb.phi` (config) | 16/(N−1) | `net.static.pct.rec` / `net.dynamic.pct.rec`, sim 1 · sim 2 |
|---|---|---|---|---|---|---|---|
| n80-s1 | 0 | 2 | 1.0 | 0.1170..0.1716 | 0.202532 | 0.202532 | 17.5 / 10.0 · 98.75 / 3.75 |
| n160-s1 | 0 | 8 | 4.0 | 0.1251..0.1998 | 0.100629 | 0.100629 | 100.0 / 17.5 · 6.25 / 6.25 |
| n240-s1 | 0 | 26 | 13.0 | 0.1092..0.1720 | 0.066946 | 0.066946 | 99.58 / 91.67 · 97.92 / 37.08 |
| n320-s1 | 0 | 66 | 33.0 | 0.1012..0.1091 | 0.050157 | 0.050157 | 99.06 / 46.25 · 99.06 / 45.94 |
| n400-s1 | 0 | 120 | 60.0 | 0.1847..0.1919 | 0.040100 | 0.040100 | 100.0 / 100.0 · 89.5 / 0.25 |
| n480-s1 | 0 | 206 | 103.0 | 0.1886..0.1908 | 0.033403 | 0.033403 | 100.0 / 0.625 · 100.0 / 5.0 |

- `simulation-summary.csv`: 2 rows per shard; `nb.ep.structure == both` in
  every row; `net.static.pct.rec` and `net.dynamic.pct.rec` are numeric in
  every row and usually differ; every `nb.gamma` is in [0.1, 0.2]. Each
  shard's `config.properties` has `nb.ep.structure=both` and exactly one
  `nb.N=` line.
- **`nb.phi` is not a column in `simulation-summary.csv`.** It lives only in
  each shard's `config.properties`, and there it equals 16/(N−1) to six
  decimals at every N. The README's check 1 implies it is a summary column,
  and the analysis should take it from the config.
- `round-summary.csv`: for every `sim.cnt` in every shard,
  `nb.ep.structure` runs `static` then `dynamic`, and `sim.stage` runs
  `pre-epidemic > active-epidemic > stopped-epidemic > active-epidemic > stopped-epidemic > post-epidemic`,
  i.e. two active stretches. Example (n320-s1):

  ```
  sim.cnt sim.round nb.ep.structure sim.stage
  1   1  static   pre-epidemic
  1  11  static   active-epidemic      <- static outbreak starts at zeta+1
  1  45  static   stopped-epidemic     <- one round, still labelled static
  1  46  dynamic  active-epidemic      <- dynamic outbreak; sim.round keeps counting
  1  75  dynamic  stopped-epidemic
  1  76  dynamic  post-epidemic
  ```

  The README writes `ACTIVE_EPIDEMIC`; the CSV value is lowercase
  `active-epidemic`, as in Run A's data, so string matches in the analysis
  must use the lowercase form. One `stopped-epidemic` round sits between the
  two outbreaks, and it is labelled `static`.
- `batch-info.txt` is complete:

  ```
  started         : 2026-10-09T17:01:02+02:00
  git commit      : c3de40adba7ab70ce1f7b1b7d9e1c55adcf75cb8
  git branch      : selective-contact-reduction
  git dirty       : 0 modified files
  java            : openjdk version "1.8.0_504"
  ngrid           : 80,160,240,320,400,480
  reps per N      : 2
  shards          : 6
  ep structure    : both
  omega           : random
  gamma range     : 0.1..0.2
  alpha range     : config..config
  encounters      : 16
  centralities    : false
  platform        : MINGW64_NT-10.0-22631 (classpath separator ';')
  command         : ./batch/run-batch.sh --reps 2 --shards 6 --gamma-min 0.1 --gamma-max 0.2 --omega-random --ep-structure both --no-centralities --out /c/Users/astellbrink/java-workspace/nidm-simulation-sel/batch-runs/p3-smoke
  finished        : 2026-10-09T17:04:30+02:00
  ```

### 4c. Timing compared with the README's centralities-off column

| N | 80 | 160 | 240 | 320 | 400 | 480 |
|---|---|---|---|---|---|---|
| BOTH smoke, s/sim | 1.0 | 4.0 | 13.0 | 33.0 | 60.0 | 103.0 |
| README "off" (dynamic only) | 0.67 | 4.00 | 10.67 | 31.00 | 55.67 | 107.33 |
| ratio | 1.49 | 1.00 | 1.22 | 1.06 | 1.08 | 0.96 |

The static arm adds almost nothing: about 1.0–1.2× at N ≥ 160. The N = 80
figure is dominated by JVM startup (2 s for the whole shard). Caveats: only
2 sims per N; the times include startup; the 6 shards ran concurrently,
whereas the README figures are contention-free serial; and outbreak length
varies with the γ draw (the N = 320 shard drew γ ≈ 0.10, N = 480 drew
γ ≈ 0.19).

**Projection.** Run A's chunks on this machine (K = 16, 2g) took 12h49,
11h20, 11h31, 10h27 and 11h08; Run B's took 11h55, 11h20, 11h25, 10h55 and
10h51. At 1.0–1.2× that puts p3 at roughly **11–14 h per chunk, about
2.4–3 days of compute for 5 chunks**, plus any time lost to restarts. The
band also concentrates γ at the low end, where outbreaks last longer than in
Run A's U[0.1, 0.4], so expect the upper half of that range.

Warning from the Run A/B logs: chunk 4 of each run was interrupted (Run A
stalled from 2026-08-30 00:48 to 09-01 11:06, Run B from 09-03 22:43 to
09-04 16:48). After a reboot nothing resumes on its own until someone re-runs
`./batch/phase2.sh p3`. Check on it daily.

### 4d. Tarball for analysis-side development

`batch-runs/p3-smoke.tgz` holds `split/` (6 shard directories, each with
`config.properties` and `data/nunnerbuskens/{simulation,round}-summary.csv`)
and `batch-info.txt`; 38 entries, 53,026 B.

```
SHA-256  0322ad6b390e4fd961ca1bacb3b0a46d3795ae7371c25a3aa18f4d4cc037f958  p3-smoke.tgz
```

## 5. Analysis repo next to the clone: install path checked, not run

`../SelSWIDM-analysis` **exists** on this machine (HEAD `7af1e18`). Part B
step 5 assumed it didn't, so the driver **will auto-install** at the end
(`INSTALL` defaults to 1). I read the driver; I did not run it.

- `run-phase2.sh` accepts only the arms `runA`, `runB` and `p3`. The install
  block checks `INSTALL != 1` → stage only; no analysis repo → stage only;
  `ARM = p3` → the p3 branch. The p3 branch is taken before the generic
  `else` branch, which is the only one containing
  `rm -rf "$ANALYSIS/data/split"`, `rm -f "$ANALYSIS"/data/*.csv` and
  `rm -rf "$ANALYSIS/_targets"`.
- The p3 branch only does `mkdir -p data/phase3/{split,provenance}`,
  `cp -r merged/* data/phase3/split/`, `cp provenance/* data/phase3/provenance/`,
  and writes `data/phase3/split/.arm`. It contains no `rm`. If
  `data/phase3/split` exists and is non-empty, it logs, deletes nothing and
  exits 1.
- The driver's other `rm -rf` calls (`$ROOT/c$i`, `merged/c$i-*`,
  `provenance/c$i-*`) all fall under `nidm-simulation-sel/batch-runs/p3/`.
- No `CHUNKS`/`REPS`/`SHARDS`/`HEAP`/`NGRID`/`ANALYSIS`/`INSTALL` variables
  are set in the environment, so the defaults apply (with `SHARDS=16` set
  explicitly).
- The analysis reads each design with
  `list.dirs(<split>, recursive = FALSE)`, so `data/phase3/` cannot leak into
  the `main` (`./data/split`) design.
- `data/phase3/` does not exist yet. **If you unpack `p3-smoke.tgz` into
  `data/phase3/split` on this machine for reader development, the final
  install will refuse** (safe, but staged only). Use a different directory,
  such as `data/phase3-smoke/`, or develop on the laptop.

**Unrelated, but worth knowing:** on this machine,
`SelSWIDM-analysis/data/split/.arm` reads **`runB`** (written 2026-09-07
14:31:31), and the configs in it have `nb.omega.random=false`,
`nb.omega=0`. The cached `data/*.csv` merges are dated 14:32–14:36, just
after that install. The README and `DESIGNS$main` treat `data/split` as
Run A, and `DESIGNS$w0` points at `./data/runB/merged`, which doesn't exist
here. Run A's install (14:17) was replaced by Run B's 14 minutes later. So
any `main` result computed from this machine's copy is Run B data. I changed
nothing there.

## 6. Launch: not done, blocked

- tmux and screen are not installed (Windows / Git Bash). The driver detaches
  itself with `nohup`, which is what Runs A/B relied on.
- Claude Code's own processes run inside a Windows job object, so a `nohup`
  started from inside the session could be killed when the session closes.
  Starting it outside the job (via WMI `Win32_Process.Create` into a mintty
  window) was denied by Claude Code's permission classifier. I did not try
  other ways around that.

To launch, open a Git Bash window and run:

```sh
cd ~/java-workspace/nidm-simulation-sel
git status --short                     # must print nothing
SHARDS=16 ./batch/phase2.sh p3
```

This report is committed on top of `c3de40a`, so the tree is clean and every
chunk's `batch-info.txt` records `git dirty : 0` with the report commit's
hash as `git commit`. That commit only adds this file, so the Java sources
and harness are identical to `c3de40a`, which the jar was built from.
`git status --porcelain` counts untracked files as dirty, so keep the root
free of stray files until the run ends. `batch-runs/p3` does not exist yet.

After launch: Ctrl-C or closing the window stops only the display. For a
one-off status, run `./batch/progress.sh p3`. The full log, with each chunk's
`run-batch.sh` output and collect table, is in `batch-runs/p3/driver.log`.
Per-chunk work is under `batch-runs/p3/c<i>/` (`work/<shard>/shard.log`,
`batch-info.txt`), staging under `batch-runs/p3/merged/`, provenance under
`batch-runs/p3/provenance/`.

| | |
|---|---|
| launch time | — (not launched) |
| first `progress.sh p3` output | — |

## 7. Files created on this machine

- `batch-runs/p3-smoke/`: the smoke-test run (passed)
- `batch-runs/p3-smoke.tgz`: the smoke split plus `batch-info.txt` (SHA-256 above)
- `batch-runs/p3-smoke-failed-relative-out/`: the failed relative-path attempt
- `PHASE3_REPORT.md`: this file, committed and pushed (report only, no code
  changes)

## 8. Completion (separate session)

To fill in after `=== p3 complete: 60000 simulations across 5 chunks ===`:
first chunk's `started` and last chunk's `finished` (from
`provenance/c*-batch-info.txt`), redone chunks (`FAILED` / `INCOMPLETE` in
`driver.log`), per-shard exit codes and elapsed times from each collect
table, rows per N (10,000 each, 60,000 total), `p3-split.tgz` SHA-256, and
the result of the auto-install into `SelSWIDM-analysis/data/phase3/`.
