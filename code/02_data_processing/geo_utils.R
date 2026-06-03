# geo_utils.R
# Shared, side-effect-free helpers for reconciling municipality codes across
# SINAN, SIM, and IBGE. Sourced by the loaders and by prepare_stan_data().

#' Normalise an IBGE municipality code to a common 6-digit join key.
#'
#' SINAN typically stores the 6-digit municipality code (the 7-digit IBGE code
#' without its check digit); IBGE and geobr use the full 7-digit code. We reduce
#' every code to its first 6 digits, the lossless intersection of the two
#' conventions. Errors on NA, empty, or wrong-length input so a silent bad join
#' is impossible.
#'
#' @param x A vector of municipality codes (integer or character).
#' @return An integer vector of 6-digit codes.
normalise_muni6 <- function(x) {
  s <- trimws(as.character(x))
  if (any(is.na(s) | s == "")) {
    stop("normalise_muni6: municipality codes contain NA or empty values.")
  }
  nch <- nchar(s)
  if (any(!nch %in% c(6L, 7L))) {
    bad <- unique(s[!nch %in% c(6L, 7L)])
    stop("normalise_muni6: codes must be 6 or 7 digits; got e.g. ",
         paste(utils::head(bad, 5L), collapse = ", "), ".")
  }
  as.integer(substr(s, 1L, 6L))
}

#' Coalesce a residence code with an occurrence fallback.
#'
#' Attribute a case or death to municipality of residence, falling back to the
#' municipality of notification/occurrence when residence is missing or invalid
#' (e.g. Sao Paulo records with a blank residence code in some years). A value
#' is "valid" when it is non-NA and has 6 or 7 digits after trimming; anything
#' else (blank, NA, sentinel like "999999") triggers the fallback.
#'
#' @param residence,occurrence Equal-length vectors of municipality codes.
#' @return A character vector of the chosen codes (not yet normalised). Errors
#'   if any row has neither a valid residence nor a valid occurrence code. The
#'   number of rows that fell back to occurrence is attached as the attribute
#'   `n_fallback` (and `n_total`) so callers can surface the fallback rate:
#'   occurrence is biased toward referral centres, so a high fallback rate
#'   signals numerator/denominator (residence) misalignment.
coalesce_muni_code <- function(residence, occurrence) {
  if (length(residence) != length(occurrence)) {
    stop("coalesce_muni_code: residence and occurrence must be equal length.")
  }
  valid <- function(v) {
    s <- trimws(as.character(v))
    ok <- !is.na(s) & nchar(s) %in% c(6L, 7L) & !grepl("^9+$", s)
    list(s = s, ok = ok)
  }
  r <- valid(residence)
  o <- valid(occurrence)
  out <- ifelse(r$ok, r$s, o$s)
  if (any(!(r$ok | o$ok))) {
    n <- sum(!(r$ok | o$ok))
    stop("coalesce_muni_code: ", n, " row(s) have neither a valid residence ",
         "nor a valid occurrence municipality code.")
  }
  used_fallback <- !r$ok & o$ok
  attr(out, "n_fallback") <- sum(used_fallback)
  attr(out, "n_total") <- length(out)
  out
}
