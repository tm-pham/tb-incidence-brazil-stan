# load_population.R
# IBGE municipal population: the person-time denominator (gamma offset), not a
# covariate. The pure transform tidy_population() is side-effect free and tested;
# load_ibge_population() is the thin sidrar fetch wrapper that runs where the
# network is.

#' Standardise a raw IBGE population frame to the (muni_code, year, population)
#' contract that prepare_stan_data() consumes.
#'
#' Pure: no I/O. Selects and renames the code/year/value columns, coerces types,
#' drops rows with a missing population, and enforces one strictly-positive value
#' per municipality-year. Municipality codes are left as-is (6- or 7-digit);
#' prepare_stan_data() reconciles them to the 6-digit join key.
#'
#' @param raw A data.frame/data.table of IBGE population estimates.
#' @param code_col,year_col,value_col Column names in `raw` holding the
#'   municipality code, the year, and the population count.
#' @return data.table(muni_code, year, population).
tidy_population <- function(raw,
                            code_col = "muni_code",
                            year_col = "year",
                            value_col = "population") {
  dt <- data.table::as.data.table(raw)
  miss <- setdiff(c(code_col, year_col, value_col), names(dt))
  if (length(miss)) {
    stop("tidy_population: missing column(s): ", paste(miss, collapse = ", "), ".")
  }

  out <- data.table::data.table(
    muni_code  = dt[[code_col]],
    year       = suppressWarnings(as.integer(dt[[year_col]])),
    population = suppressWarnings(as.numeric(dt[[value_col]]))
  )

  if (anyNA(out$year)) {
    stop("tidy_population: ", sum(is.na(out$year)), " row(s) have a ",
         "non-integer year after coercion.")
  }
  # A missing population means a municipality-year would silently drop out of the
  # canonical universe in prepare_stan_data(). That is the primary failure mode
  # this pipeline guards against, so it is a loud error, not a silent drop.
  n_drop <- sum(is.na(out$population))
  if (n_drop > 0L) {
    bad <- out[is.na(population)]
    stop("tidy_population: ", n_drop, " row(s) have NA population; every ",
         "municipality-year needs a denominator. First: code ",
         bad$muni_code[1L], " year ", bad$year[1L], ".")
  }
  data.table::setattr(out, "n_dropped_missing", 0L)

  if (any(out$population <= 0)) {
    bad <- out[population <= 0]
    stop("tidy_population: ", nrow(bad), " row(s) have a non-positive ",
         "population, e.g. code ", bad$muni_code[1L], " year ", bad$year[1L], ".")
  }
  dup <- out[, .N, by = .(muni_code, year)][N > 1L]
  if (nrow(dup)) {
    stop("tidy_population: ", nrow(dup), " duplicated (municipality, year) ",
         "cell(s); IBGE estimates must be unique per municipality-year.")
  }

  data.table::setorder(out, muni_code, year)
  out[]
}

# --- IBGE/sidrar fetch wrapper (side-effecting; runs on the Mac/cluster) ----

#' Fetch municipal population estimates from IBGE (SIDRA) and standardise them.
#'
#' Side-effecting (network + sidrar). Not exercised by unit tests; the testable
#' logic lives in tidy_population(). SIDRA table 6579 ("Populacao residente
#' estimada") gives annual municipal population estimates; census years can be
#' substituted from table 9514 if exact-count alignment is wanted. Confirm the
#' table number and the returned column names against the installed sidrar
#' version before the first run.
#'
#' @param years Integer vector of years to fetch.
#' @return data.table(muni_code, year, population) via tidy_population().
load_ibge_population <- function(years) {
  if (!requireNamespace("sidrar", quietly = TRUE)) {
    stop("load_ibge_population: package 'sidrar' is required (run on a machine ",
         "with IBGE access).")
  }
  if (any(years > 2021L)) {
    warning("load_ibge_population: years after 2021 use IBGE intercensal ",
            "projections anchored to the 2010 census; the 2022 census revised ",
            "many municipal estimates. Consider census table 9514 or revision ",
            "factors before extending past 2021.")
  }
  raw <- sidrar::get_sidra(
    x = 6579,
    variable = 9324,
    period = as.character(years),
    geo = "City"
  )
  raw <- data.table::as.data.table(raw)
  # SIDRA returns Portuguese column names; map to the contract. Confirm against
  # the installed sidrar output (column labels can vary by table/version).
  tidy_population(
    raw,
    code_col  = "Município (Código)",
    year_col  = "Ano",
    value_col = "Valor"
  )
}
