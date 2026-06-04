# Data processing

Builds the Stan data list (notifications, deaths, and the IBGE person-time
offset, plus the IDC / treatment-outcome / GeneXpert covariates) from SINAN, SIM,
and IBGE.

Target: the **state x year-month** panel (27 states x 252 months, 2003-2023).
Record-oriented: one pull of each source serves both counts and covariates.

**Sources.** SINAN-TB notifications are read from the PI's local export in
`data/raw/TB_notifications/` (`.dbc`/`.dbf`/`.csv`/`.rds`) -- SINAN-TB is not
served by `microdatasus`. SIM **all-cause** mortality is fetched from DATASUS
(via `microdatasus`, serving both TB deaths and the ill-defined-cause fraction)
and IBGE state population from SIDRA (via `sidrar`). So a run needs the
notification export present locally **plus** network access for SIM and IBGE.

## Two kinds of file here

- **Function libraries** (no number prefix): side-effect-free, sourced not run.
  - `geo_utils.R` -- code reconciliation, residence fallback, `uf_from_muni()`
  - `load_notifications.R` -- `standardise_sinan_tb()` records, then
    `summarise_notifications()`, `treatment_outcomes()`, `genexpert_share()`
  - `load_sim.R` -- `standardise_sim()` all-cause records, then
    `filter_tb_deaths()` (A15-A19) and `idc_fraction()` (ill-defined causes)
  - `load_population.R` -- `tidy_state_population()` + `expand_population_monthly()`
  - `prepare_stan_data.R` -- assembles the 27 x 252 panel; `stan_data_for_state()`
    slices one state's series for fitting
- **Scripts** (number prefix = run order): thin drivers over the targets DAG.
  - `01_fetch_raw.R` -- STEP 1: local SINAN + SIM/IBGE fetch -> `data/interim/`
  - `02_assemble_stan_data.R` -- STEP 2, offline: `data/interim/` -> `outputs/`

The numbers are on the **scripts you run**, not the function files (those are a
library; you never run them in sequence).

## How to run

Canonical (handles order and caching automatically), from the repo root:

```r
targets::tar_make()
```

Or run the numbered scripts in order (STEP 1 needs the network + microdatasus /
sidrar; STEP 2 is offline and re-runnable from the cache):

```bash
Rscript code/02_data_processing/01_fetch_raw.R
Rscript code/02_data_processing/02_assemble_stan_data.R
```

Override the analysis window with environment variables (defaults in
`code/00_config/config.R`):

```bash
TB_YEAR_START=2015 TB_YEAR_END=2019 TB_UF=all Rscript code/02_data_processing/01_fetch_raw.R
```

The pipeline itself (the single source of truth for run order) is `_targets.R`
at the repo root.
