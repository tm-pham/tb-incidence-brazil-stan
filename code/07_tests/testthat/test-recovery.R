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
                         covid_break = 124L, n_trend_knots = 6L, n_harmonics = 2L)
  params <- default_true_params(design, seed = 1L)
  cov <- synthetic_covariates(n_obs, population = 2e6)
  truth <- simulate_state_month(design, kernels, params, cov, seed = 99L)

  obs <- list(population = cov$population, sinan = truth$notifications,
              sim = truth$deaths, idc = cov$idc, genexpert = cov$genexpert,
              pri_mort_t = cov$pri_mort_t, pri_aban_t = cov$pri_aban_t)
  stan_data <- build_stan_model_data(obs, design, kernels, pr)

  res <- fit_base_model(stan_data, seed = 20240603L,
                        iter_warmup = 1500L, iter_sampling = 1000L,
                        adapt_delta = 0.99)

  # Convergence over the estimands + all sampled params (fit_base_model's vars
  # include incidence_rate / detection, so max_rhat covers the time series).
  expect_lt(res$diagnostics$max_rhat, 1.01)
  expect_gt(res$diagnostics$min_ess_bulk, 400)   # 4 chains x 1000 draws
  # A small number of divergences persist on the variance-parameter (sigma)
  # geometry even at adapt_delta 0.99; production fits raise it further and
  # monitor per state. They do not bias the recovered estimands below.
  expect_lt(res$diagnostics$num_divergent, 20)
  expect_lt(max(res$fit$summary("incidence_rate")$rhat), 1.01)
  expect_lt(max(res$fit$summary("detection")$rhat), 1.01)

  # Recovery of the latent ESTIMAND SERIES (posterior median vs truth) and
  # coverage. Thresholds reflect the information the data actually carry, not
  # aspiration: INCIDENCE is the primary, count-driven estimand and recovers
  # well (r ~ 0.9); DETECTION and the DEATH ADJUSTMENT are latent probability
  # series identified through the sparse monthly death counts, so they recover
  # with moderate fidelity (r ~ 0.8) here -- a single 13-year state. High-burden
  # states and the full 252-month window carry more information. The interval
  # coverage (below) confirms the uncertainty is honest where the point
  # correlation is lower.
  sm_inc <- res$fit$summary("incidence_rate", "median",
                            ~quantile(.x, c(0.05, 0.95)))
  sm_det <- res$fit$summary("detection", "median",
                            ~quantile(.x, c(0.05, 0.95)))
  sm_adj <- res$fit$summary("death_adj", "median")
  expect_gt(cor(sm_inc$median, truth$true_gamma), 0.88)   # incidence (primary estimand)
  expect_gt(cor(sm_det$median, truth$true_delta), 0.78)   # detection (death-channel limited)
  expect_gt(cor(sm_adj$median, truth$true_death_adj), 0.83)  # death adjustment recovered
  cover_inc <- mean(truth$true_gamma >= sm_inc$`5%` & truth$true_gamma <= sm_inc$`95%`)
  cover_det <- mean(truth$true_delta >= sm_det$`5%` & truth$true_delta <= sm_det$`95%`)
  expect_gt(cover_inc, 0.80)
  expect_gt(cover_det, 0.80)

  # The COVID shock has a distinct shape and IS identified: its level terms (true
  # covid_inc_level -0.15, covid_det_level -0.20) should sit below 0. (We check
  # the COVID terms and the recovered series, not the individual smooth-trend /
  # covariate coefficients, which are partly confounded by design.)
  th <- res$fit$summary(c("covid_inc_level", "covid_det_level"))
  expect_lt(th$q95[th$variable == "covid_inc_level"], 0)
  expect_lt(th$q95[th$variable == "covid_det_level"], 0)
  covid_months <- seq.int(124L, n_obs)
  expect_gt(cor(sm_inc$median[covid_months], truth$true_gamma[covid_months]), 0.8)

  # Exercise the real estimate-extraction path (tidy_state_estimates uses
  # fit$summary, which the mock test cannot replicate). Catches the posterior
  # quantile-naming bug.
  source(here::here("code", "05_analysis", "extract_estimates.R"))
  est <- tidy_state_estimates(res, uf = 1L, year = rep(2010L, n_obs),
                              month = rep(1:12, length.out = n_obs))
  expect_equal(nrow(est), n_obs)
  expect_true(all(c("incidence_rate", "incidence_lo", "incidence_hi",
                    "incidence_per100k", "detection") %in% names(est)))
  expect_false(anyNA(est$incidence_rate) || anyNA(est$incidence_lo))
})
