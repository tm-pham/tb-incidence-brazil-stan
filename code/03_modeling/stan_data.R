# stan_data.R
# Bridge one state's observed monthly series to the data list consumed by
# tb_state_month.stan. Pure (no I/O). Used for both the real panel
# (stan_data_for_state -> this) and simulated data (recovery test). All prior
# hyperparameters come from priors.R, so the model and simulator share one source.

# These function files are side-effect free, so re-sourcing is safe and is done
# unconditionally -- guards like if(!exists()) would skip reloading updated code
# in an interactive session (a real footgun).
source(here::here("code", "01_functions", "delays.R"))
source(here::here("code", "01_functions", "basis.R"))
source(here::here("code", "03_modeling", "priors.R"))

#' Build the Stan data list for one state.
#'
#' @param obs Named list / data.table with length-N_obs vectors: population,
#'   sinan (notifications), sim (TB deaths), idc, genexpert, pri_mort_t,
#'   pri_aban_t.
#' @param design Output of `build_design()` (must have the same n_obs and basis
#'   sizes the model will use).
#' @param kernels Output of `build_delay_kernels()`.
#' @param pr Prior table from `priors()`.
#' @param inc_intercept_mean Location of the per-capita log-incidence intercept
#'   prior (e.g. -9; keeps the wide N(.,10) prior near realistic rates).
#' @param prior_only If TRUE, the model skips the likelihood (prior predictive).
#' @return A named list ready for cmdstanr `$sample(data = ...)`.
build_stan_model_data <- function(obs, design, kernels, pr = priors(),
                                  inc_intercept_mean = -9,
                                  det_intercept_mean = 0, prior_only = FALSE) {
  N_obs <- length(obs$population)
  N_pre <- design$n_pre
  if (N_obs != design$n_obs) {
    stop("build_stan_model_data: obs length (", N_obs,
         ") != design$n_obs (", design$n_obs, ").")
  }
  for (v in c("sinan", "sim", "idc", "genexpert", "pri_mort_t", "pri_aban_t")) {
    if (length(obs[[v]]) != N_obs) stop("build_stan_model_data: `", v, "` wrong length.")
  }
  pre <- function(v, fill) c(rep(fill, N_pre), v)   # extend a covariate backward
  num <- function(x) unname(as.numeric(x))

  list(
    N_obs = N_obs, N_pre = N_pre,
    K_trend = ncol(design$B_trend), H2 = ncol(design$S_season),
    L_lambda = length(kernels$phi_lambda),
    L_gamma  = length(kernels$phi_gamma),
    L_mort   = length(kernels$phi_mort),
    B_trend = design$B_trend, S_season = design$S_season,
    covid_level = num(design$covid_level), covid_slope = num(design$covid_slope),
    genexpert_ext = num(pre(obs$genexpert, 0)),
    pri_mort_ext  = num(pre(obs$pri_mort_t, obs$pri_mort_t[1L])),
    pri_aban_ext  = num(pre(obs$pri_aban_t, obs$pri_aban_t[1L])),
    idc = num(obs$idc), year_idx = (seq_len(N_obs) - 1) / 12,
    population = num(obs$population),
    sinan = as.integer(obs$sinan), sim = as.integer(obs$sim),
    phi_lambda = num(kernels$phi_lambda), phi_gamma = num(kernels$phi_gamma),
    phi_mort = num(kernels$phi_mort),
    inc_intercept_sd = num(pr$inc_intercept["sd"]),
    inc_coef_sd = num(pr$inc_coef["sd"]),
    det_intercept_sd = num(pr$det_intercept["sd"]),
    det_coef_sd = num(pr$det_coef["sd"]),
    trend_sd_inc = num(pr$trend_sd["sd"]), trend_sd_det = num(pr$trend_sd["sd"]),
    season_sd_inc = num(pr$season_sd["sd"]), season_sd_det = num(pr$season_sd["sd"]),
    genexpert_coef_sd = num(pr$genexpert_coef["sd"]),
    theta0_mean = num(pr$death_adj$theta0["mean"]),
    theta0_sd = num(pr$death_adj$theta0["sd"]),
    theta_time_sd = num(pr$death_adj$theta_time["sd"]),
    theta_idc_sd = num(pr$death_adj$theta_idc["sd"]),
    pmort_nonotif_a = num(pr$p_mort_nonotif["a"]),
    pmort_nonotif_b = num(pr$p_mort_nonotif["b"]),
    pmort_aban_a = num(pr$p_mort_aban["a"]),
    pmort_aban_b = num(pr$p_mort_aban["b"]),
    inc_intercept_mean = inc_intercept_mean,
    det_intercept_mean = det_intercept_mean,
    prior_only = as.integer(prior_only)
  )
}

#' Convenience: build the Stan data for a UF directly from an assembled panel
#' (output of prepare_stan_data) using `stan_data_for_state()`.
#'
#' @param assembled Output of prepare_stan_data().
#' @param uf State code.
#' @param start_month_of_year Calendar month of observed month 1 (Jan = 1 for a
#'   January start such as 2003-01).
#' @param covid_break Observed-month index of the COVID break.
#' @param n_trend_knots,n_harmonics Basis sizes.
#' @param ... Passed to build_stan_model_data (e.g. prior_only).
stan_data_from_panel <- function(assembled, uf, start_month_of_year = 1L,
                                 covid_break = NULL, n_trend_knots = 8L,
                                 n_harmonics = 2L, pr = priors(), ...) {
  source(here::here("code", "02_data_processing", "prepare_stan_data.R"), local = TRUE)
  sd1 <- stan_data_for_state(assembled, uf)
  n_obs <- sd1$N
  if (is.null(covid_break)) {
    # default: first month with covid_level == 1 (or NULL if never)
    cb <- which(sd1$covid_level == 1L)
    covid_break <- if (length(cb)) min(cb) else NULL
  }
  design <- build_design(n_obs, n_pre = as.integer(pr$delays$lambda_max +
                           pr$delays$gamma_max + pr$delays$mort_max),
                         start_month_of_year = start_month_of_year,
                         covid_break = covid_break,
                         n_trend_knots = n_trend_knots, n_harmonics = n_harmonics)
  kernels <- build_delay_kernels(pr$delays)
  obs <- list(population = sd1$population, sinan = sd1$notifications,
              sim = sd1$deaths, idc = sd1$idc, genexpert = sd1$genexpert_share,
              pri_mort_t = sd1$pri_mort_t, pri_aban_t = sd1$pri_aban_t)
  build_stan_model_data(obs, design, kernels, pr = pr, ...)
}
