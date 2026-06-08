# seasonality.R
# Side-effect-free calendar-month seasonality diagnostic on the observed panel.
# It answers the two questions the seasonal model term raises:
#   (1) Is there a real within-year seasonal signal in the OBSERVED series (or is
#       the clean cycle in the estimates just the fixed Fourier block doing the
#       work)?
#   (2) Does that signal CHANGE across the 21-year window -- which is the evidence
#       that would motivate time-varying seasonality over the current fixed block.
# Pure: returns tables only. The runner script does the I/O and the plot.
#
# This is a DATA-side check (no model fit needed). It deliberately does not touch
# the Stan estimates: the point is to see the seasonality the data carry on their
# own, independent of any seasonal structure we imposed.

#' Month-of-year seasonal profile of an observed series, detrended and by era.
#'
#' Within each calendar year the monthly rate (value / population) is divided by
#' that year's mean, giving a seasonal INDEX centred on 1 (1.05 = 5% above the
#' annual average). Dividing per year removes both the level and the long-run
#' trend, so the calendar-month means isolate the within-year shape rather than
#' the 21-year decline. Profiles are then averaged by month within each ERA, so
#' eras can be compared for drift.
#'
#' @param panel data.table with uf, year, month, population and the value column.
#' @param value Column to profile: "notifications" (default) or "deaths".
#' @param uf Optional state code(s); NULL pools all states (counts and population
#'   summed by year-month before forming the rate).
#' @param era_breaks Optional vector of cut years splitting the period into eras,
#'   each break being the LAST year of an era (e.g. c(2009, 2016) ->
#'   2003-2009, 2010-2016, 2017-end). NULL = one era spanning the whole period.
#' @return list(profile, amplitude):
#'   * profile: era, month, index_mean, index_lo, index_hi (5/95% across the
#'     years in that era), n_years.
#'   * amplitude: era, peak_month, trough_month, amplitude (peak-trough on the
#'     index scale, i.e. fraction of the annual mean), seasonal_strength (share
#'     of the within-year, detrended variance explained by the stable
#'     month-of-year pattern, 0..1; high = strong, repeatable seasonality, low =
#'     the monthly differences are mostly noise), and the robust first-harmonic
#'     summary h1_amplitude (peak-trough of the period-12 harmonic) and
#'     h1_peak_month (its phase as a month in (0,12]; stable across eras unless
#'     the seasonal phase genuinely drifts).
seasonal_profile <- function(panel, value = "notifications", uf = NULL,
                             era_breaks = NULL) {
  stopifnot(data.table::is.data.table(panel))
  for (col in c("uf", "year", "month", "population", value)) {
    if (!col %in% names(panel)) stop("seasonal_profile: column '", col, "' not in panel.")
  }
  d <- data.table::data.table(
    uf = panel$uf, year = panel$year, month = panel$month,
    value = panel[[value]], population = panel$population)
  if (!is.null(uf)) { sel_uf <- uf; d <- d[uf %in% sel_uf] }
  if (!nrow(d)) stop("seasonal_profile: no rows after filtering on uf.")

  # Pool across states (if more than one) by summing counts and population per
  # year-month, then form the pooled rate.
  d <- d[, .(value = sum(value), population = sum(population)), by = .(year, month)]
  d[, rate := value / population]

  # Detrend: divide by the per-year mean rate -> a seasonal index centred on 1.
  # Years whose mean rate is 0 or non-finite carry no seasonal information.
  d[, year_mean := mean(rate), by = year]
  d <- d[is.finite(year_mean) & year_mean > 0]
  if (!nrow(d)) stop("seasonal_profile: every year has a zero mean rate; no signal to profile.")
  d[, index := rate / year_mean]

  # Assign era.
  if (is.null(era_breaks)) {
    d[, era := sprintf("%d-%d", min(year), max(year))]
  } else {
    eb <- sort(unique(as.integer(era_breaks)))
    labs <- sprintf("%d-%d", c(min(d$year), eb + 1L), c(eb, max(d$year)))
    d[, era := as.character(cut(year, breaks = c(-Inf, eb, Inf),
                                labels = labs, right = TRUE))]
  }

  # Stable month-of-year mean within each era (used for the profile and strength).
  d[, month_mean := mean(index), by = .(era, month)]
  prof <- d[, .(index_mean = mean(index),
                index_lo = stats::quantile(index, 0.05, names = FALSE),
                index_hi = stats::quantile(index, 0.95, names = FALSE),
                n_years = data.table::uniqueN(year)),
            by = .(era, month)]
  data.table::setorder(prof, era, month)

  amp <- prof[, .(peak_month = month[which.max(index_mean)],
                  trough_month = month[which.min(index_mean)],
                  amplitude = max(index_mean) - min(index_mean)),
              by = era]
  strength <- d[, {
    vi <- stats::var(index)
    .(seasonal_strength = if (is.finite(vi) && vi > 0)
        1 - stats::var(index - month_mean) / vi else 0)
  }, by = era]
  amp <- strength[amp, on = "era"]

  # Robust phase/amplitude: fit the index on a 2-harmonic basis within each era
  # and read off the FIRST harmonic (period 12). Its amplitude is 2*sqrt(a^2+b^2)
  # and its peak month is the phase angle in months -- far more stable across eras
  # than the argmax peak_month, which jumps between near-ties when the profile is
  # noisy. Compare h1_peak_month across eras to judge whether the phase truly
  # moves (drift) or the argmax was just chasing noise.
  harm <- d[, {
    c1 <- cos(2 * pi * month / 12); s1 <- sin(2 * pi * month / 12)
    c2 <- cos(4 * pi * month / 12); s2 <- sin(4 * pi * month / 12)
    co <- stats::coef(stats::lm(index ~ c1 + s1 + c2 + s2))
    pk <- (atan2(co[["s1"]], co[["c1"]]) * 6 / pi) %% 12   # phase -> month, in (0,12]
    .(h1_amplitude = 2 * sqrt(co[["c1"]]^2 + co[["s1"]]^2),
      h1_peak_month = if (pk <= 0) pk + 12 else pk)
  }, by = era]
  amp <- harm[amp, on = "era"]
  data.table::setcolorder(amp, c("era", "peak_month", "trough_month", "amplitude",
                                 "seasonal_strength", "h1_amplitude", "h1_peak_month"))

  list(profile = prof[], amplitude = amp[])
}
