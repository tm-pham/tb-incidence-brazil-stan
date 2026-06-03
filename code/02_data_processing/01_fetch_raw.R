#!/usr/bin/env Rscript
# 01_fetch_raw.R  --  STEP 1 of data processing (NETWORKED).
#
# Pulls SINAN notifications, SIM deaths, and IBGE population from DATASUS/IBGE
# and caches the raw, standardised tables to data/interim/ (the reproducibility
# boundary). Run this on a machine with network access and microdatasus/sidrar
# installed (the Mac or the cluster). Re-run only when you want fresh data;
# STEP 2 then re-runs offline from the cache.
#
# Override the window with env vars: TB_YEAR_START, TB_YEAR_END, TB_UF.
#
# This is a thin driver over the targets DAG defined in _targets.R (the single
# source of truth for run order). Equivalent canonical command:
#   targets::tar_make(names = c("raw_notifications", "raw_deaths", "raw_population"))

targets::tar_make(
  names = c("raw_notifications", "raw_deaths", "raw_population")
)
