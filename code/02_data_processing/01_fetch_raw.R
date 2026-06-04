#!/usr/bin/env Rscript
# 01_fetch_raw.R  --  STEP 1 of data processing (prepare the raw inputs).
#
# Caches the raw, standardised tables to data/interim/ (the reproducibility
# boundary):
#   * notifications -- read from the LOCAL SINAN-TB export in
#     data/raw/TB_notifications/ (SINAN-TB is not served by microdatasus)
#   * deaths (SIM) and population (IBGE) -- fetched from DATASUS/IBGE
# So this needs the notification export present locally AND network access for
# SIM and IBGE (microdatasus/sidrar installed). Run on the Mac or the cluster.
# Re-run only when sources change; STEP 2 then re-runs offline from the cache.
#
# Override the window with env vars: TB_YEAR_START, TB_YEAR_END, TB_UF.
#
# This is a thin driver over the targets DAG defined in _targets.R (the single
# source of truth for run order). Equivalent canonical command:
#   targets::tar_make(names = c("sinan_records_file", "sim_records_file", "population_annual_file"))

targets::tar_make(
  names = c("sinan_records_file", "sim_records_file", "population_annual_file")
)
