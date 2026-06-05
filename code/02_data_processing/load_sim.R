# load_sim.R
# SIM (mortality) loader for the state-month model. One all-cause SIM-DO pull
# serves both the TB-death counts and the ill-defined-cause (IDC) fraction that
# drives the time-varying death-reporting adjustment. The pure transforms
# (standardise_sim, filter_tb_deaths, idc_fraction) are side-effect free and
# tested; load_sim_records() is the thin DATASUS fetch wrapper.

source(here::here("code", "02_data_processing", "geo_utils.R"))

# --- Date parsing (raw SIM DTOBITO is ddmmyyyy) -----------------------------

#' Calendar year from a SIM date. Raw `DTOBITO` is ddmmyyyy, so the year is the
#' LAST four characters; also handles `Date`.
sim_year <- function(x) {
  if (inherits(x, "Date")) return(as.integer(format(x, "%Y")))
  s <- trimws(as.character(x))
  suppressWarnings(as.integer(substr(s, nchar(s) - 3L, nchar(s))))
}

#' Calendar month (1-12) from a SIM date. ddmmyyyy -> the two characters before
#' the year (robust to a dropped leading zero on the day); also handles `Date`.
sim_month <- function(x) {
  if (inherits(x, "Date")) return(as.integer(format(x, "%m")))
  s <- trimws(as.character(x))
  suppressWarnings(as.integer(substr(s, nchar(s) - 5L, nchar(s) - 4L)))
}

# --- Standardise raw SIM (pure) ---------------------------------------------

#' Standardise a raw SIM-DO frame to all-cause death records keyed by state and
#' month.
#'
#' Pure: no I/O. Attributes each death to the municipality of residence (with an
#' occurrence fallback) and rolls it up to the state (UF); parses year and month
#' from `DTOBITO`. Records that can be placed in no municipality are dropped and
#' counted (`n_unattributable`). One input row is one (all-cause) death.
#'
#' @param sim data.table with the columns named by the *_col args.
#' @param cause_col,res_col,occ_col,date_col Source columns (SIM `CAUSABAS`,
#'   `CODMUNRES`, `CODMUNOCOR`, `DTOBITO`).
#' @return data.table(cause, uf, year, month), one row per death, with
#'   `n_residence_fallback` and `n_unattributable` attributes.
standardise_sim <- function(sim,
                            cause_col = "cause",
                            res_col = "muni_res",
                            occ_col = "muni_occ",
                            date_col = "date") {
  if (!data.table::is.data.table(sim)) stop("standardise_sim: sim must be a data.table.")
  miss <- setdiff(c(cause_col, res_col, occ_col, date_col), names(sim))
  if (length(miss)) {
    stop("standardise_sim: missing column(s): ", paste(miss, collapse = ", "), ".")
  }
  coalesced <- coalesce_muni_code(sim[[res_col]], sim[[occ_col]])
  ok <- !is.na(coalesced)
  out <- data.table::data.table(
    cause = toupper(trimws(as.character(sim[[cause_col]])))[ok],
    uf    = uf_from_muni(coalesced[ok]),
    year  = sim_year(sim[[date_col]])[ok],
    month = sim_month(sim[[date_col]])[ok]
  )
  data.table::setattr(out, "n_residence_fallback", attr(coalesced, "n_fallback"))
  data.table::setattr(out, "n_unattributable", attr(coalesced, "n_unattributable"))
  out[]
}

# --- State-month aggregates (pure) ------------------------------------------

#' TB-death counts by state-month from standardised all-cause SIM records.
#'
#' Keeps deaths whose underlying cause is an active-TB ICD-10 code (A15-A19 by
#' default; the canonical list is `TB_DEATH_ICD3` in config.R). Underlying cause
#' only, per the documented decision; see literature/notes/priors.md.
#'
#' @param records Output of `standardise_sim()` (cause, uf, year, month).
#' @param icd3 3-character ICD-10 prefixes counted as a TB death.
#' @return data.table(uf, year, month, deaths), non-negative integers.
filter_tb_deaths <- function(records,
                             icd3 = c("A15", "A16", "A17", "A18", "A19")) {
  if (!data.table::is.data.table(records)) stop("filter_tb_deaths: records must be a data.table.")
  d <- records[substr(cause, 1L, 3L) %in% icd3]
  out <- d[, .(deaths = .N), by = .(uf, year, month)]
  data.table::set(out, j = "deaths", value = as.integer(out$deaths))
  data.table::setorder(out, uf, year, month)
  out[]
}

#' Ill-defined-cause-of-death fraction by state-month.
#'
#' The covariate driving the time-varying death-reporting adjustment: the share
#' of ALL-cause deaths coded to ill-defined causes (ICD-10 Chapter XVIII, R00-R99
#' by default). Computed from the same all-cause records as the TB deaths.
#'
#' @param records Output of `standardise_sim()`.
#' @param idc_prefix Leading ICD-10 letter(s) for ill-defined causes.
#' @return data.table(uf, year, month, n_deaths, n_idc, idc), idc in [0,1].
idc_fraction <- function(records, idc_prefix = "R") {
  if (!data.table::is.data.table(records)) stop("idc_fraction: records must be a data.table.")
  pat <- paste0("^(", paste(idc_prefix, collapse = "|"), ")")
  out <- records[, .(
    n_deaths = .N,
    n_idc = sum(grepl(pat, cause))
  ), by = .(uf, year, month)]
  out[, idc := n_idc / n_deaths]
  data.table::setorder(out, uf, year, month)
  out[]
}

