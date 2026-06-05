# prepare_stan_data.R
# Side-effect-free assembly of the state-month panel that feeds the per-state
# Stan models. The model is fit one state at a time, so this builds the full
# 27 x 252 panel (UF x year x month, 2003-2023) and provides stan_data_for_state()
# to slice one state's 252-month series. No reading or writing here.
#
# Contract (enforced loudly, per the data_integrity mandate):
#   * The canonical universe is the COMPLETE grid uf_codes x years x 12 months.
#     Population must cover every cell (it is the person-time offset); a missing
#     denominator is an error, not a silent drop.
#   * Notifications and deaths are LEFT-joined onto the grid; a cell with no
#     record is zero (filled and reported), not missing.
#   * Counts outside the grid (bad UF / year / month) error rather than drop.
#   * Counts are non-negative integers. Covariates (idc, genexpert_share,
#     pri_mort_t, pri_aban_t) are joined; cells where they are undefined (e.g. no
#     notifications) are reported as NA, not silently imputed.

.is_count <- function(x) {
  is.numeric(x) && all(is.finite(x)) && isTRUE(all(x >= 0)) &&
    isTRUE(all(x == suppressWarnings(as.integer(x))))
}

.require_cols <- function(dt, cols, what) {
  miss <- setdiff(cols, names(dt))
  if (length(miss)) {
    stop(what, ": missing required column(s): ", paste(miss, collapse = ", "), ".")
  }
  invisible(TRUE)
}

