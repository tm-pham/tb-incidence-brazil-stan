# prepare_stan_data.R
# Side-effect-free assembly of the municipality-by-year Stan data list from the
# three processed sources: SINAN notification counts, SIM TB-death counts, and
# IBGE population (the person-time offset, gamma). No reading or writing here;
# the orchestration script loads the inputs and writes the output.
#
# Design contract (enforced loudly, per the data_integrity reviewer mandate):
#   * The IBGE population table defines the canonical municipality-by-year
#     universe. Every (municipality, year) with a known denominator is kept;
#     joins never drop a municipality.
#   * Notifications and deaths are LEFT-joined onto that universe. A cell with
#     no record means zero events, not missing data, so it is filled with 0 and
#     the number of fills is reported. NA handling is explicit, never silent.
#   * A notification or death for a (municipality, year) absent from the
#     population universe is an error (a code or year mismatch), reported with
#     the offending keys rather than silently dropped.
#   * Counts must be non-negative integers; population must be present and
#     strictly positive. Violations error with the offending rows.

source(here::here("code", "02_data_processing", "geo_utils.R"))

# --- Internal validation helpers -------------------------------------------

.is_count <- function(x) {
  is.numeric(x) && all(!is.na(x)) && all(x >= 0) && all(x == as.integer(x))
}

.require_cols <- function(dt, cols, what) {
  miss <- setdiff(cols, names(dt))
  if (length(miss)) {
    stop(what, ": missing required column(s): ", paste(miss, collapse = ", "),
         ".")
  }
  invisible(TRUE)
}

# --- Main assembly ----------------------------------------------------------

