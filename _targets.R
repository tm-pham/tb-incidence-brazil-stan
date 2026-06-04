# _targets.R: end-to-end pipeline (targets package). Single source of truth for
# run order; run with `targets::tar_make()` from the repo root.
#
# State-month, 2003-2023. SINAN notifications are read from the local export
# (not served by microdatasus); SIM all-cause deaths are fetched once and serve
# both the TB-death counts and the ill-defined-cause (IDC) fraction; IBGE state
# population is expanded to monthly person-time. The assembly builds the 27 x 252
# panel; per-state Stan fits are wired in the modelling phase.

library(targets)

source(here::here("code", "00_config", "config.R"))
for (f in c("geo_utils.R", "load_notifications.R", "load_sim.R",
            "load_population.R", "prepare_stan_data.R")) {
  source(here::here("code", "02_data_processing", f))
}

tar_option_set(packages = c("data.table", "here"))

list(
  # --- Analysis window (env vars, config defaults; always-cue so a changed
  # window is re-read on the next tar_make()).
  tar_target(year_start,
             as.integer(Sys.getenv("TB_YEAR_START", as.character(YEAR_START_DEFAULT))),
             cue = tar_cue(mode = "always")),
  tar_target(year_end,
             as.integer(Sys.getenv("TB_YEAR_END", as.character(YEAR_END_DEFAULT))),
             cue = tar_cue(mode = "always")),
  tar_target(uf,
             { e <- Sys.getenv("TB_UF", UF_DEFAULT)
               if (e == "all") "all" else strsplit(e, ",")[[1]] },
             cue = tar_cue(mode = "always")),
  tar_target(years, seq.int(year_start, year_end)),

  # --- Notifications: LOCAL SINAN-TB export (not a network pull). Track the
  # source files, cache the standardised records, then derive counts and the
  # detection / treatment-outcome covariates from the one record set.
  tar_target(notification_files,
             list.files(file.path(DATA_RAW, "TB_notifications"),
                        pattern = "[.](rds|csv|csv\\.gz|dbf|dbc)$",
                        full.names = TRUE, ignore.case = TRUE),
             format = "file"),
  tar_target(sinan_records_file, {
    dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
    d <- load_sinan_records(notification_files)
    p <- file.path(DATA_INTERIM, "sinan_records.rds"); saveRDS(d, p); p
  }, format = "file"),
  tar_target(sinan_records, readRDS(sinan_records_file)),
  tar_target(notifications, summarise_notifications(sinan_records, SINAN_ENTRY_KEEP_CODES)),
  tar_target(treatment, treatment_outcomes(sinan_records, SINAN_ENTRY_KEEP_CODES)),
  tar_target(genexpert, genexpert_share(sinan_records, SINAN_ENTRY_KEEP_CODES)),

  # --- SIM all-cause deaths: networked fetch, cached to data/interim. Serves
  # both the TB-death counts and the ill-defined-cause fraction.
  tar_target(sim_records_file, {
    dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
    d <- load_sim_records(year_start, year_end, uf = uf)
    p <- file.path(DATA_INTERIM, "sim_records.rds"); saveRDS(d, p); p
  }, format = "file"),
  tar_target(sim_records, readRDS(sim_records_file)),
  tar_target(tb_deaths, filter_tb_deaths(sim_records, TB_DEATH_ICD3)),
  tar_target(idc, idc_fraction(sim_records, IDC_ICD_PREFIX)),

  # --- IBGE state population -> monthly person-time.
  tar_target(population_annual_file, {
    dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
    d <- load_ibge_state_population(years)
    p <- file.path(DATA_INTERIM, "population_annual.rds"); saveRDS(d, p); p
  }, format = "file"),
  tar_target(population_annual, readRDS(population_annual_file)),
  tar_target(population_monthly,
             expand_population_monthly(population_annual, year_start, year_end)),

  # --- Assemble the 27 x 252 state-month panel.
  tar_target(assembled,
             prepare_stan_data(notifications = notifications,
                               deaths = tb_deaths,
                               population = population_monthly,
                               idc = idc, genexpert = genexpert,
                               treatment = treatment,
                               year_start = year_start, year_end = year_end,
                               uf_codes = UF_CODES,
                               covid_break_year = COVID_BREAK_YEAR,
                               covid_break_month = COVID_BREAK_MONTH)),

  tar_target(stan_panel_file, {
    dir.create(OUT_STAN_DATA, recursive = TRUE, showWarnings = FALSE)
    dir.create(OUT_LOGS, recursive = TRUE, showWarnings = FALSE)
    p <- file.path(OUT_STAN_DATA, "tb_state_month_panel.rds")
    saveRDS(assembled, p)
    r <- assembled$report
    writeLines(c(
      "== TB state-month data processing report ==",
      sprintf("fetched at:        %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      sprintf("states x months:   %d x %d", r$n_states, r$n_months),
      sprintf("cells:             %d", r$n_cells),
      sprintf("total notifications: %d", sum(assembled$panel$notifications)),
      sprintf("total TB deaths:   %d", sum(assembled$panel$deaths)),
      sprintf("notif zero-filled: %d", r$notifications_zero_filled),
      sprintf("death zero-filled: %d", r$deaths_zero_filled),
      sprintf("idc NA cells:      %s", r$idc_missing),
      sprintf("genexpert NA cells: %s", r$genexpert_missing),
      sprintf("treatment NA cells: %s", r$treatment_missing)
    ), file.path(OUT_LOGS, "data_processing_report.txt"))
    p
  }, format = "file")

  # --- Modelling phase (placeholders): per-state fits over assembled$states,
  # diagnostics, and the tidy state x year-month posterior-draw output.
  # tar_target(fit_by_state, fit_base_model(stan_data_for_state(assembled, uf),
  #            seed = GLOBAL_SEED), pattern = map(states))  # dynamic branching
)
