# load_notifications.R
# SINAN (notifications) loader for the state-month model. SINAN-TB is NOT served
# by microdatasus, so records come from the PI's local export. One read serves
# the notification counts, the treatment-outcome fractions (mortality likelihood),
# and the GeneXpert share-among-notified (detection covariate). The pure
# transforms are side-effect free and tested; load_sinan_records() reads files.

source(here::here("code", "02_data_processing", "geo_utils.R"))

# --- Date parsing (raw SINAN dates are YYYYMMDD; also handle ISO and Date) ---

#' Calendar year from a SINAN date (leading four characters, or `Date`).
sinan_year <- function(x) {
  if (inherits(x, "Date")) return(as.integer(format(x, "%Y")))
  s <- trimws(as.character(x))
  suppressWarnings(as.integer(substr(s, 1L, 4L)))
}

#' Calendar month (1-12) from a SINAN date. YYYYMMDD -> chars 5-6; ISO
#' YYYY-MM-DD -> chars 6-7; also handles `Date`.
sinan_month <- function(x) {
  if (inherits(x, "Date")) return(as.integer(format(x, "%m")))
  s <- trimws(as.character(x))
  iso <- grepl("-", s)
  suppressWarnings(as.integer(ifelse(iso, substr(s, 6L, 7L), substr(s, 5L, 6L))))
}

# --- Standardise raw SINAN-TB (pure) ----------------------------------------

#' Standardise a raw SINAN-TB frame to notification records keyed by state and
#' month, carrying the fields needed for the derived covariates.
#'
#' Pure: no I/O. Attributes each notification to the municipality of residence
#' (notification fallback) rolled up to the state (UF); parses year and month
#' from `DT_DIAG`. Carries the entry type (`TRATAMENTO`), closure status
#' (`SITUA_ENCE`), and rapid molecular test (`TEST_MOLEC`); the latter two are
#' optional (NA where the column is absent, e.g. TEST_MOLEC pre-GeneXpert).
#' Records placeable in no municipality are dropped and counted.
#'
#' @param sinan data.table with the columns named by the *_col args.
#' @return data.table(entry_type, uf, year, month, situa_ence, test_molec).
standardise_sinan_tb <- function(sinan,
                                 entry_col = "TRATAMENTO",
                                 res_col = "ID_MN_RESI",
                                 occ_col = "ID_MUNICIP",
                                 date_col = "DT_DIAG",
                                 closure_col = "SITUA_ENCE",
                                 molec_col = "TEST_MOLEC") {
  sinan <- data.table::as.data.table(sinan)
  miss <- setdiff(c(entry_col, res_col, occ_col, date_col), names(sinan))
  if (length(miss)) {
    stop("standardise_sinan_tb: missing column(s): ",
         paste(miss, collapse = ", "),
         ". Confirm the export matches the SINAN-TB variable dictionary.")
  }
  col_or_na <- function(nm) if (nm %in% names(sinan)) {
    as.character(sinan[[nm]]) } else NA_character_

  coalesced <- coalesce_muni_code(sinan[[res_col]], sinan[[occ_col]])
  ok <- !is.na(coalesced)
  out <- data.table::data.table(
    entry_type = as.character(sinan[[entry_col]])[ok],
    uf         = uf_from_muni(coalesced[ok]),
    year       = sinan_year(sinan[[date_col]])[ok],
    month      = sinan_month(sinan[[date_col]])[ok],
    situa_ence = col_or_na(closure_col)[ok],
    test_molec = col_or_na(molec_col)[ok]
  )
  data.table::setattr(out, "n_residence_fallback", attr(coalesced, "n_fallback"))
  data.table::setattr(out, "n_unattributable", attr(coalesced, "n_unattributable"))
  out[]
}

# --- State-month aggregates (pure) ------------------------------------------

#' Treatment-initiation counts by state-month (new + relapse).
#'
#' @param records Output of `standardise_sinan_tb()`.
#' @param keep_entry Entry-type codes to count (canonically
#'   `SINAN_ENTRY_KEEP_CODES` = c("1","2")); no default, so the load-bearing
#'   inclusion rule is never implicit.
#' @return data.table(uf, year, month, notifications), non-negative integers.
summarise_notifications <- function(records, keep_entry) {
  if (!data.table::is.data.table(records)) stop("summarise_notifications: records must be a data.table.")
  if (missing(keep_entry) || !length(keep_entry)) {
    stop("summarise_notifications: keep_entry must list the entry-type values ",
         "to count (new + relapse); it has no default by design.")
  }
  d <- records[as.character(entry_type) %in% as.character(keep_entry)]
  out <- d[, .(notifications = .N), by = .(uf, year, month)]
  data.table::set(out, j = "notifications", value = as.integer(out$notifications))
  data.table::setorder(out, uf, year, month)
  out[]
}