#' Assemble the Stan data list from processed counts and population.
#'
#' @param notifications data.table with columns `muni_code`, `year`,
#'   `notifications`.
#' @param deaths data.table with columns `muni_code`, `year`, `deaths`.
#' @param population data.table with columns `muni_code`, `year`, `population`.
#'   This is the canonical universe; population is continuous person-time.
#' @param covariates Optional data.table keyed by `muni_code` (+ optional
#'   `year`) of standardised area covariates. If supplied it must cover every
#'   municipality in the universe; otherwise an error lists the gaps.
#' @param year_range Optional length-2 integer vector `c(min, max)` to restrict
#'   the universe before assembly.
#' @param fill_missing_counts If TRUE (default) count cells with no record are
#'   filled with 0 and the count of fills is reported; if FALSE such cells are
#'   an error.
#' @return A list with the Stan data (`N`, `n_areas`, `n_years`, integer
#'   `area`/`year` indices, `notifications`, `deaths`, `population`, and
#'   `log_pop_offset` = log(population)), plus a `key` mapping indices to codes
#'   and a `report` of what was filled or coerced.
prepare_stan_data <- function(notifications, deaths, population,
                              covariates = NULL,
                              year_range = NULL,
                              fill_missing_counts = TRUE) {
  for (nm in c("notifications", "deaths", "population")) {
    if (!data.table::is.data.table(get(nm))) {
      stop("prepare_stan_data: `", nm, "` must be a data.table.")
    }
  }
  .require_cols(notifications, c("muni_code", "year", "notifications"),
                "notifications")
  .require_cols(deaths, c("muni_code", "year", "deaths"), "deaths")
  .require_cols(population, c("muni_code", "year", "population"), "population")

  # Work on copies; never mutate the caller's tables.
  pop <- data.table::copy(population)
  notif <- data.table::copy(notifications)
  dth <- data.table::copy(deaths)

  # Normalise keys to the common 6-digit code and integer year.
  for (d in list(pop, notif, dth)) {
    data.table::set(d, j = "muni_code", value = normalise_muni6(d$muni_code))
    data.table::set(d, j = "year", value = as.integer(d$year))
  }

  if (!is.null(year_range)) {
    if (length(year_range) != 2L) stop("year_range must be length 2.")
    yr <- as.integer(year_range)
    pop <- pop[year >= yr[1L] & year <= yr[2L]]
    notif <- notif[year >= yr[1L] & year <= yr[2L]]
    dth <- dth[year >= yr[1L] & year <= yr[2L]]
  }

  # --- Validate the population universe (the denominator) ------------------
  if (anyNA(pop$population)) {
    stop("prepare_stan_data: population has NA values; every (municipality, ",
         "year) in the universe needs a denominator.")
  }
  if (any(pop$population <= 0)) {
    bad <- pop[population <= 0]
    stop("prepare_stan_data: population must be strictly positive; ",
         nrow(bad), " offending row(s), e.g. muni ", bad$muni_code[1L],
         " year ", bad$year[1L], ".")
  }
  dup <- pop[, .N, by = .(muni_code, year)][N > 1L]
  if (nrow(dup)) {
    stop("prepare_stan_data: population has ", nrow(dup), " duplicated ",
         "(municipality, year) cell(s); the universe must be unique.")
  }

  data.table::setkey(pop, muni_code, year)

  # --- Orphan check: counts must live inside the population universe -------
  univ <- pop[, .(muni_code, year)]
  check_orphans <- function(d, what) {
    if (!nrow(d)) return(invisible(TRUE))
    keys <- unique(d[, .(muni_code, year)])
    orph <- keys[!univ, on = c("muni_code", "year")]
    if (nrow(orph)) {
      stop("prepare_stan_data: ", nrow(orph), " ", what, " (municipality, ",
           "year) cell(s) are absent from the population universe (code or ",
           "year mismatch), e.g. muni ", orph$muni_code[1L], " year ",
           orph$year[1L], ". Resolve rather than drop.")
    }
    invisible(TRUE)
  }
  check_orphans(notif, "notification")
  check_orphans(dth, "death")

  # Collapse counts to one row per cell (sum duplicates) and validate.
  notif_c <- notif[, .(notifications = sum(notifications)),
                   by = .(muni_code, year)]
  dth_c <- dth[, .(deaths = sum(deaths)), by = .(muni_code, year)]
  if (!.is_count(notif_c$notifications)) {
    stop("prepare_stan_data: notifications must be non-negative integers.")
  }
  if (!.is_count(dth_c$deaths)) {
    stop("prepare_stan_data: deaths must be non-negative integers.")
  }

  # --- Left-join counts onto the universe; explicit zero-fill --------------
  dt <- notif_c[pop, on = c("muni_code", "year")]
  dt <- dth_c[dt, on = c("muni_code", "year")]
  data.table::setorder(dt, muni_code, year)

  n_notif_filled <- sum(is.na(dt$notifications))
  n_death_filled <- sum(is.na(dt$deaths))
  if (!fill_missing_counts && (n_notif_filled || n_death_filled)) {
    stop("prepare_stan_data: ", n_notif_filled, " notification and ",
         n_death_filled, " death cell(s) have no record while ",
         "fill_missing_counts = FALSE.")
  }
  dt[is.na(notifications), notifications := 0L]
  dt[is.na(deaths), deaths := 0L]
  data.table::set(dt, j = "notifications",
                  value = as.integer(dt$notifications))
  data.table::set(dt, j = "deaths", value = as.integer(dt$deaths))

  # --- Integer area/year indices ------------------------------------------
  areas <- sort(unique(dt$muni_code))
  years <- sort(unique(dt$year))
  dt[, area_idx := match(muni_code, areas)]
  dt[, year_idx := match(year, years)]

  # --- Optional covariates -------------------------------------------------
  X <- NULL
  if (!is.null(covariates)) {
    cov <- data.table::copy(covariates)
    .require_cols(cov, "muni_code", "covariates")
    data.table::set(cov, j = "muni_code",
                    value = normalise_muni6(cov$muni_code))
    by_year <- "year" %in% names(cov)
    join_cols <- if (by_year) c("muni_code", "year") else "muni_code"
    if (by_year) data.table::set(cov, j = "year", value = as.integer(cov$year))
    cov_cols <- setdiff(names(cov), c("muni_code", "year"))
    if (!length(cov_cols)) stop("covariates has no covariate columns.")
    merged <- cov[dt[, c("muni_code", "year", "area_idx", "year_idx"),
                     with = FALSE], on = join_cols]
    gaps <- merged[!stats::complete.cases(merged[, cov_cols, with = FALSE])]
    if (nrow(gaps)) {
      stop("prepare_stan_data: covariates miss ", nrow(gaps), " universe ",
           "cell(s), e.g. muni ", gaps$muni_code[1L], ". Fill before fitting.")
    }
    data.table::setorder(merged, muni_code, year)
    X <- as.matrix(merged[, cov_cols, with = FALSE])
  }

  report <- list(
    n_areas = length(areas),
    n_years = length(years),
    n_cells = nrow(dt),
    notifications_zero_filled = as.integer(n_notif_filled),
    deaths_zero_filled = as.integer(n_death_filled),
    year_range = range(years)
  )

  list(
    N = nrow(dt),
    n_areas = length(areas),
    n_years = length(years),
    area = dt$area_idx,
    year = dt$year_idx,
    notifications = dt$notifications,
    deaths = dt$deaths,
    population = dt$population,
    log_pop_offset = log(dt$population),
    X = X,
    key = dt[, .(area_idx, year_idx, muni_code, year, population,
                 notifications, deaths)],
    report = report
  )
}
