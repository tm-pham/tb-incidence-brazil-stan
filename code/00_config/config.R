# config.R
# Project-wide configuration: path constants, the global seed, and parallelism.
# Sourced at startup by .Rprofile. Defines constants only; it does not set the
# RNG state (seeds are passed explicitly to stochastic steps, never set globally
# here) so there is no hidden global state.

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
# One global seed, used explicitly by scripts and passed to every stochastic
# step (simulator draws, cmdstanr $sample(seed = ...)). Do not call set.seed()
# here: keep the RNG state out of global scope.

GLOBAL_SEED <- 20240603L

# --- Parallelism ------------------------------------------------------------
# Default to all but one core locally; the cluster sbatch template overrides
# this. data.table threads kept in step.

MC_CORES <- max(1L, parallel::detectCores() - 1L)
options(mc.cores = MC_CORES)
data.table::setDTthreads(MC_CORES)
