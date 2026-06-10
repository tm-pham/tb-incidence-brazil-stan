#!/usr/bin/env Rscript
# 00_precompile_model.R -- compile tb_state_month.stan ONCE.
# Run this before the SLURM array (fit_all_states.slurm) so the 27 parallel tasks
# reuse one cached binary instead of racing to compile it. cmdstanr caches the
# executable next to the .stan file, so a single compile here is enough.

suppressMessages(library(here))
source(here("code", "00_config", "config.R"))
source(here("code", "03_modeling", "fit_models.R"))
m <- compile_tb_model()
cat("compiled:", m$exe_file(), "\ncmdstan:", cmdstanr::cmdstan_version(), "\n")
