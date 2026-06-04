#!/usr/bin/env Rscript
# 02_assemble_stan_data.R  --  STEP 2 of data processing (DETERMINISTIC).
#
# Assembles the state x year-month panel (27 x 252, 2003-2023) from the cached
# raw records (data/interim/) via prepare_stan_data(), then writes
# outputs/stan_data/tb_state_month_panel.rds and a report to outputs/logs/. This
# step is offline and re-runnable; it needs no network.
#
# If the raw cache is missing or stale, targets will run STEP 1 first
# automatically (so this also needs the network in that case).
#
# Thin driver over the targets DAG in _targets.R. Equivalent canonical command:
#   targets::tar_make(names = "stan_panel_file")

targets::tar_make(names = "stan_panel_file")
