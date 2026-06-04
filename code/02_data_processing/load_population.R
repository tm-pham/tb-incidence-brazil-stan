# load_population.R
# IBGE STATE population: the person-time denominator (the gamma offset), expanded
# to state-month over 2003-2023. Annual intercensal estimates span the 2000,
# 2010, and 2022 censuses (note the 2022 revision). The pure transforms
# (tidy_state_population, expand_population_monthly) are tested;
# load_ibge_state_population() is the thin sidrar fetch wrapper.

#' Standardise a raw IBGE state-population frame to (uf, year, population).
#'
#' Pure: no I/O. Coerces types, errors loudly on a missing or non-positive
#' population or a duplicated (uf, year) cell (a missing state-year denominator
#' would silently drop a state-month from the universe downstream).
#'
#' @param raw data.frame/data.table of annual state population estimates.
#' @param uf_col,year_col,value_col Column names for the 2-digit UF code, year,
#'   and population.
#' @return data.table(uf, year, population).
tidy_state_population <- function(raw,
                                  uf_col = "uf",
                                  year_col = "year",
                                  value_col = "population") {
  dt <- data.table::as.data.table(raw)
  miss <- setdiff(c(uf_col, year_col, value_col), names(dt))
  if (length(miss)) {
    stop("tidy_state_population: missing column(s): ",
         paste(miss, collapse = ", "), ".")
  }
  out <- data.table::data.table(
    uf         = suppressWarnings(as.integer(dt[[uf_col]])),
    year       = suppressWarnings(as.integer(dt[[year_col]])),
    population = suppressWarnings(as.numeric(dt[[value_col]]))
  )
  if (anyNA(out$uf) || anyNA(out$year)) {
    stop("tidy_state_population: non-integer uf or year after coercion.")
  }
  if (anyNA(out$population) || any(out$population <= 0)) {
    stop("tidy_state_population: population must be present and strictly ",
         "positive (every state-year needs a denominator).")
  }
  dup <- out[, .N, by = .(uf, year)][N > 1L]
  if (nrow(dup)) {
    stop("tidy_state_population: duplicated (uf, year) cell(s); estimates must ",
         "be unique per state-year.")
  }
  data.table::setorder(out, uf, year)
  out[]
}

#' Expand annual state population to state-month person-time.
#'
#' Pure: no I/O. Produces a population value for every (uf, year, month) in the
#' requested window. Annual IBGE estimates are mid-year (1 July); the default
#' `method = "linear"` linearly interpolates them onto a monthly axis (month
#' mid-points), holding constant beyond the observed years. `method = "constant"`
#' repeats each year's estimate across its 12 months.
#'
#' @param annual data.table(uf, year, population) from tidy_state_population().
#' @param year_start,year_end Inclusive target year range.
#' @param method "linear" or "constant".
#' @return data.table(uf, year, month, population) over the full grid.
expand_population_monthly <- function(annual, year_start, year_end,
                                      method = c("linear", "constant")) {
  method <- match.arg(method)
  annual <- data.table::as.data.table(annual)
  ufs <- sort(unique(annual$uf))
  grid <- data.table::CJ(uf = ufs, year = seq.int(year_start, year_end),
                         month = 1:12)
  # Continuous time at each month mid-point and at each annual (mid-year) anchor.
  grid[, t := year + (month - 0.5) / 12]

  out <- grid[, {
    a <- annual[uf == .BY$uf]
    if (method == "constant") {
      pop <- a$population[match(year, a$year)]
    } else {
      pop <- stats::approx(x = a$year + 0.5, y = a$population, xout = t,
                           rule = 2)$y
    }
    list(year = year, month = month, population = pop)
  }, by = uf]

  if (anyNA(out$population)) {
    stop("expand_population_monthly: ", sum(is.na(out$population)),
         " (uf, year, month) cell(s) have no population; the annual series does ",
         "not cover the requested window for every state.")
  }
  data.table::setorder(out, uf, year, month)
  out[, .(uf, year, month, population)]
}

# --- IBGE/sidrar fetch wrapper (side-effecting; runs on the Mac/cluster) -----

#' Fetch annual state population estimates from IBGE (SIDRA) and standardise.
#'
#' Side-effecting (network + sidrar). Not unit tested; the testable logic lives
#' in tidy_state_population() / expand_population_monthly(). Confirm the SIDRA
#' table and column names against the installed sidrar version: SIDRA 6579
#' ("Populacao residente estimada") aggregated to UF, with census years
#' substituted from the census tables if exact alignment is wanted (2000/2010/
#' 2022; note the 2022 revision).
#'
#' @param years Integer vector of years.
#' @return data.table(uf, year, population) via tidy_state_population().
load_ibge_state_population <- function(years) {
  if (!requireNamespace("sidrar", quietly = TRUE)) {
    stop("load_ibge_state_population: package 'sidrar' is required (run on a ",
         "machine with IBGE access).")
  }
  raw <- sidrar::get_sidra(
    x = 6579, variable = 9324, period = as.character(years), geo = "State"
  )
  raw <- data.table::as.data.table(raw)
  # SIDRA returns Portuguese labels; map to the contract. Confirm against the
  # installed sidrar output.
  tidy_state_population(
    raw,
    uf_col    = "Unidade da Federacao (Codigo)",
    year_col  = "Ano",
    value_col = "Valor"
  )
}
