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
#' @param prob Central credible-interval mass (default 0.95 -> 2.5%/97.5%).
#' @return data.table(uf, year, month, incidence_rate_*, detection_*) with median
#'   and lo/hi quantiles, plus per-100k incidence for convenience.
tidy_state_estimates <- function(res, uf, year, month, prob = 0.95) {
  fit <- res$fit
  a <- (1 - prob) / 2; b <- 1 - a              # e.g. 0.025 / 0.975 for 95%
  q <- function(var) {
    # explicit functions (closing over a/b) and unname() so the columns are
    # "lo"/"hi" rather than posterior's "lo2.5%"/"hi97.5%".
    s <- fit$summary(var,
                     median = function(x) stats::median(x),
                     lo = function(x) unname(stats::quantile(x, a)),
                     hi = function(x) unname(stats::quantile(x, b)))
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