#' Treatment-outcome fractions by state-month, over the kept (new + relapse)
#' notifications with a known closure status (`SITUA_ENCE`).
#'
#' Provisional code sets (confirm with the 2025 supplement / PI): death = TB
#' death (3) + other death (4); abandonment = abandonment (2) + primary
#' abandonment (10). Cohort is dated by notification month (`DT_DIAG`); the
#' supplement may instead key on closure date.
#'
#' @return data.table(uf, year, month, n_closed, pri_mort_t, pri_aban_t).
treatment_outcomes <- function(records, keep_entry,
                               death_codes = c("3", "4"),
                               aban_codes = c("2", "10")) {
  if (missing(keep_entry) || !length(keep_entry)) {
    stop("treatment_outcomes: keep_entry must be supplied.")
  }
  d <- records[as.character(entry_type) %in% as.character(keep_entry) &
                 !is.na(situa_ence) & situa_ence != ""]
  out <- d[, .(
    n_closed = .N,
    pri_mort_t = sum(situa_ence %in% death_codes) / .N,
    pri_aban_t = sum(situa_ence %in% aban_codes) / .N
  ), by = .(uf, year, month)]
  data.table::setorder(out, uf, year, month)
  out[]
}

#' GeneXpert share-among-notified by state-month: the share of kept (new +
#' relapse) notifications for which the rapid molecular test was performed
#' (`TEST_MOLEC` in `performed`). A capacity proxy (denominator is the notified
#' set); interpret cautiously. Months with no TEST_MOLEC values (pre-GeneXpert)
#' yield a share of 0.
#'
#' @return data.table(uf, year, month, n_notif, n_genexpert, genexpert_share).
genexpert_share <- function(records, keep_entry,
                            performed = c("1", "2", "3", "4")) {
  if (missing(keep_entry) || !length(keep_entry)) {
    stop("genexpert_share: keep_entry must be supplied.")
  }
  d <- records[as.character(entry_type) %in% as.character(keep_entry)]
  out <- d[, .(
    n_notif = .N,
    n_genexpert = sum(!is.na(test_molec) & test_molec %in% performed)
  ), by = .(uf, year, month)]
  out[, genexpert_share := n_genexpert / n_notif]
  data.table::setorder(out, uf, year, month)
  out[]
}

# --- Local-file loader (side-effecting) -------------------------------------

#' Read a single SINAN-TB export file by extension (.rds/.csv/.csv.gz/.dbf/.dbc).
read_sinan_file <- function(file) {
  ext <- tolower(tools::file_ext(file))
  raw <- switch(
    ext,
    rds = readRDS(file),
    csv = data.table::fread(file),
    gz  = data.table::fread(file),
    dbf = {
      if (!requireNamespace("foreign", quietly = TRUE)) {
        stop("read_sinan_file: reading .dbf needs the 'foreign' package.")
      }
      foreign::read.dbf(file, as.is = TRUE)
    },
    dbc = {
      if (!requireNamespace("read.dbc", quietly = TRUE)) {
        stop("read_sinan_file: reading .dbc needs the 'read.dbc' package ",
             "(install.packages('read.dbc')).")
      }
      read.dbc::read.dbc(file)
    },
    stop("read_sinan_file: unsupported file type '", ext, "': ", file)
  )
  data.table::as.data.table(raw)
}

#' Read local SINAN-TB export file(s) and standardise to notification records.
#'
#' Side-effecting (reads files). The testable logic lives in
#' `standardise_sinan_tb()` and the aggregators.
#'
#' @param files A directory (all matching files read and row-bound, e.g. one per
#'   year) or a character vector of file paths.
#' @param pattern File-name pattern used when `files` is a directory.
#' @return data.table of standardised notification records.
load_sinan_records <- function(files,
                               pattern = "[.](rds|csv|csv\\.gz|dbf|dbc)$") {
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = pattern, full.names = TRUE,
                        ignore.case = TRUE)
  }
  if (!length(files)) {
    stop("load_sinan_records: no SINAN-TB export file(s) found. ",
         "Place the notification export in data/raw/TB_notifications/.")
  }
  raw <- data.table::rbindlist(lapply(files, read_sinan_file),
                               use.names = TRUE, fill = TRUE)
  standardise_sinan_tb(raw)
}
