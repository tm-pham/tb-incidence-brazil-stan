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
#' @param entry_col Entry-type column (the standardised `entry_type`, from SINAN
#'   `TRATAMENTO`).
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
    data.table::setattr(out, "n_unattributable", 0L)
    return(out)
  }

  coalesced <- coalesce_muni_code(d[[res_col]], d[[occ_col]])
  year <- as.integer(d[[year_col]])
  # Drop records that can be placed in no municipality (no valid residence or
  # notification code); the count is surfaced for the processing report.
  ok <- !is.na(coalesced)
  muni <- normalise_muni6(coalesced[ok])
  out <- data.table::data.table(muni_code = muni, year = year[ok])[
    , .(notifications = .N), by = .(muni_code, year)]
  data.table::set(out, j = "notifications", value = as.integer(out$notifications))
  data.table::setorder(out, muni_code, year)
  data.table::setattr(out, "n_residence_fallback",
                      attr(coalesced, "n_fallback"))
  data.table::setattr(out, "n_unattributable",
                      attr(coalesced, "n_unattributable"))
  out[]
}

# --- Standardise a raw SINAN-TB export (pure) -------------------------------
# SINAN-TB is NOT available through microdatasus::fetch_datasus() (only a few
# SINAN systems are), so notifications come from the local export downloaded
# into data/raw/TB_notifications/, not from a network pull. These helpers turn
# the raw dictionary columns into the contract summarise_notifications() expects.

#' Extract the calendar year from a SINAN date column.
#'
#' Handles `Date` values and character dates that begin with the four-digit year
#' (raw SINAN `YYYYMMDD`, or ISO `YYYY-MM-DD`).
#'
#' @param x A `Date` or character vector.
#' @return An integer vector of years.
sinan_year <- function(x) {
  if (inherits(x, "Date")) return(as.integer(format(x, "%Y")))
  s <- trimws(as.character(x))
  suppressWarnings(as.integer(substr(s, 1L, 4L)))
}

#' Map raw SINAN-TB dictionary columns to the standardised frame.
#'
#' Pure: no I/O. Column names match `SINAN_TB_Variable_Dictionary.xlsx`:
#' `TRATAMENTO` (Tipo de Entrada), `ID_MN_RESI` (residence), `ID_MUNICIP`
#' (notification), `DT_DIAG` (diagnosis date).
#'
#' @param raw A data.frame/data.table of raw SINAN-TB records.
#' @param entry_col,res_col,occ_col,date_col Source column names.
#' @return data.table(entry_type, muni_res, muni_occ, year).
standardise_sinan_tb <- function(raw,
                                 entry_col = "TRATAMENTO",
                                 res_col = "ID_MN_RESI",
                                 occ_col = "ID_MUNICIP",
                                 date_col = "DT_DIAG") {
  raw <- data.table::as.data.table(raw)
  miss <- setdiff(c(entry_col, res_col, occ_col, date_col), names(raw))
  if (length(miss)) {
    stop("standardise_sinan_tb: missing column(s): ",
         paste(miss, collapse = ", "),
         ". Confirm the export matches the SINAN-TB variable dictionary.")
  }
  data.table::data.table(
    entry_type = as.character(raw[[entry_col]]),
    muni_res   = raw[[res_col]],
    muni_occ   = raw[[occ_col]],
    year       = sinan_year(raw[[date_col]])
  )
}

# --- Local-file loader (side-effecting; runs where the export lives) --------

#' Read a single SINAN-TB export file by extension.
#'
#' Supports `.rds`, `.csv`/`.csv.gz`, `.dbf` (via `foreign`), and `.dbc` (the
#' native DATASUS compressed format, via `read.dbc`). Returns a data.table with
#' the raw dictionary column names preserved.
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

#' Read local SINAN-TB notification file(s) and return treatment-initiation
#' counts by municipality-year.
#'
#' Side-effecting (reads files). The testable logic lives in
#' `standardise_sinan_tb()` and `summarise_notifications()`. SINAN-TB is the only
#' source NOT pulled over the network; supply the PI's export from
#' data/raw/TB_notifications/.
#'
#' @param files A directory (all matching files inside are read and row-bound,
#'   e.g. one per year) or a character vector of file paths.
#' @param keep_entry Raw entry-type codes for new case + relapse. Defaults to
#'   `SINAN_ENTRY_KEEP_CODES` (c("1", "2"), confirmed from the dictionary).
#' @param pattern File-name pattern used when `files` is a directory.
load_sinan_tb_notifications <- function(files,
                                        keep_entry = SINAN_ENTRY_KEEP_CODES,
                                        pattern = "[.](rds|csv|csv\\.gz|dbf|dbc)$") {
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = pattern, full.names = TRUE,
                        ignore.case = TRUE)
  }
  if (!length(files)) {
    stop("load_sinan_tb_notifications: no SINAN-TB export file(s) found. ",
         "Place the notification export in data/raw/TB_notifications/.")
  }
  raw <- data.table::rbindlist(lapply(files, read_sinan_file),
                               use.names = TRUE, fill = TRUE)
  sinan <- standardise_sinan_tb(raw)
  summarise_notifications(sinan, keep_entry = keep_entry)
}
