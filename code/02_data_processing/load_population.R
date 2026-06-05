# load_population.R
# IBGE STATE population: the person-time denominator (the gamma offset), expanded
# to state-month over 2003-2023. Assembled across the censuses: the annual
# intercensal ESTIMATES table plus the 2022 CENSUS anchor (which revised many
# states down from the projections), combined census-over-estimate. The pure
# transforms (tidy_state_population, combine_population_sources,
# expand_population_monthly) are tested; fetch_sidra_state_pop() and
# load_ibge_state_population() are the defensive sidrar fetch wrappers.

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

#' Combine annual state-population anchors from several IBGE sources.
#'
#' Pure: no I/O. Row-binds the supplied source tables (each (uf, year,
#' population)), dropping NULL sources, and for any (uf, year) present in more
#' than one source keeps the value from the higher-priority source (census over
#' estimate). Validates positivity. This is where the 2022 Census takes
#' precedence over any stale estimate for 2022.
#'
#' @param sources Named list of data.tables (or NULLs), keyed by source name.
#' @param priority Source names from highest to lowest precedence.
#' @return data.table(uf, year, population, source), one row per (uf, year).
combine_population_sources <- function(sources, priority = names(sources)) {
  sources <- sources[!vapply(sources, is.null, logical(1))]
  if (!length(sources)) {
    stop("combine_population_sources: no population source returned any data.")
  }
  dt <- data.table::rbindlist(lapply(names(sources), function(nm) {
    s <- data.table::as.data.table(sources[[nm]])
    s[, source := nm][]
  }), use.names = TRUE)
  dt[, prio := match(source, priority)]
  if (anyNA(dt$prio)) {
    stop("combine_population_sources: source(s) missing from `priority`: ",
         paste(setdiff(unique(dt$source), priority), collapse = ", "))
  }
  data.table::setorder(dt, uf, year, prio)
  out <- dt[, .SD[1L], by = .(uf, year)]            # highest-priority per cell
  if (anyNA(out$population) || any(out$population <= 0)) {
    stop("combine_population_sources: non-positive population after combine.")
  }
  data.table::setorder(out, uf, year)
  out[, .(uf, year, population, source)]
}

#' Fetch one SIDRA state-population table and tidy to (uf, year, population).
#'
#' Side-effecting (network + sidrar) and DEFENSIVE: returns NULL (with a message)
#' rather than erroring if the table fails or its columns cannot be located, so a
#' single source outage cannot sink the whole assembly. SIDRA labels are accented
#' and vary, so columns are matched by pattern. Census tables have no year
#' column, so pass `stamp_year` to stamp it.
#'
#' @param table,variable SIDRA table and variable IDs.
#' @param period Years to request (NULL for a single-snapshot census table).
#' @param stamp_year If set, stamp this year instead of reading a year column.
#' @return data.table(uf, year, population) or NULL.
fetch_sidra_state_pop <- function(table, variable, period = NULL,
                                  stamp_year = NULL) {
  args <- list(x = table, variable = variable, geo = "State")
  if (!is.null(period)) args$period <- as.character(period)
  raw <- tryCatch(do.call(sidrar::get_sidra, args),
                  error = function(e) {
                    message("  sidra table ", table, " fetch failed: ",
                            conditionMessage(e)); NULL })
  if (is.null(raw)) return(NULL)
  raw <- data.table::as.data.table(raw)
  if (!nrow(raw)) return(NULL)
  nms <- names(raw)
  pick <- function(patterns) {
    for (p in patterns) {
      h <- grep(p, nms, value = TRUE, ignore.case = TRUE)
      if (length(h)) return(h[1L])
    }
    NA_character_
  }
  uf_col  <- pick(c("Federa.*[CC].?dig", "Unidade da Federa"))
  val_col <- pick(c("^Valor$", "Valor"))
  yr_col  <- if (is.null(stamp_year)) pick(c("^Ano$", "Ano")) else NA_character_
  if (is.na(uf_col) || is.na(val_col) ||
      (is.null(stamp_year) && is.na(yr_col))) {
    message("  could not locate uf/year/value columns in sidra table ", table,
            "; columns were: ", paste(nms, collapse = " | "))
    return(NULL)
  }
  out <- data.table::data.table(
    uf = suppressWarnings(as.integer(raw[[uf_col]])),
    year = if (is.null(stamp_year)) suppressWarnings(as.integer(raw[[yr_col]]))
           else as.integer(stamp_year),
    population = suppressWarnings(as.numeric(raw[[val_col]]))
  )
  out <- out[!is.na(uf) & uf >= 11L & uf <= 53L &
               !is.na(population) & population > 0]
  if (!nrow(out)) return(NULL)
  out[]
}

#' Assemble annual state population from IBGE (SIDRA), across the censuses.
#'
#' Side-effecting. Pulls the annual intercensal ESTIMATES table for the requested
#' years and the 2022 CENSUS for the 2022 anchor, then combines them
#' (census > estimate). The testable logic is in combine_population_sources() /
#' expand_population_monthly(); fetch_sidra_state_pop() is defensive so a source
#' outage degrades gracefully (the year is interpolated/held downstream rather
#' than crashing the run).
#'
#' Coverage: estimate years come from 6579; 2022 from the census; gap years
#' (2007, 2010) are interpolated and any year past the last anchor (2023) is held
#' by expand_population_monthly(). Years still absent are reported.
#'
#' @param years Integer vector of years.
#' @return data.table(uf, year, population).
load_ibge_state_population <- function(years,
                                       estimate_table = SIDRA_POP_ESTIMATE_TABLE,
                                       estimate_variable = SIDRA_POP_ESTIMATE_VARIABLE,
                                       census2022_table = SIDRA_POP_CENSUS2022_TABLE,
                                       census2022_variable = SIDRA_POP_CENSUS2022_VARIABLE) {
  if (!requireNamespace("sidrar", quietly = TRUE)) {
    stop("load_ibge_state_population: package 'sidrar' is required (run on a ",
         "machine with IBGE access).")
  }
  estimates <- fetch_sidra_state_pop(estimate_table, estimate_variable,
                                     period = years)
  census2022 <- if (2022L %in% years) {
    fetch_sidra_state_pop(census2022_table, census2022_variable,
                          stamp_year = 2022L)
  } else NULL

  combined <- combine_population_sources(
    list(census2022 = census2022, estimates = estimates),
    priority = c("census2022", "estimates"))

  got <- combined[, .N, by = .(year, source)]
  message("load_ibge_state_population: anchors by source -> ",
          paste(sprintf("%d:%s", got$year, got$source), collapse = " "))
  miss <- setdiff(years, unique(combined$year))
  if (length(miss)) {
    message("load_ibge_state_population: no anchor for year(s) ",
            paste(miss, collapse = ", "),
            " (interpolated / held by expand_population_monthly).")
  }
  combined[, .(uf, year, population)]
}
