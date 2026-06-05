# delays.R
# Fixed-delay convolution kernels for the monthly TB natural-history model
# (Chitwood 2025, supplement Table S2). Each continuous delay distribution is
# discretised to a per-month pmf over lags 0, 1, ..., max_months, truncated at the
# stated maximum and renormalised to sum to 1. Side-effect free; the parameters
# live in priors.R / config and are passed in.
#
# 2025 kernels (rate-parameterised gammas; shape/scale Weibull):
#   infection  -> symptom    phi_lambda = Weibull(shape 1.75, scale 25), max 60 mo
#   symptom    -> detectable phi_gamma  = Gamma(shape 10,  rate 4),      max 7  mo
#   detectable -> death      phi_mort   = Gamma(shape 12,  rate 3),      max 10 mo

#' Discretise a delay CDF to a per-month pmf over lags 0..max_months.
#'
#' The mass on lag i is `cdf(i+1) - cdf(i)` (the increment over month i),
#' truncated at `max_months` and renormalised to sum to 1.
#'
#' @param cdf A vectorised CDF function on [0, Inf).
#' @param max_months Maximum lag (inclusive) to retain.
#' @return Numeric pmf of length `max_months + 1` summing to 1 (index 1 = lag 0).
discretise_delay <- function(cdf, max_months) {
  if (max_months < 0) stop("discretise_delay: max_months must be >= 0.")
  edges <- 0:(max_months + 1L)
  p <- diff(cdf(edges))
  if (sum(p) <= 0) stop("discretise_delay: degenerate kernel (zero mass).")
  p / sum(p)
}

#' Weibull (shape/scale) delay kernel.
weibull_delay <- function(shape, scale, max_months) {
  discretise_delay(function(x) stats::pweibull(x, shape = shape, scale = scale),
                   max_months)
}

#' Gamma (shape/rate) delay kernel.
gamma_delay <- function(shape, rate, max_months) {
  discretise_delay(function(x) stats::pgamma(x, shape = shape, rate = rate),
                   max_months)
}

#' Build the three 2025 TB delay kernels from a parameter list.
#'
#' @param p A list like `priors()$delays`.
#' @return list(phi_lambda, phi_gamma, phi_mort), each a pmf summing to 1.
build_delay_kernels <- function(p) {
  list(
    phi_lambda = weibull_delay(p$lambda_shape, p$lambda_scale, p$lambda_max),
    phi_gamma  = gamma_delay(p$gamma_shape, p$gamma_rate, p$gamma_max),
    phi_mort   = gamma_delay(p$mort_shape, p$mort_rate, p$mort_max)
  )
}

#' Causal convolution of a series with a delay kernel.
#'
#' `y[t] = sum_{i=0}^{K-1} x[t-i] * kernel[i+1]` over the available past (lags
#' that fall before the start of `x` contribute nothing). Feed `x` with a
#' pre-window long enough that the output months of interest are complete.
#'
#' @param x Numeric series (index 1 = first month, including any pre-window).
#' @param kernel pmf from a *_delay() function (index 1 = lag 0).
#' @return Numeric series the same length as `x`.
causal_convolve <- function(x, kernel) {
  M <- length(x); K <- length(kernel)
  y <- numeric(M)
  for (t in seq_len(M)) {
    k <- min(K, t)
    y[t] <- sum(x[t - (0:(k - 1L))] * kernel[1:k])
  }
  y
}
