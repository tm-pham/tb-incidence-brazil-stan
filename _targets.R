# _targets.R: end-to-end pipeline (targets package). Single source of truth for
# run order; run with `targets::tar_make()` from the repo root.
#
# Current stages: data processing (fetch -> assemble). Modelling, diagnostics,
# and analysis are commented placeholders wired up in later phases.
#
# Layout note: the files in code/02_data_processing/ split into side-effect-free
# FUNCTION libraries (geo_utils.R, load_*.R, prepare_stan_data.R), sourced below,
# and numbered convenience SCRIPTS (01_fetch_raw.R, 02_assemble_stan_data.R) that
# just drive subsets of this DAG. The functions are the building blocks; this
# file does the calling, reading, and writing.

library(targets)

source(here::here("code", "00_config", "config.R"))
for (f in c("geo_utils.R", "load_notifications.R", "load_sim.R",
            "load_population.R", "prepare_stan_data.R")) {
  source(here::here("code", "02_data_processing", f))
}

tar_option_set(packages = c("data.table", "here"))

list(
  # --- Analysis window (env vars, config defaults). always-cue so a changed
  # window is re-read on the next tar_make().
  tar_target(
    year_start,
    as.integer(Sys.getenv("TB_YEAR_START", as.character(YEAR_START_DEFAULT))),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    year_end,
    as.integer(Sys.getenv("TB_YEAR_END", as.character(YEAR_END_DEFAULT))),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    uf,
    { e <- Sys.getenv("TB_UF", UF_DEFAULT)
      if (e == "all") "all" else strsplit(e, ",")[[1]] },
    cue = tar_cue(mode = "always")
  ),
  tar_target(years, seq.int(year_start, year_end)),

  # --- Notifications: LOCAL SINAN-TB export (NOT a network pull; microdatasus
  # does not serve SINAN-TUBERCULOSE). Track the source file(s) so a new export
  # re-triggers processing, then cache the standardised counts to data/interim/.
  tar_target(
    notification_files,
    list.files(file.path(DATA_RAW, "TB_notifications"),
               pattern = "[.](rds|csv|csv\\.gz|dbf|dbc)$",
               full.names = TRUE, ignore.case = TRUE),
    format = "file"
  ),
  tar_target(
    raw_notifications_file,
    {
      dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
      d <- load_sinan_tb_notifications(notification_files,
                                       keep_entry = SINAN_ENTRY_KEEP_CODES)
      p <- file.path(DATA_INTERIM, "raw_notifications.rds")
      saveRDS(d, p); p
    },
    format = "file"
  ),
  tar_target(raw_notifications, readRDS(raw_notifications_file)),

  # --- STEP 1 (networked): SIM deaths and IBGE population. Raw pulls cached to
  # data/interim/ as the reproducibility boundary (run on the Mac/cluster; needs
  # microdatasus + sidrar). format = "file" makes targets track the cached file.
  tar_target(
    raw_deaths_file,
    {
      dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
      d <- load_sim_deaths(year_start, year_end, uf = uf, icd3 = TB_DEATH_ICD3)
      p <- file.path(DATA_INTERIM, "raw_deaths.rds")
      saveRDS(d, p); p
    },
    format = "file"
  ),
  tar_target(raw_deaths, readRDS(raw_deaths_file)),

  tar_target(
    raw_population_file,
    {
      dir.create(DATA_INTERIM, recursive = TRUE, showWarnings = FALSE)
      d <- load_ibge_population(years)
      p <- file.path(DATA_INTERIM, "raw_population.rds")
      saveRDS(d, p); p
    },
    format = "file"
  ),
  tar_target(raw_population, readRDS(raw_population_file)),

  # --- STEP 2: deterministic assembly (offline, re-runnable from the cache).
  tar_target(
    stan_data,
    prepare_stan_data(notifications = raw_notifications,
                      deaths = raw_deaths,
                      population = raw_population,
                      year_range = c(year_start, year_end))
  ),

  # Write the Stan data list and a vintage-stamped processing report.
  tar_target(
    stan_data_file,
    {
      dir.create(OUT_STAN_DATA, recursive = TRUE, showWarnings = FALSE)
      dir.create(OUT_LOGS, recursive = TRUE, showWarnings = FALSE)
      p <- file.path(OUT_STAN_DATA, "tb_stan_data.rds")
      saveRDS(stan_data, p)
      pkg_ver <- function(x) if (requireNamespace(x, quietly = TRUE)) {
        as.character(utils::packageVersion(x)) } else "not installed"
      fb <- function(d) {
        v <- attr(d, "n_residence_fallback"); if (is.null(v)) NA else v
      }
      report <- c(
        "== TB data processing report ==",
        sprintf("fetched at:           %s",
                format(Sys.time(), tz = "UTC", usetz = TRUE)),
        sprintf("years:                %d-%d", year_start, year_end),
        sprintf("uf:                   %s", paste(uf, collapse = ", ")),
        sprintf("municipalities:       %d", stan_data$n_areas),
        sprintf("years (n):            %d", stan_data$n_years),
        sprintf("municipality-years:   %d", stan_data$N),
        sprintf("total notifications:  %d", sum(stan_data$notifications)),
        sprintf("total deaths:         %d", sum(stan_data$deaths)),
        sprintf("notif cells 0-filled: %d",
                stan_data$report$notifications_zero_filled),
        sprintf("death cells 0-filled: %d",
                stan_data$report$deaths_zero_filled),
        sprintf("notif residence-fallback rows: %s", fb(raw_notifications)),
        sprintf("death residence-fallback rows: %s", fb(raw_deaths)),
        "-- vintage --",
        sprintf("R:                    %s", R.version.string),
        sprintf("microdatasus:         %s", pkg_ver("microdatasus")),
        sprintf("sidrar:               %s (SIDRA 6579, var 9324)",
                pkg_ver("sidrar")),
        sprintf("data.table / here:    %s / %s",
                pkg_ver("data.table"), pkg_ver("here"))
      )
      writeLines(report, file.path(OUT_LOGS, "data_processing_report.txt"))
      p
    },
    format = "file"
  )

  # --- Phase 4+ (placeholders, wired up with the Stan model):
  # tar_target(fit, fit_base_model(stan_data, seed = GLOBAL_SEED)),
  # tar_target(diagnostics, run_diagnostics(fit)),
  # tar_target(estimates, extract_estimates(fit, stan_data$key)),
)
