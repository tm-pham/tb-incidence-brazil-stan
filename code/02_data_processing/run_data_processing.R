#!/usr/bin/env Rscript
# run_data_processing.R
# Orchestration script (side-effecting: reads DATASUS/IBGE, writes outputs/).
# Wires the loaders into prepare_stan_data() and saves the Stan data list.
#
# This is the script layer: the functions it calls are side-effect free and
# tested; this script does the reading, calling, and writing (CLAUDE.md).
#
# WHERE TO RUN: on a machine with DATASUS + IBGE network access and the
# microdatasus/sidrar packages installed (the Mac or the cluster). The web
# container has neither, so the fetch steps will stop early there by design.
#
# Usage:
#   Rscript code/02_data_processing/run_data_processing.R
# Optionally override the year range / states via environment variables:
#   TB_YEAR_START, TB_YEAR_END, TB_UF (comma-separated, or "all").

suppressPackageStartupMessages({
  library(data.table)
  library(here)
})

source(here::here("code", "00_config", "config.R"))
source(here::here("code", "02_data_processing", "load_notifications.R"))
source(here::here("code", "02_data_processing", "load_sim.R"))
source(here::here("code", "02_data_processing", "load_population.R"))
source(here::here("code", "02_data_processing", "prepare_stan_data.R"))

# --- Parameters -------------------------------------------------------------
# Year range and states. Defaults (config.R) cover a pre-COVID-stable window;
# override via env vars. The 2020-2021 COVID disruption (chitwood2025) should be
# handled explicitly in the model before extending across it, not just by
# widening this window.
year_start <- as.integer(Sys.getenv("TB_YEAR_START", as.character(YEAR_START_DEFAULT)))
year_end   <- as.integer(Sys.getenv("TB_YEAR_END", as.character(YEAR_END_DEFAULT)))
uf_env     <- Sys.getenv("TB_UF", UF_DEFAULT)
uf         <- if (uf_env == "all") "all" else strsplit(uf_env, ",")[[1]]
years      <- seq.int(year_start, year_end)

# NOTE (treatment-outcome priors): if a prior year (e.g. year_start - 1) is ever
# pulled to inform p_death_tx / p_ltfu, fetch it with a SEPARATE
# load_sinan_tb_notifications() call and DO NOT pass it to prepare_stan_data();
# mixing it into the main notification counts would double-count cases.

message("Data processing for years ", year_start, "-", year_end,
        " (uf = ", paste(uf, collapse = ", "), ")")

# --- Load the three sources -------------------------------------------------
# Notifications: new + relapse treatment initiations (SINAN_ENTRY_KEEP_CODES).
message("Fetching SINAN notifications ...")
notifications <- load_sinan_tb_notifications(year_start, year_end,
                                             keep_entry = SINAN_ENTRY_KEEP_CODES,
                                             uf = uf)

# Deaths: underlying cause A15-A19 (TB_DEATH_ICD3).
message("Fetching SIM deaths ...")
deaths <- load_sim_deaths(year_start, year_end, uf = uf, icd3 = TB_DEATH_ICD3)

# Population: IBGE municipal estimates (the person-time denominator).
message("Fetching IBGE population ...")
population <- load_ibge_population(years)

# --- Assemble and validate the Stan data list -------------------------------
message("Assembling Stan data ...")
stan_data <- prepare_stan_data(
  notifications = notifications,
  deaths        = deaths,
  population    = population,
  year_range    = c(year_start, year_end)
)

# --- Write outputs ----------------------------------------------------------
dir.create(OUT_STAN_DATA, recursive = TRUE, showWarnings = FALSE)
out_rds <- file.path(OUT_STAN_DATA, "tb_stan_data.rds")
if (file.exists(out_rds)) {
  message("NOTE: overwriting existing ", out_rds,
          " (DATASUS/IBGE may have been revised since the last run).")
}
saveRDS(stan_data, out_rds)

# Local null-coalesce (base R's %||% is only available from R 4.4.0).
`%or%` <- function(a, b) if (is.null(a)) b else a

pkg_ver <- function(p) {
  if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p))
  else "not installed"
}

# Human-readable processing report. Records the data vintage and tool versions
# so a given tb_stan_data.rds can be traced to a specific fetch: DATASUS/IBGE
# revise historical records, so the same year range can yield different counts
# on different dates.
report <- c(
  "== TB data processing report ==",
  sprintf("fetched at:           %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  sprintf("years:                %d-%d", year_start, year_end),
  sprintf("uf:                   %s", paste(uf, collapse = ", ")),
  sprintf("municipalities:       %d", stan_data$n_areas),
  sprintf("years (n):            %d", stan_data$n_years),
  sprintf("municipality-years:   %d", stan_data$N),
  sprintf("total notifications:  %d", sum(stan_data$notifications)),
  sprintf("total deaths:         %d", sum(stan_data$deaths)),
  sprintf("notif cells 0-filled: %d", stan_data$report$notifications_zero_filled),
  sprintf("death cells 0-filled: %d", stan_data$report$deaths_zero_filled),
  sprintf("notif residence-fallback rows: %s",
          attr(notifications, "n_residence_fallback") %or% NA),
  sprintf("death residence-fallback rows: %s",
          attr(deaths, "n_residence_fallback") %or% NA),
  "-- vintage --",
  sprintf("R:                    %s", R.version.string),
  sprintf("microdatasus:         %s", pkg_ver("microdatasus")),
  sprintf("sidrar:               %s (SIDRA table 6579, var 9324)", pkg_ver("sidrar")),
  sprintf("data.table / here:    %s / %s", pkg_ver("data.table"), pkg_ver("here")),
  sprintf("written:              %s", out_rds)
)
dir.create(OUT_LOGS, recursive = TRUE, showWarnings = FALSE)
writeLines(report, file.path(OUT_LOGS, "data_processing_report.txt"))
message(paste(report, collapse = "\n"))
message("Done.")
