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

# GeneXpert detection covariate: SINAN variable TEST_MOLEC (Teste Molecular
# Rapido, TMR-TB). Codes 1=Detectable/Rif-sensitive, 2=Detectable/Rif-resistant,
# 3=Not detectable, 4=Inconclusive, 5=Not performed. "Diagnosed via GeneXpert"
# (share-among-notified) = the test was performed, i.e. a result exists (1-4).
# PI to confirm whether the numerator should instead be detection-positive (1,2).
SINAN_GENEXPERT_PERFORMED <- c("1", "2", "3", "4")

# Ill-defined causes of death (IDC) for the time-varying death adjustment:
# ICD-10 Chapter XVIII "causas mal definidas" (R00-R99), matched on the leading
# letter. PI to confirm the exact garbage-code set.
IDC_ICD_PREFIX <- "R"

# Study window and grid (state-month, 2003-2023). PI decision 2026-06-04: full
# 2003-2023 with wide early-year uncertainty (no pre-2008 cut).
YEAR_START_DEFAULT <- 2003L
YEAR_END_DEFAULT   <- 2023L
UF_DEFAULT         <- "all"

# The 27 federative units (states + DF), by 2-digit IBGE code. The canonical
# state-month grid is UF_CODES x (YEAR_START_DEFAULT..YEAR_END_DEFAULT) x 12.
UF_CODES <- c(11L, 12L, 13L, 14L, 15L, 16L, 17L,          # North
              21L, 22L, 23L, 24L, 25L, 26L, 27L, 28L, 29L, # Northeast
              31L, 32L, 33L, 35L,                          # Southeast
              41L, 42L, 43L,                               # South
              50L, 51L, 52L, 53L)                          # Centre-West

# 2-digit UF code -> postal abbreviation, for targeted DATASUS fetches
# (microdatasus::fetch_datasus takes state abbreviations, not codes).
UF_ABBREV <- c(`11` = "RO", `12` = "AC", `13` = "AM", `14` = "RR", `15` = "PA",
               `16` = "AP", `17` = "TO", `21` = "MA", `22` = "PI", `23` = "CE",
               `24` = "RN", `25` = "PB", `26` = "PE", `27` = "AL", `28` = "SE",
               `29` = "BA", `31` = "MG", `32` = "ES", `33` = "RJ", `35` = "SP",
               `41` = "PR", `42` = "SC", `43` = "RS", `50` = "MS", `51` = "MT",
               `52` = "GO", `53` = "DF")

# COVID structural break (level + slope change with recovery) at April 2020.
COVID_BREAK_YEAR  <- 2020L
COVID_BREAK_MONTH <- 4L

# Population denominators span the 2000/2010/2022 censuses. We assemble from
# IBGE/SIDRA: the annual intercensal ESTIMATES table (which excludes census /
# count years) PLUS the 2022 Census for the 2022 anchor (the census revised many
# state populations down from the projections). Remaining gap years (2007, 2010)
# and any year past the last anchor (2023) are interpolated / held by
# expand_population_monthly(). Table/variable IDs are config so they can be
# repointed without code surgery if the installed sidrar exposes different ones.
SIDRA_POP_ESTIMATE_TABLE      <- 6579L  # Estimativas de Populacao (annual)
SIDRA_POP_ESTIMATE_VARIABLE   <- 9324L  # Populacao residente estimada
SIDRA_POP_CENSUS2022_TABLE    <- 4709L  # Censo 2022: Populacao residente
SIDRA_POP_CENSUS2022_VARIABLE <- 93L    # Populacao residente (total)

# --- Parallelism ------------------------------------------------------------
# Intended core count: all but one locally; the cluster sbatch template
# overrides this. The actual options(mc.cores = ) / setDTthreads() side effect
# is applied by .Rprofile after sourcing this file, not here.

MC_CORES <- max(1L, parallel::detectCores() - 1L)
