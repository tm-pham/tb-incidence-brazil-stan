# simulate.R
# Generative simulator for the MONTHLY, state-level TB natural-history process
# (Chitwood 2025 + project extensions). This is the data-generating process the
# Stan model (code/03_modeling/stan/tb_state_month.stan) must match exactly; it
# is the backbone of the recovery test and of data/synthetic/.
#
# Process (discrete monthly, per state), on an extended axis with a pre-window:
#   lambda_t  = exp( inc_intercept + B_trend beta + S_season s + COVID )    [infections, per-capita]
#   gamma_t   = conv(lambda, phi_lambda)                                    [symptomatic = "incidence"]
#   delta_t   = invlogit( det_intercept + B_trend b + S_season s + COVID + genexpert )
#   detect_t  = conv(gamma, phi_gamma)
#   Notified  = delta * detect ;  Missed = (1-delta) * detect
#   DeadNotif = Notified * (pri_mort_t + pri_aban_t * p_mort_aban)
#   AllDeaths = conv(DeadNotif, phi_mort) + conv(Missed * p_mort_nonotif, phi_mort)
#   DeathAdj_t= invlogit( theta0 + theta_time*year + theta_idc*idc_t )       [time-varying, our extension]
#   SINAN_t ~ Poisson( pop_t * Notified_t )
#   SIM_t   ~ Poisson( pop_t * AllDeaths_t * DeathAdj_t )
#
# Side-effect free: no file I/O; RNG seeds scoped with withr::with_seed.

source(here::here("code", "01_functions", "delays.R"))
source(here::here("code", "01_functions", "basis.R"))
source(here::here("code", "03_modeling", "priors.R"))

#' Simulate one state's monthly notification and death counts.
#'
#' @param design Output of `build_design()` (extended axis + bases).
#' @param kernels Output of `build_delay_kernels()`.
#' @param params Named list of TRUE parameter values (see `default_true_params`).
#' @param covariates Named list of length-`n_obs` vectors: population, idc,
#'   genexpert, pri_mort_t, pri_aban_t.
#' @param seed Optional integer; if given, Poisson draws are reproducible.
#' @return data.table with month, notifications, deaths, the offset, and the true
#'   latent series (lambda, gamma, delta, death_adj) for recovery checks.
simulate_state_month <- function(design, kernels, params, covariates,
                                 seed = NULL) {
  n_total <- design$n_total; n_pre <- design$n_pre; n_obs <- design$n_obs
  obs_rows <- (n_pre + 1L):n_total
  stopifnot(length(covariates$population) == n_obs)

  pre <- function(v, fill) c(rep(fill, n_pre), v)   # extend a covariate backward
  gx_ext    <- pre(covariates$genexpert, 0)         # no Xpert in the pre-window
  pmort_ext <- pre(covariates$pri_mort_t, covariates$pri_mort_t[1L])
  paban_ext <- pre(covariates$pri_aban_t, covariates$pri_aban_t[1L])

  # Latent per-capita infection rate on the extended axis, then symptomatic.
  loglam <- params$inc_intercept +
    as.numeric(design$B_trend %*% params$beta_trend_inc) +
    as.numeric(design$S_season %*% params$beta_season_inc) +
    params$covid_inc_level * design$covid_level +
    params$covid_inc_slope * design$covid_slope
  lambda <- exp(loglam)
  gamma  <- causal_convolve(lambda, kernels$phi_lambda)

  # Detection probability.
  logit_delta <- params$det_intercept +
    as.numeric(design$B_trend %*% params$beta_trend_det) +
    as.numeric(design$S_season %*% params$beta_season_det) +
    params$covid_det_level * design$covid_level +
    params$covid_det_slope * design$covid_slope +
    params$genexpert_coef * gx_ext
  delta <- stats::plogis(logit_delta)

  detectable <- causal_convolve(gamma, kernels$phi_gamma)
  notified <- delta * detectable
  missed   <- (1 - delta) * detectable

  dead_notif <- notified * (pmort_ext + paban_ext * params$p_mort_aban)
  alldeaths  <- causal_convolve(dead_notif, kernels$phi_mort) +
    causal_convolve(missed * params$p_mort_nonotif, kernels$phi_mort)

  # Time-varying death-reporting adjustment (observed months; time in years).
  year_idx  <- (seq_len(n_obs) - 1) / 12
  death_adj <- stats::plogis(params$theta0 + params$theta_time * year_idx +
                               params$theta_idc * covariates$idc)

  exp_notif  <- covariates$population * notified[obs_rows]
  exp_deaths <- covariates$population * alldeaths[obs_rows] * death_adj
  if (any(!is.finite(exp_notif)) || any(!is.finite(exp_deaths)) ||
      any(exp_notif < 0) || any(exp_deaths < 0)) {
    stop("simulate_state_month: non-finite/negative expected counts; check params.")
  }

  draw <- function() list(n = stats::rpois(n_obs, exp_notif),
                          d = stats::rpois(n_obs, exp_deaths))
  out <- if (is.null(seed)) draw() else withr::with_seed(seed, draw())

  data.table::data.table(
    month = seq_len(n_obs),
    notifications = as.integer(out$n),
    deaths = as.integer(out$d),
    population = covariates$population,
    idc = covariates$idc, genexpert = covariates$genexpert,
    pri_mort_t = covariates$pri_mort_t, pri_aban_t = covariates$pri_aban_t,
    true_lambda = lambda[obs_rows], true_gamma = gamma[obs_rows],
    true_delta = delta[obs_rows], true_death_adj = death_adj,
    exp_notif = exp_notif, exp_deaths = exp_deaths
  )
}

