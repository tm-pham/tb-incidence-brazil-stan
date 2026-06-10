#!/bin/bash
# fit_all_states.slurm -- fit all 27 states as a SLURM job array on CHPC/Notchpeak.
# One array task per state, 4 CPUs/task (4 parallel chains). Each task runs the
# single-state path (01_fit_one_state.R) with the PRODUCTION sampler config.
#
# Submit the compile job FIRST, then the array with a dependency so the 27 tasks
# reuse one cached Stan binary instead of racing to compile:
#
#   cid=$(sbatch --parsable --wrap "Rscript code/03_modeling/00_precompile_model.R")
#   sbatch --dependency=afterok:$cid code/00_chpc_scripts/fit_all_states.slurm
#
# Fill in <ACCOUNT>/<PARTITION> for your allocation before submitting.

#SBATCH --job-name=tb_fit_states
#SBATCH --array=1-27
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --account=<ACCOUNT>
#SBATCH --partition=<PARTITION>
#SBATCH --output=logs/fit_uf_%a.out
#SBATCH --error=logs/fit_uf_%a.err

set -euo pipefail
mkdir -p logs

# The 27 federative-unit codes, in UF_CODES order (config.R). Array index 1..27
# selects one. Keep in sync with config.R::UF_CODES.
UFS=(11 12 13 14 15 16 17 \
     21 22 23 24 25 26 27 28 29 \
     31 32 33 35 \
     41 42 43 \
     50 51 52 53)
UF=${UFS[$((SLURM_ARRAY_TASK_ID - 1))]}

# Production sampler config: diagonal metric (dense_e was tested and rejected --
# it wrecked mixing; the incidence<->detection ridge is intrinsic). diag_e gives
# valid draws at the cost of treedepth saturation. See 02_fit_all_states.R.
export TB_FIT_UF=$UF
export TB_FIT_METRIC=diag_e
export TB_FIT_WARMUP=4000
export TB_FIT_SAMPLING=2000
export TB_FIT_ADAPT_DELTA=0.95
export TB_FIT_TREEDEPTH=12
export TB_FIT_CHAINS=4
unset TB_FIT_FAST

echo "Array task $SLURM_ARRAY_TASK_ID -> uf $UF on $(hostname) at $(date)"
Rscript code/03_modeling/01_fit_one_state.R
echo "uf $UF done at $(date)"
