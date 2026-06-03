#!/usr/bin/env Rscript
# 02_assemble_stan_data.R  --  STEP 2 of data processing (DETERMINISTIC).
#
# Assembles the municipality-by-year Stan data list from the cached raw tables
# (data/interim/) via prepare_stan_data(), then writes
# outputs/stan_data/tb_stan_data.rds and a vintage-stamped report to
# outputs/logs/. This step is offline and re-runnable; it needs no network.
#
# If the raw cache is missing or stale, targets will run STEP 1 first
# automatically (so this also needs the network in that case).
#
# Thin driver over the targets DAG in _targets.R. Equivalent canonical command:
#   targets::tar_make(names = "stan_data_file")

targets::tar_make(names = "stan_data_file")
