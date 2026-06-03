# load_sim.R
# SIM (mortality) loader: TB deaths as the death-before-treatment route in the
# identifying model. The pure transform filter_tb_deaths() is side-effect free
# and tested; load_sim_deaths() is the thin DATASUS fetch wrapper that runs
# where the network is (the Mac/cluster), not in unit tests.

source(here::here("code", "02_data_processing", "geo_utils.R"))

#' Reduce a standardised SIM death frame to TB-death counts by municipality-year.
#'
#' Pure: no I/O. (1) Keeps rows whose UNDERLYING cause (CAUSABAS) is an active-TB
#' ICD-10 code; (2) attributes each death to municipality of residence, falling
#' back to municipality of occurrence when residence is missing; (3) aggregates
#' to non-negative integer counts on the 6-digit key. One input row is one death.
#'
#' SCOPE: only the underlying cause is searched, not the contributory-cause
#' lines (LINHAA-LINHAD, LINHAII). This matches the PI decision (2026-06-03:
#' A15-A19 underlying cause only); TB deaths recorded only as a contributory
#' cause are intentionally not counted. See literature/notes/priors.md.
#'
#' @param sim data.table with the columns named by the *_col args below.
#' @param icd3 Character vector of 3-character ICD-10 prefixes counted as a TB
#'   death. The canonical list is `TB_DEATH_ICD3` in config.R; the literal
#'   default here keeps the pure function self-contained for direct/test use.
#' @param cause_col Underlying-cause column (e.g. SIM `CAUSABAS`).
#' @param res_col,occ_col Residence and occurrence municipality columns
#'   (e.g. SIM `CODMUNRES`, `CODMUNOCOR`).
#' @param year_col Integer year column (e.g. derived from `DTOBITO`).
#' @return data.table(muni_code, year, deaths), one row per municipality-year.
#'   The number of rows that took the occurrence fallback is attached as the
#'   attribute `n_residence_fallback`.
filter_tb_deaths <- function(sim,
                             icd3 = c("A15", "A16", "A17", "A18", "A19"),
                             cause_col = "cause",
                             res_col = "muni_res",
                             occ_col = "muni_occ",
                             year_col = "year") {
  if (!data.table::is.data.table(sim)) stop("filter_tb_deaths: sim must be a data.table.")
  need <- c(cause_col, res_col, occ_col, year_col)
  miss <- setdiff(need, names(sim))
  if (length(miss)) {
    stop("filter_tb_deaths: missing column(s): ", paste(miss, collapse = ", "), ".")
  }

  causes <- toupper(trimws(as.character(sim[[cause_col]])))
  keep <- substr(causes, 1L, 3L) %in% icd3
  d <- sim[keep]
  if (!nrow(d)) {
    out <- data.table::data.table(muni_code = integer(), year = integer(),
                                  deaths = integer())
    data.table::setattr(out, "n_residence_fallback", 0L)
    return(out)
  }

  coalesced <- coalesce_muni_code(d[[res_col]], d[[occ_col]])
  muni <- normalise_muni6(coalesced)
  year <- as.integer(d[[year_col]])
  out <- data.table::data.table(muni_code = muni, year = year)[
    , .(deaths = .N), by = .(muni_code, year)]
  data.table::set(out, j = "deaths", value = as.integer(out$deaths))
  data.table::setorder(out, muni_code, year)
  data.table::setattr(out, "n_residence_fallback",
                      attr(coalesced, "n_fallback"))
  out[]
}

# --- DATASUS fetch wrapper (side-effecting; runs on the Mac/cluster) --------

#' Fetch SIM deaths from DATASUS and return TB-death counts by municipality-year.
#'
#' Side-effecting (network + microdatasus). Not exercised by unit tests; the
#' testable logic lives in filter_tb_deaths(). Confirm the microdatasus API and
#' column names against the installed package version before the first run.
#'
#' @param year_start,year_end Inclusive death-year range (from DTOBITO).
#' @param uf Optional vector of state abbreviations to restrict the pull.
#' @param icd3 ICD-10 prefixes. Defaults to `TB_DEATH_ICD3` from config.R (the
#'   canonical definition), which must be on the search path.
load_sim_deaths <- function(year_start, year_end, uf = "all",
                            icd3 = TB_DEATH_ICD3) {
  if (!requireNamespace("microdatasus", quietly = TRUE)) {
    stop("load_sim_deaths: package 'microdatasus' is required (run on a ",
         "machine with DATASUS access).")
  }
  raw <- microdatasus::fetch_datasus(
    year_start = year_start, year_end = year_end, uf = uf,
    information_system = "SIM-DO"
  )
  raw <- microdatasus::process_sim(raw)
  raw <- data.table::as.data.table(raw)
  # Standardise to the columns filter_tb_deaths() expects.
  sim <- data.table::data.table(
    cause    = raw$CAUSABAS,
    muni_res = raw$CODMUNRES,
    muni_occ = raw$CODMUNOCOR,
    year     = as.integer(format(as.Date(raw$DTOBITO), "%Y"))
  )
  filter_tb_deaths(sim, icd3 = icd3)
}