# --- DATASUS fetch wrapper (side-effecting; runs on the Mac/cluster) --------

#' Fetch and standardise one (state, year) slice of all-cause SIM-DO deaths.
#'
#' Targeted fetch used to fill gaps left by DATASUS FTP timeouts. Returns NULL if
#' the slice comes back empty.
fetch_sim_slice <- function(year, uf_abbrev) {
  raw <- microdatasus::fetch_datasus(
    year_start = year, year_end = year, uf = uf_abbrev,
    information_system = "SIM-DO"
  )
  raw <- data.table::as.data.table(raw)
  if (!nrow(raw)) return(NULL)
  standardise_sim(data.table::data.table(
    cause = raw$CAUSABAS, muni_res = raw$CODMUNRES,
    muni_occ = raw$CODMUNOCOR, date = raw$DTOBITO
  ))
}

#' Fetch all-cause SIM-DO deaths from DATASUS and standardise to death records.
#'
#' Side-effecting (network + microdatasus). SELF-HEALING: starts from any cached
#' records (`existing`), then fetches ONLY the state-years still missing, one
#' slice at a time, so a single DATASUS FTP timeout costs one targeted re-fetch
#' rather than the whole 20-year pull. Asserts every requested state-year is
#' present, so a truncated download can never silently become "zero deaths"
#' downstream (the failure mode that dropped RN 2010 on the first run).
#'
#' We use the raw SIM-DO columns directly and SKIP microdatasus::process_sim()
#' (it decodes unused fields and fails on some versions). The pure aggregators
#' filter_tb_deaths() and idc_fraction() then run on the result.
#'
#' NB presence detects a fully-dropped state-year (the observed failure); a
#' partially-truncated file that still returns some rows is not caught here.
#'
#' @param year_start,year_end Inclusive death-year range (from DTOBITO).
#' @param uf "all" or a vector of state abbreviations to restrict the pull.
#' @param existing Optional cached data.table from a prior (partial) run.
#' @param uf_codes State codes expected present (the completeness grid).
#' @return data.table of standardised all-cause death records, complete over the
#'   requested state-year grid.
load_sim_records <- function(year_start, year_end, uf = "all", existing = NULL,
                             uf_codes = UF_CODES) {
  if (!requireNamespace("microdatasus", quietly = TRUE)) {
    stop("load_sim_records: package 'microdatasus' is required (run on a ",
         "machine with DATASUS access).")
  }
  # DATASUS FTP is slow; allow long single-file downloads.
  options(timeout = max(as.numeric(getOption("timeout", 60)), 600))

  expected_codes <- if (identical(uf, "all")) uf_codes else {
    cc <- as.integer(names(UF_ABBREV)[match(uf, UF_ABBREV)])
    if (anyNA(cc)) stop("load_sim_records: unknown state abbreviation in `uf`.")
    cc
  }
  want <- data.table::CJ(uf = sort(expected_codes),
                         year = seq.int(year_start, year_end))

  out <- if (!is.null(existing) && nrow(existing)) data.table::copy(existing) else NULL

  # First run with no cache: one bulk fetch (efficient); gaps patched below.
  if (is.null(out)) {
    raw <- microdatasus::fetch_datasus(
      year_start = year_start, year_end = year_end, uf = uf,
      information_system = "SIM-DO"
    )
    raw <- data.table::as.data.table(raw)
    out <- standardise_sim(data.table::data.table(
      cause = raw$CAUSABAS, muni_res = raw$CODMUNRES,
      muni_occ = raw$CODMUNOCOR, date = raw$DTOBITO
    ))
  }

  # Patch any missing state-years, one slice at a time.
  missing <- want[!unique(out[, .(uf, year)]), on = c("uf", "year")]
  for (i in seq_len(nrow(missing))) {
    ab <- UF_ABBREV[[as.character(missing$uf[i])]]
    message("load_sim_records: fetching missing SIM slice ", ab, " ",
            missing$year[i], " ...")
    slice <- tryCatch(fetch_sim_slice(missing$year[i], ab),
                      error = function(e) {
                        message("  fetch failed: ", conditionMessage(e)); NULL
                      })
    if (!is.null(slice) && nrow(slice)) {
      out <- data.table::rbindlist(list(out, slice), use.names = TRUE)
    }
  }

  still <- want[!unique(out[, .(uf, year)]), on = c("uf", "year")]
  if (nrow(still)) {
    stop("load_sim_records: SIM still missing ", nrow(still),
         " state-year(s) after fetch (DATASUS FTP timeouts). First: uf ",
         still$uf[1L], " ", still$year[1L],
         ". Re-run to retry; the cache is preserved.")
  }
  data.table::setorder(out, uf, year, month)
  out[]
}
