# Recovery test: the Stan model must recover the known incidence and detection
# series from data simulated by the SAME generative process. Gated -- it compiles
# and samples with cmdstanr, so it only runs when a Stan toolchain is present AND
# RUN_RECOVERY_TEST is set (it is slow). On CI without cmdstan it skips cleanly.
#
#   RUN_RECOVERY_TEST=1 Rscript code/07_tests/testthat.R

source(here::here("code", "01_functions", "simulate.R"))
source(here::here("code", "03_modeling", "stan_data.R"))
source(here::here("code", "03_modeling", "fit_models.R"))

test_that("the model recovers known monthly incidence and detection", {
  testthat::skip_if_not(nzchar(Sys.getenv("RUN_RECOVERY_TEST")),
                        "set RUN_RECOVERY_TEST=1 to run the Stan recovery test")
  testthat::skip_if_not_installed("cmdstanr")

  pr <- priors()
  kernels <- build_delay_kernels(pr$delays)
  n_obs <- 156L                                   # 13 years, COVID inside window
  n_pre <- default_n_pre(pr)
  design <- build_design(n_obs, n_pre, start_month_of_year = 1L,
                         covid_break = 124L, n_trend_knots = 8L, n_harmonics = 2L)
  params <- default_true_params(design, seed = 1L)
  cov <- synthetic_covariates(n_obs, population = 2e6)
  truth <- simulate_state_month(design, kernels, params, cov, seed = 99L)

  obs <- list(population = cov$population, sinan = truth$notifications,
              sim = truth$deaths, idc = cov$idc, genexpert = cov$genexpert,
              pri_mort_t = cov$pri_mort_t, pri_aban_t = cov$pri_aban_t)
  stan_data <- build_stan_model_data(obs, design, kernels, pr)

  res <- fit_base_model(stan_data, seed = 20240603L,
                        iter_warmup = 1000L, iter_sampling = 1000L,
                        adapt_delta = 0.95)

  # Convergence over the estimands + all sampled params (fit_base_model's vars
  # now include incidence_rate / detection, so max_rhat covers the time series).
  expect_lt(res$diagnostics$max_rhat, 1.01)
  # Fast-mode ESS floor: 4 chains x 1000 draws = 4000; 400 = 10% efficiency.
  expect_gt(res$diagnostics$min_ess_bulk, 400)
  expect_equal(res$diagnostics$num_divergent, 0)
  # And R-hat directly on the estimand vectors (not just the scalar summary).
  expect_lt(max(res$fit$summary("incidence_rate")$rhat), 1.01)
  expect_lt(max(res$fit$summary("detection")$rhat), 1.01)

  # Recovery of the latent estimands: posterior median vs truth, and coverage.
  sm_inc <- res$fit$summary("incidence_rate", "median",
                            ~quantile(.x, c(0.05, 0.95)))
  sm_det <- res$fit$summary("detection", "median",
                            ~quantile(.x, c(0.05, 0.95)))
  expect_gt(cor(sm_inc$median, truth$true_gamma), 0.9)
  expect_gt(cor(sm_det$median, truth$true_delta), 0.9)
  cover_inc <- mean(truth$true_gamma >= sm_inc$`5%` & truth$true_gamma <= sm_inc$`95%`)
  cover_det <- mean(truth$true_delta >= sm_det$`5%` & truth$true_delta <= sm_det$`95%`)
  expect_gt(cover_inc, 0.80)
  expect_gt(cover_det, 0.80)

  # Recovery of the structural terms (COVID shock + time-varying death
  # adjustment + GeneXpert), whose signs are known from default_true_params:
  # covid_inc_level -0.15, covid_det_level -0.20, theta_time +0.02, theta_idc
  # -1.5, genexpert_coef +0.5. The 90% CI should sit on the correct side of 0.
  th <- res$fit$summary(c("covid_inc_level", "covid_det_level", "theta_time",
                          "theta_idc", "genexpert_coef"))
  q5 <- function(v) th$q5[th$variable == v]; q95 <- function(v) th$q95[th$variable == v]
  expect_lt(q95("covid_inc_level"), 0)
  expect_lt(q95("covid_det_level"), 0)
  expect_gt(q5("theta_time"), 0)
  expect_lt(q95("theta_idc"), 0)
  expect_gt(q5("genexpert_coef"), 0)
  # The COVID-period months are fit, not just the pre-COVID stretch.
  covid_months <- seq.int(124L, n_obs)
  expect_gt(cor(sm_inc$median[covid_months], truth$true_gamma[covid_months]), 0.8)
})
