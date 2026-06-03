# config.R
# Project-wide configuration: path constants, the global seed, and the intended
# parallelism level. Sourced at startup by .Rprofile.
#
# This file defines constants only. It does NOT set the RNG state and does NOT
# mutate global options or thread counts (that side effect lives in .Rprofile,
# which applies MC_CORES after sourcing this file), so sourcing config.R has no
# hidden global state and is safe to re-source.

# --- Paths (all relative to the repo root via here::here) -------------------
# here::here() anchors on the .Rproj / .git at the repo root.

DATA_RAW       <- here::here("data", "raw")
DATA_INTERIM   <- here::here("data", "interim")
DATA_PROCESSED <- here::here("data", "processed")
DATA_SYNTHETIC <- here::here("data", "synthetic")

OUTPUTS         <- here::here("outputs")
OUT_STAN_DATA   <- file.path(OUTPUTS, "stan_data")
OUT_MODEL_FITS  <- file.path(OUTPUTS, "model_fits")
OUT_DIAGNOSTICS <- file.path(OUTPUTS, "diagnostics")
OUT_ESTIMATES   <- file.path(OUTPUTS, "estimates")
OUT_FIGURES     <- file.path(OUTPUTS, "figures")
OUT_TABLES      <- file.path(OUTPUTS, "tables")
OUT_LOGS        <- file.path(OUTPUTS, "logs")

STAN_DIR <- here::here("code", "03_modeling", "stan")

# --- Reproducibility --------------------------------------------------------
# One global seed. Orchestration scripts and _targets.R pass this explicitly to
# every stochastic step: the synthetic-data generator and recovery test pass it
# (or a documented offset) to simulate_tb_dataset()/simulate_tb_counts(), and
# fit_models.R passes it to cmdstanr $sample(seed = ...). Do not call set.seed()
# here: the RNG state stays out of global scope, set only at explicit call sites.

GLOBAL_SEED <- 20240603L

# --- Data definitions (load-bearing; see literature/notes/priors.md) ---------
# The canonical, single-source-of-truth definitions of what is counted. The
# orchestration script passes these explicitly to the loaders so the inclusion
# rules are never implicit. Changing them changes the estimand; do not edit
# without updating priors.md and re-running /review.

# TB death = underlying cause ICD-10 A15-A19 only (active TB; excludes B90
# sequelae). PI decision 2026-06-03.
TB_DEATH_ICD3 <- c("A15", "A16", "A17", "A18", "A19")

# SINAN notification numerator = TRATAMENTO (Tipo de Entrada) new case (1) +
# relapse (2) only; excludes re-entry/unknown/transfer/post-mortem. Version-safe
# across SINAN v4/v5. PI decision 2026-06-03.
SINAN_ENTRY_KEEP_CODES <- c("1", "2")

# --- Analysis window defaults -----------------------------------------------
# Default to a pre-COVID-stable window. The 2020-2021 disruption
# (chitwood2025) must be handled explicitly before extending across it. The
# orchestration script reads env vars TB_YEAR_START/TB_YEAR_END/TB_UF and falls
# back to these.
YEAR_START_DEFAULT <- 2015L
YEAR_END_DEFAULT   <- 2019L
UF_DEFAULT         <- "all"

# --- Parallelism ------------------------------------------------------------
# Intended core count: all but one locally; the cluster sbatch template
# overrides this. The actual options(mc.cores = ) / setDTthreads() side effect
# is applied by .Rprofile after sourcing this file, not here.

MC_CORES <- max(1L, parallel::detectCores() - 1L)
