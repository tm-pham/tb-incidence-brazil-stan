# basis.R
# Design matrices for the monthly latent time series (log-incidence and
# logit-detection), shared by the R simulator and the Stan model so the two
# cannot drift: Stan receives these matrices as data. Side-effect free.
#
# The latent series live on an EXTENDED axis = a pre-window of `n_pre` months
# (unobserved, needed so the delay convolutions are complete for the observed
# months) followed by `n_obs` observed months. Observed month 1 is extended
# index n_pre + 1.
#
# Per CLAUDE.md: a smooth trend (penalised B-spline on coarse knots) + a seasonal
# harmonic component + an explicit COVID level/slope shock. No monthly AR-1.

#' Penalised B-spline trend basis over the extended monthly axis.
#'
#' Cubic B-spline with interior knots at evenly spaced quantiles of the time
#' index, no intercept column (the model carries its own intercept). A smoothing
#' prior (RW penalty / shrinkage) on the coefficients goes in the model.
#'
#' @param n_total Total months (pre-window + observed).
#' @param n_knots Number of interior knots (trend flexibility).
#' @param degree Spline degree (3 = cubic).
#' @return Numeric matrix `n_total x (n_knots + degree)`.
#'
#' The columns are MEAN-CENTERED and then ORTHONORMALISED (QR). Centering removes
#' the level direction (the intercept carries the level, the spline only
#' deviations); orthonormalising decorrelates the spline columns. Together they
#' fix the geometry that wrecked HMC on real data (R-hat ~1.2, ESS ~17, and 100%
#' of transitions hitting max treedepth -- a strongly correlated posterior). With
#' an orthonormal basis the trend coefficients get independent iid-normal priors
#' in the Stan model (the coarse knots provide the smoothness; this replaces the
#' RW penalty, a deliberate trade for identifiability/convergence). Because the
#' centred columns are all orthogonal to the constant, the QR columns are too, so
#' the basis stays mean-zero.
trend_basis <- function(n_total, n_knots = 8L, degree = 3L) {
  tt <- seq_len(n_total)
  probs <- seq(0, 1, length.out = n_knots + 2L)[-c(1L, n_knots + 2L)]
  knots <- as.numeric(stats::quantile(tt, probs = probs))
  B <- splines::bs(tt, knots = knots, degree = degree, intercept = FALSE)
  B <- matrix(as.numeric(B), nrow = n_total)
  B <- sweep(B, 2L, colMeans(B))               # center: remove the level direction
  qr.Q(qr(B))                                  # orthonormalise: decorrelate columns
}

#' Seasonal harmonic basis (Fourier) for a cyclic monthly effect.
#'
#' @param month_of_year Integer vector in 1..12.
#' @param n_harmonics Number of sin/cos harmonic pairs.
#' @return Numeric matrix `length(month_of_year) x (2 * n_harmonics)`.
#'   Columns are mean-centered (as for the trend) so seasonality does not carry
#'   any of the level.
seasonal_basis <- function(month_of_year, n_harmonics = 2L) {
  cols <- lapply(seq_len(n_harmonics), function(k) {
    ang <- 2 * pi * k * month_of_year / 12
    cbind(sin(ang), cos(ang))
  })
  S <- do.call(cbind, cols)
  sweep(S, 2L, colMeans(S))
}

#' Assemble the full extended-axis design for one state.
#'
#' @param n_obs Observed months (252 for 2003-2023).
#' @param n_pre Pre-window length (>= total delay-kernel support so the
#'   convolutions are complete for observed months).
#' @param start_month_of_year Calendar month (1..12) of observed month 1.
#' @param covid_break Observed-month index of the COVID break (e.g. April 2020),
#'   or NULL for no shock.
#' @param n_trend_knots,n_harmonics Basis sizes.
#' @return A list of the time index, month-of-year, trend/seasonal bases, and the
#'   COVID level/slope columns, all on the extended axis.
build_design <- function(n_obs, n_pre, start_month_of_year = 1L,
                         covid_break = NULL, n_trend_knots = 8L,
                         n_harmonics = 2L) {
  n_total <- n_pre + n_obs
  obs_index <- seq_len(n_total) - n_pre               # <=0 pre-window, 1..n_obs
  moy <- ((obs_index - 1L + (start_month_of_year - 1L)) %% 12L) + 1L
  B_trend <- trend_basis(n_total, n_trend_knots)
  covid_level <- if (is.null(covid_break)) rep(0, n_total) else
    as.numeric(obs_index >= covid_break)
  covid_slope <- if (is.null(covid_break)) rep(0, n_total) else
    pmax(obs_index - covid_break + 1L, 0)
  # Decorrelate the COVID columns from the intercept + smooth trend (and the slope
  # from the level) so their coefficients do not ride the late spline coefficients.
  # That trend<->COVID posterior correlation is what saturated max treedepth on the
  # 252-month real data (a dense mass matrix confirmed correlation -- not a
  # variance funnel -- as the cause, but is too costly to adapt). B_trend is
  # orthonormal and mean-zero, so subtracting the mean and the B_trend projection
  # orthogonalises a column against span{1, B_trend}. This leaves the incidence /
  # detection SERIES unchanged (same column space) but removes the correlated
  # direction, so the cheap diagonal metric mixes cleanly. The COVID coefficients
  # become the trend-orthogonal shock (a cleaner, better-identified estimand).
  if (!is.null(covid_break)) {
    resid_trend <- function(v) {
      v <- v - mean(v)
      v - as.numeric(B_trend %*% crossprod(B_trend, v))
    }
    covid_level <- resid_trend(covid_level)
    covid_slope <- resid_trend(covid_slope)
    d <- sum(covid_level^2)
    if (d > 0) covid_slope <- covid_slope - (sum(covid_slope * covid_level) / d) * covid_level
  }
  list(
    n_total = n_total, n_pre = n_pre, n_obs = n_obs, obs_index = obs_index,
    month_of_year = moy,
    B_trend = B_trend,
    S_season = seasonal_basis(moy, n_harmonics),
    covid_level = covid_level, covid_slope = covid_slope
  )
}
