#!/bin/sh
#SBATCH --job-name=selcor-final
#SBATCH --partition=defq
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=96G
#SBATCH --time=4-01:00:00
#SBATCH --no-requeue
#SBATCH --output=slurm-%x-%j.out
#
# Final re-run batches on the AI-Lab cluster (S9, 2 Nov 2026): one job per batch, all of it
# in batch/slurm/final.sh. No --gres: the simulation uses no GPU. Submit from the root of the
# unpacked bundle (sbatch runs a copy of this file from Slurm's spool directory, so the bundle
# is found through $SLURM_SUBMIT_DIR), with --time and, for exa80 and the tie batches, --mem
# and --cpus-per-task per batch as in batch/README.md, "Running on the AI-Lab cluster":
#
#   sbatch --dependency=singleton --time=4-01:00:00 --mem=96G batch/slurm/final.sbatch main
#
# The defaults above are main's: 64 CPUs (Slurm counts both threads of a core, so 32 cores),
# one shard per CPU; --mem = 64 shards x 1.5 GB (a 1g shard can take its whole heap plus about
# 0.2 GB outside it, plus a margin; see "Memory" in the README); --time = the main batch's
# projection at its slow end x 1.5 (README, "Projections"). --no-requeue: a
# batch cannot be resumed, so a job that fails stays failed instead of restarting into a
# half-written batch folder (final.sh would stop there anyway).

cd "$SLURM_SUBMIT_DIR" || exit 1
[ -f batch/slurm/final.sh ] || { echo "submit from the root of the unpacked bundle (no batch/slurm/final.sh in $SLURM_SUBMIT_DIR)"; exit 1; }
exec sh batch/slurm/final.sh "$@"
