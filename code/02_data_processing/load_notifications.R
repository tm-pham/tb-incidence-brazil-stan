# load_notifications.R
# SINAN (notifications) loader: treatment initiations as the route out of
# untreated disease that the model observes. The pure transform
# summarise_notifications() is side-effect free and tested;
# load_sinan_tb_notifications() is the thin DATASUS fetch wrapper that runs
# where the network is.

source(here::here("code", "02_data_processing", "geo_utils.R"))

# The keep-set of SINAN-TB "Tipo de Entrada" (DBF variable TRATAMENTO) codes is
# defined canonically as SINAN_ENTRY_KEEP_CODES in config.R (c("1", "2"): new
# case + relapse). PI decision 2026-06-03, recorded in literature/notes/priors.md.
# Codes confirmed against SINAN_TB_Variable_Dictionary.xlsx (variable
# TRATAMENTO): 1=New case, 2=Relapse, 3=Re-entry after abandonment, 4=Unknown,
# 5=Transfer, 6=Post-mortem (v5). It is passed explicitly to the loader so the
# inclusion rule is never applied implicitly.

#' Reduce a standardised SINAN-TB frame to treatment-initiation counts.
#'
#' Pure: no I/O. (1) Keeps rows whose entry type is in `keep_entry`; (2)
#' attributes each notification to municipality of residence, falling back to
#' municipality of notification when residence is missing; (3) aggregates to
#' non-negative integer counts on the 6-digit key. One input row is one
#' treatment initiation.
#'
#' `keep_entry` has no default on purpose: the caller must state which raw entry
#' values count, so the load-bearing inclusion rule is never applied implicitly.
#'
#' @param sinan data.table with the columns named by the *_col args below.
#' @param keep_entry Vector of raw entry-type values to keep (new + relapse);
#'   canonically `SINAN_ENTRY_KEEP_CODES` from config.R.
#' @param entry_col Entry-type column (e.g. SINAN `TRATAMENTO` after
#'   `process_sinan_tuberculose`).
#' @param res_col,occ_col Residence and notification municipality columns
#'   (e.g. SINAN `ID_MN_RESI`, `ID_MUNICIP`).
#' @param year_col Integer year column (e.g. derived from `DT_DIAG`).
#' @return data.table(muni_code, year, notifications), one row per
#'   municipality-year. The number of rows that took the notification fallback
#'   is attached as the attribute `n_residence_fallback`.
summarise_notifications <- function(sinan,
                                    keep_entry,
                                    entry_col = "entry_type",
                                    res_col = "muni_res",
                                    occ_col = "muni_occ",
                                    year_col = "year") {
  if (!data.table::is.data.table(sinan)) {
    stop("summarise_notifications: sinan must be a data.table.")
  }
  if (missing(keep_entry) || !length(keep_entry)) {
    stop("summarise_notifications: keep_entry must list the entry-type values ",
         "to count (new + relapse); it has no default by design.")
  }
  need <- c(entry_col, res_col, occ_col, year_col)
  miss <- setdiff(need, names(sinan))
  if (length(miss)) {
    stop("summarise_notifications: missing column(s): ",
         paste(miss, collapse = ", "), ".")
  }

  keep <- as.character(sinan[[entry_col]]) %in% as.character(keep_entry)
  d <- sinan[keep]
  if (!nrow(d)) {
    out <- data.table::data.table(muni_code = integer(), year = integer(),
                                  notifications = integer())
    data.table::setattr(out, "n_residence_fallback", 0L)
    return(out)
  }

  coalesced <- coalesce_muni_code(d[[res_col]], d[[occ_col]])
  muni <- normalise_muni6(coalesced)
  year <- as.integer(d[[year_col]])
  out <- data.table::data.table(muni_code = muni, year = year)[
    , .(notifications = .N), by = .(muni_code, year)]
  data.table::set(out, j = "notifications", value = as.integer(out$notifications))
  data.table::setorder(out, muni_code, year)
  data.table::setattr(out, "n_residence_fallback",
                      attr(coalesced, "n_fallback"))
  out[]
}

# --- DATASUS fetch wrapper (side-effecting; runs on the Mac/cluster) --------

#' Fetch SINAN-TB notifications from DATASUS and return treatment-initiation
#' counts by municipality-year.
#'
#' Side-effecting (network + microdatasus). Not exercised by unit tests; the
#' testable logic lives in summarise_notifications(). Confirm the microdatasus
#' API, the entry-type column name, and the codes in `keep_entry` against the
#' installed package and the variable dictionary before the first run.
#'
#' @param year_start,year_end Inclusive diagnosis-year range (from DT_DIAG).
#' @param keep_entry Raw entry-type codes for new case + relapse. Defaults to
#'   `SINAN_ENTRY_KEEP_CODES` (c("1", "2"), confirmed from the dictionary).
#' @param uf Optional vector of state abbreviations to restrict the pull.
load_sinan_tb_notifications <- function(year_start, year_end,
                                        keep_entry = SINAN_ENTRY_KEEP_CODES,
                                        uf = "all") {
  if (!requireNamespace("microdatasus", quietly = TRUE)) {
    stop("load_sinan_tb_notifications: package 'microdatasus' is required ",
         "(run on a machine with DATASUS access).")
  }
  raw <- microdatasus::fetch_datasus(
    year_start = year_start, year_end = year_end, uf = uf,
    information_system = "SINAN-TUBERCULOSE"
  )
  raw <- microdatasus::process_sinan_tuberculose(raw)
  raw <- data.table::as.data.table(raw)
  # Standardise to the columns summarise_notifications() expects. Source names
  # confirmed against the dictionary: TRATAMENTO (Tipo de Entrada), ID_MN_RESI
  # (residence), ID_MUNICIP (notification), DT_DIAG (diagnosis date).
  sinan <- data.table::data.table(
    entry_type = as.character(raw$TRATAMENTO),
    muni_res   = raw$ID_MN_RESI,
    muni_occ   = raw$ID_MUNICIP,
    year       = as.integer(format(as.Date(raw$DT_DIAG), "%Y"))
  )
  summarise_notifications(sinan, keep_entry = keep_entry)
}
