# extract_estimates.R
# Turn a fitted per-state model into a tidy state x year-month table of the
# estimands (symptomatic incidence rate and case-detection probability) with
# posterior median and 90% credible interval. Side-effect free.

#' Tidy the per-state estimands from a fit.
#'
#' @param res Output of `fit_base_model()` (uses `res$fit`).
#' @param uf State code.
#' @param year,month Integer vectors (length N_obs) giving the calendar of the
#'   observed months, in the same order the Stan data used (month 1 first).
#' @return data.table(uf, year, month, incidence_rate_*, detection_*) with median
#'   and 5%/95% quantiles, plus per-100k incidence for convenience.
tidy_state_estimates <- function(res, uf, year, month) {
  fit <- res$fit
  q <- function(var) {
    s <- fit$summary(var, median = ~stats::median(.x),
                     lo = ~stats::quantile(.x, 0.05),
                     hi = ~stats::quantile(.x, 0.95))
    data.table::as.data.table(s)[, .(median, lo, hi)]
  }
  inc <- q("incidence_rate")
  det <- q("detection")
  n <- length(year)
  if (nrow(inc) != n) {
    stop("tidy_state_estimates: ", nrow(inc), " incidence rows but ", n,
         " months supplied for uf ", uf, ".")
  }
  data.table::data.table(
    uf = uf, year = year, month = month,
    incidence_rate = inc$median, incidence_lo = inc$lo, incidence_hi = inc$hi,
    incidence_per100k = inc$median * 1e5,
    detection = det$median, detection_lo = det$lo, detection_hi = det$hi
  )
}
