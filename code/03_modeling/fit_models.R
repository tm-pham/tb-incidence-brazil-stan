# fit_models.R
# Compile and sample tb_state_month.stan with cmdstanr, one state at a time.
# Side-effecting (compiles, samples, touches the cmdstan toolchain), so it lives
# here, not in the function libraries. Seeds explicitly and records the cmdstan
# version for reproducibility (reproducibility review H2).

#' Compile the monthly state model (cached by cmdstanr).
#' @param stan_file Path to the .stan file.
#' @return A CmdStanModel.
compile_tb_model <- function(
    stan_file = here::here("code", "03_modeling", "stan", "tb_state_month.stan")) {
  if (!requireNamespace("cmdstanr", quietly = TRUE)) {
    stop("compile_tb_model: cmdstanr is required (install cmdstan and set the ",
         "toolchain). The model is authored to compile under cmdstan >= 2.30.")
  }
  cmdstanr::cmdstan_model(stan_file)
}

#' Reasonable inits to help the 252-month series converge.
#'
#' The per-capita log-incidence intercept must start near its realistic value
#' (~ -9), not at 0 (which would make exp(loglam) overflow -- the chief
#' convergence threat, see code/03_modeling/README.md). Scales start small. The
#' init draws are seeded so initialisation is reproducible (the `seed` argument to
#' $sample() controls only Stan's HMC RNG, not these R-side draws).
#' (Draws use the R RNG; fit_base_model() scopes it with withr::local_seed so the
#' per-chain inits are reproducible yet distinct across chains.)
init_tb_model <- function(stan_data, inc_intercept = -9) {
  function() list(
    inc_intercept = inc_intercept + stats::rnorm(1, 0, 0.2),
    sigma_trend_inc = abs(stats::rnorm(1, 0.1, 0.02)),
    sigma_season_inc = abs(stats::rnorm(1, 0.05, 0.01)),
    sigma_trend_det = abs(stats::rnorm(1, 0.1, 0.02)),
    sigma_season_det = abs(stats::rnorm(1, 0.05, 0.01)),
    det_intercept = stats::rnorm(1, 0, 0.2),
    p_mort_aban = 0.05, p_mort_nonotif = 0.565,
    theta0 = 1.0
  )
}

#' Fit the monthly model for one state.
#'
#' @param stan_data Output of build_stan_model_data() / stan_data_from_panel().
#' @param seed Integer MCMC seed (REQUIRED for reproducibility; defaults to the
#'   global seed if config is sourced).
#' @param model Optional pre-compiled CmdStanModel (compiled once, reused across
#'   states).
#' @param chains,parallel_chains,iter_warmup,iter_sampling,adapt_delta,
#'   max_treedepth Sampler controls. Defaults follow Chitwood 2025 (4 chains,
#'   4000 warmup, 1000 sampling) with a higher adapt_delta given the long series.
#' @return list(fit, cmdstan_version, seed, diagnostics) where diagnostics holds
#'   max R-hat, min bulk/tail ESS, and the number of divergences.
fit_base_model <- function(stan_data, seed,
                           model = NULL,
                           chains = 4L, parallel_chains = chains,
                           iter_warmup = 4000L, iter_sampling = 1000L,
                           adapt_delta = 0.99, max_treedepth = 12L,
                           metric = "diag_e",
                           inc_intercept_init = -9, refresh = 0L) {
  if (missing(seed) || is.null(seed)) {
    stop("fit_base_model: an explicit integer `seed` is required.")
  }
  # Scope the R-side RNG so the per-chain init draws are reproducible (the `seed`
  # below controls only Stan's HMC RNG).
  withr::local_seed(seed)
  if (is.null(model)) model <- compile_tb_model()
  # metric: "diag_e" (default) or "dense_e". The 252-month posterior is strongly
  # correlated (trend coefficients <-> COVID slope, re-correlated by the
  # convolution likelihood), which a diagonal mass matrix navigates with very long
  # trajectories (treedepth saturation). A dense metric adapts the full ~40x40
  # covariance, moving along the correlated directions directly; usually collapses
  # treedepth and lifts ESS. Costs a bit more warmup; needs >=~1000 warmup draws.
  fit <- model$sample(
    data = stan_data, seed = seed,
    chains = chains, parallel_chains = parallel_chains,
    iter_warmup = iter_warmup, iter_sampling = iter_sampling,
    adapt_delta = adapt_delta, max_treedepth = max_treedepth, metric = metric,
    init = init_tb_model(stan_data, inc_intercept_init), refresh = refresh
  )
  # Convergence summary over the ESTIMANDS (incidence_rate, detection) and all
  # sampled scalars/coefficients -- NOT only a handful of scalars, so the check
  # can catch non-convergence in the time-series parameters (testing review C1).
  vars <- c("incidence_rate", "detection",
            "inc_intercept", "det_intercept", "genexpert_coef",
            "beta_trend_inc", "beta_trend_det", "beta_season_inc",
            "beta_season_det", "covid_inc_level", "covid_inc_slope",
            "covid_det_level", "covid_det_slope",
            "sigma_trend_inc", "sigma_trend_det",
            "theta0", "theta_time", "theta_idc",
            "p_mort_aban", "p_mort_nonotif")
  s <- fit$summary(variables = vars)
  ds <- fit$diagnostic_summary()
  diagnostics <- list(
    max_rhat = max(s$rhat, na.rm = TRUE),
    min_ess_bulk = min(s$ess_bulk, na.rm = TRUE),
    min_ess_tail = min(s$ess_tail, na.rm = TRUE),
    num_divergent = sum(ds$num_divergent),
    num_max_treedepth = sum(ds$num_max_treedepth)
  )
  list(fit = fit, cmdstan_version = cmdstanr::cmdstan_version(),
       seed = seed, diagnostics = diagnostics)
}