#' Assemble the state-month panel.
#'
#' @param notifications data.table(uf, year, month, notifications).
#' @param deaths data.table(uf, year, month, deaths).
#' @param population data.table(uf, year, month, population) covering the grid.
#' @param idc Optional data.table(uf, year, month, idc).
#' @param genexpert Optional data.table(uf, year, month, genexpert_share).
#' @param treatment Optional data.table(uf, year, month, pri_mort_t, pri_aban_t).
#' @param year_start,year_end Inclusive year window.
#' @param uf_codes Integer vector of the 27 UF codes (the canonical states).
#' @param covid_break_year,covid_break_month The COVID structural break.
#' @return A list: `panel` (the complete grid with counts, covariates, the
#'   person-time offset, and time/COVID/season columns), `states`, `n_states`,
#'   `n_months`, and a `report`.
prepare_stan_data <- function(notifications, deaths, population,
                              idc = NULL, genexpert = NULL, treatment = NULL,
                              year_start, year_end, uf_codes,
                              covid_break_year, covid_break_month) {
  for (nm in c("notifications", "deaths", "population")) {
    if (!data.table::is.data.table(get(nm))) {
      stop("prepare_stan_data: `", nm, "` must be a data.table.")
    }
  }
  .require_cols(notifications, c("uf", "year", "month", "notifications"), "notifications")
  .require_cols(deaths, c("uf", "year", "month", "deaths"), "deaths")
  .require_cols(population, c("uf", "year", "month", "population"), "population")

  years <- seq.int(year_start, year_end)
  n_months <- length(years) * 12L

  # --- Canonical universe: the complete grid -------------------------------
  grid <- data.table::CJ(uf = sort(uf_codes), year = years, month = 1:12)
  data.table::setkey(grid, uf, year, month)

  # --- Population must cover every cell, be unique and positive ------------
  pop <- data.table::copy(population)
  pop <- pop[year >= year_start & year <= year_end]
  if (anyNA(pop$population) || any(pop$population <= 0)) {
    stop("prepare_stan_data: population must be present and strictly positive.")
  }
  if (nrow(pop[, .N, by = .(uf, year, month)][N > 1L])) {
    stop("prepare_stan_data: population has duplicated (uf, year, month) cells.")
  }
  missing_pop <- pop[grid, on = c("uf", "year", "month")][is.na(population)]
  if (nrow(missing_pop)) {
    stop("prepare_stan_data: ", nrow(missing_pop), " grid cell(s) have no ",
         "population denominator, e.g. uf ", missing_pop$uf[1L], " ",
         missing_pop$year[1L], "-", missing_pop$month[1L], ".")
  }

  # --- Orphan check + count validation -------------------------------------
  check_orphans <- function(d, what) {
    if (!nrow(d)) return(invisible(TRUE))
    keys <- unique(d[, .(uf, year, month)])
    orph <- keys[!grid, on = c("uf", "year", "month")]
    if (nrow(orph)) {
      stop("prepare_stan_data: ", nrow(orph), " ", what, " cell(s) outside the ",
           "grid (bad uf/year/month), e.g. uf ", orph$uf[1L], " ",
           orph$year[1L], "-", orph$month[1L], ".")
    }
  }
  notif_c <- notifications[year >= year_start & year <= year_end][
    , .(notifications = sum(notifications)), by = .(uf, year, month)]
  death_c <- deaths[year >= year_start & year <= year_end][
    , .(deaths = sum(deaths)), by = .(uf, year, month)]
  check_orphans(notif_c, "notification")
  check_orphans(death_c, "death")
  if (!.is_count(notif_c$notifications)) stop("prepare_stan_data: notifications must be non-negative integers.")
  if (!.is_count(death_c$deaths)) stop("prepare_stan_data: deaths must be non-negative integers.")

  # --- Assemble onto the grid ----------------------------------------------
  dt <- notif_c[grid, on = c("uf", "year", "month")]
  dt <- death_c[dt, on = c("uf", "year", "month")]
  dt <- pop[, .(uf, year, month, population)][dt, on = c("uf", "year", "month")]
  data.table::setorder(dt, uf, year, month)
  stopifnot(nrow(dt) == nrow(grid))

  n_notif_filled <- sum(is.na(dt$notifications))
  n_death_filled <- sum(is.na(dt$deaths))
  dt[is.na(notifications), notifications := 0L]
  dt[is.na(deaths), deaths := 0L]
  data.table::set(dt, j = "notifications", value = as.integer(dt$notifications))
  data.table::set(dt, j = "deaths", value = as.integer(dt$deaths))

  # --- Covariates (left-joined; undefined cells stay NA and are reported) --
  # From idc we also carry all-cause deaths (n_deaths) as `allcause_deaths`: the
  # denominator of the IDC fraction and, crucially, the definitive SIM-gap signal
  # (every state-month has all-cause deaths, so zero means a download gap, not a
  # true zero) used by the panel diagnostics.
  if (!is.null(idc)) {
    idc <- data.table::as.data.table(idc)
    icols <- c("uf", "year", "month", "idc")
    if ("n_deaths" %in% names(idc)) icols <- c(icols, "n_deaths")
    j <- idc[, ..icols]
    if ("n_deaths" %in% names(j)) data.table::setnames(j, "n_deaths", "allcause_deaths")
    dt <- merge(dt, j, by = c("uf", "year", "month"), all.x = TRUE, sort = FALSE)
  }
  if (!is.null(genexpert)) dt <- merge(dt, genexpert[, .(uf, year, month, genexpert_share)], by = c("uf","year","month"), all.x = TRUE, sort = FALSE)
  if (!is.null(treatment)) dt <- merge(dt, treatment[, .(uf, year, month, pri_mort_t, pri_aban_t)], by = c("uf","year","month"), all.x = TRUE, sort = FALSE)
  data.table::setorder(dt, uf, year, month)

  # --- Time / COVID / seasonal columns -------------------------------------
  dt[, t := (year - year_start) * 12L + month]                 # 1..n_months
  dt[, month_of_year := month]
  t_break <- (covid_break_year - year_start) * 12L + covid_break_month
  dt[, covid_level := as.integer(t >= t_break)]
  dt[, covid_slope := pmax(t - t_break + 1L, 0L)]
  dt[, log_pop_offset := log(population)]

  report <- list(
    n_states = data.table::uniqueN(dt$uf),
    n_months = n_months,
    n_cells = nrow(dt),
    notifications_zero_filled = as.integer(n_notif_filled),
    deaths_zero_filled = as.integer(n_death_filled),
    idc_missing = if ("idc" %in% names(dt)) sum(is.na(dt$idc)) else NA_integer_,
    genexpert_missing = if ("genexpert_share" %in% names(dt)) sum(is.na(dt$genexpert_share)) else NA_integer_,
    treatment_missing = if ("pri_mort_t" %in% names(dt)) sum(is.na(dt$pri_mort_t)) else NA_integer_,
    year_range = c(year_start, year_end)
  )

  list(
    panel = dt[],
    states = sort(unique(dt$uf)),
    n_states = data.table::uniqueN(dt$uf),
    n_months = n_months,
    report = report
  )
}

#' Slice one state's 252-month series into a per-state Stan data list.
#'
#' The model is fit per state, so each fit consumes one of these. Counts and the
#' offset are always present; covariates may carry NA where undefined (handled in
#' the modelling stage).
#'
#' @param assembled Output of `prepare_stan_data()`.
#' @param uf One UF code.
#' @return A list with `N` (months), `uf`, the time/COVID/season vectors, the
#'   counts, the log person-time offset, and the covariates, ordered by time.
stan_data_for_state <- function(assembled, uf) {
  target_uf <- uf
  d <- data.table::copy(assembled$panel[uf == target_uf])
  data.table::setorder(d, year, month)
  if (!nrow(d)) stop("stan_data_for_state: no rows for uf ", target_uf, ".")
  out <- list(
    uf = target_uf,
    N = nrow(d),
    t = d$t,
    month_of_year = d$month_of_year,
    covid_level = d$covid_level,
    covid_slope = d$covid_slope,
    notifications = d$notifications,
    deaths = d$deaths,
    population = d$population,
    log_pop_offset = d$log_pop_offset
  )
  for (cv in c("idc", "genexpert_share", "pri_mort_t", "pri_aban_t")) {
    if (cv %in% names(d)) out[[cv]] <- d[[cv]]
  }
  out
}
