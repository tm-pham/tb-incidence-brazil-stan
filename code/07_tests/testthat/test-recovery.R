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

  # Convergence.
  expect_lt(res$diagnostics$max_rhat, 1.01)
  expect_gt(res$diagnostics$min_ess_bulk, 400)
  expect_equal(res$diagnostics$num_divergent, 0)

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
})