#' Plausible TRUE parameters that produce realistic monthly counts.
#'
#' The incidence intercept is set on the per-capita log scale (~ -9.6 gives a
#' few hundred monthly symptomatic cases per 1e6 people); spline/seasonal
#' coefficients are small, seeded perturbations. NOT drawn from the wide fitting
#' priors (those let the data speak; here we need realistic synthetic truth).
#'
#' @param design Output of `build_design()`.
#' @param seed Integer seed.
#' @return A named list consumable by `simulate_state_month()`.
default_true_params <- function(design, seed = 1L) {
  K <- ncol(design$B_trend); H2 <- ncol(design$S_season)
  withr::with_seed(seed, list(
    inc_intercept   = -9.6,
    beta_trend_inc  = cumsum(stats::rnorm(K, 0, 0.12)),
    beta_season_inc = stats::rnorm(H2, 0, 0.05),
    covid_inc_level = -0.15, covid_inc_slope = 0.002,
    det_intercept   = 0.3,
    beta_trend_det  = cumsum(stats::rnorm(K, 0, 0.08)),
    beta_season_det = stats::rnorm(H2, 0, 0.03),
    covid_det_level = -0.20, covid_det_slope = 0.003,
    genexpert_coef  = 0.5,
    theta0 = 1.0, theta_time = 0.02, theta_idc = -1.5,
    p_mort_aban = 0.05, p_mort_nonotif = 0.565
  ))
}

#' Synthetic state-month covariates with realistic shapes (IDC falling,
#' GeneXpert ~0 pre-2014 then rising), for synthetic data and recovery tests.
#'
#' @param n_obs Observed months.
#' @param population Constant state population (person-time offset).
#' @return Named list of length-`n_obs` covariate vectors.
synthetic_covariates <- function(n_obs, population = 1e6) {
  yr <- (seq_len(n_obs) - 1) / 12
  list(
    population  = rep(population, n_obs),
    idc         = 0.16 * exp(-0.12 * yr) + 0.04,        # 0.20 -> ~0.04
    genexpert   = stats::plogis((yr - 11) * 0.8) * 0.6, # ~0 before ~2014, rising
    pri_mort_t  = rep(0.04, n_obs),
    pri_aban_t  = rep(0.10, n_obs)
  )
}

#' Default pre-window length: the total delay-kernel support, so the
#' convolutions are complete for every observed month.
default_n_pre <- function(pr = priors()) {
  d <- pr$delays
  as.integer(d$lambda_max + d$gamma_max + d$mort_max)
}

#' Simulate a multi-state synthetic dataset (for synthetic data + recovery).
#'
#' @param n_states Number of states.
#' @param n_obs Observed months per state.
#' @param start_month_of_year Calendar month of observed month 1.
#' @param covid_break Observed-month index of the COVID break.
#' @param n_trend_knots,n_harmonics Basis sizes (must match the Stan model).
#' @param seed Master seed.
#' @return list(panel = data.table(uf, month, ...), design, kernels,
#'   params_by_state, priors).
simulate_tb_dataset <- function(n_states = 3L, n_obs = 252L,
                                start_month_of_year = 1L, covid_break = 208L,
                                n_trend_knots = 6L, n_harmonics = 2L,
                                seed = 20240603L) {
  pr <- priors()
  kernels <- build_delay_kernels(pr$delays)
  n_pre <- default_n_pre(pr)
  design <- build_design(n_obs, n_pre, start_month_of_year, covid_break,
                         n_trend_knots, n_harmonics)
  params_by_state <- vector("list", n_states)
  rows <- vector("list", n_states)
  for (s in seq_len(n_states)) {
    params <- default_true_params(design, seed = seed + s)
    params$inc_intercept <- params$inc_intercept +
      withr::with_seed(seed + 200L + s, stats::runif(1L, -0.3, 0.3))
    cov <- synthetic_covariates(n_obs, population = 1e6 + s * 2e5)
    d <- simulate_state_month(design, kernels, params, cov, seed = seed + 100L + s)
    d[, uf := s]
    params_by_state[[s]] <- params
    rows[[s]] <- d
  }
  list(panel = data.table::rbindlist(rows), design = design, kernels = kernels,
       params_by_state = params_by_state, priors = pr)
}
