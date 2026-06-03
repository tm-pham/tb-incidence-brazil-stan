# Data processing

Builds the municipality-by-year Stan data list (notifications, deaths, and the
IBGE person-time offset) from SINAN, SIM, and IBGE.

## Two kinds of file here

- **Function libraries** (no number prefix): side-effect-free, sourced not run.
  - `geo_utils.R` -- municipality-code reconciliation and residence fallback
  - `load_notifications.R` -- SINAN treatment-initiation counts
  - `load_sim.R` -- SIM TB-death counts (underlying cause A15-A19)
  - `load_population.R` -- IBGE population (the `gamma` offset)
  - `prepare_stan_data.R` -- assembly + validation into the Stan data list
- **Scripts** (number prefix = run order): thin drivers over the targets DAG.
  - `01_fetch_raw.R` -- STEP 1, networked: DATASUS/IBGE -> `data/interim/`
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
