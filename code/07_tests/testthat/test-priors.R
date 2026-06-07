# Pin the load-bearing priors/constants against the documented Chitwood 2025
# values (literature/notes/priors.md), so a silent edit fails loudly.

source(here::here("code", "03_modeling", "priors.R"))

test_that("delay-kernel parameters match Chitwood 2025 Table S2", {
  d <- priors()$delays
  expect_equal(c(d$lambda_shape, d$lambda_scale), c(1.75, 25)) # Weibull infection->symptom
  expect_equal(c(d$gamma_shape, d$gamma_rate), c(10, 4))       # Gamma symptom->detectable
  expect_equal(c(d$mort_shape, d$mort_rate), c(12, 3))         # Gamma detectable->death
  expect_equal(c(d$lambda_max, d$gamma_max, d$mort_max), c(60L, 7L, 10L))
})

test_that("case-fatality and death-adjustment priors match the supplement", {
  p <- priors()
  expect_equal(unname(p$p_mort_nonotif), c(113, 87))   # death|undiagnosed ~0.565
  expect_equal(unname(p$p_mort_aban), c(10, 190))      # death|LTFU ~0.05
  expect_equal(beta_mean(p$p_mort_nonotif), 0.565, tolerance = 1e-3)
  expect_equal(beta_mean(p$p_mort_aban), 0.05, tolerance = 1e-3)
  # Time-varying death adjustment (COMPLETENESS convention: death_adj multiplies
  # deaths). The idc slope is informative and NEGATIVE (Chitwood 2021 anchors,
  # converted from the missed-fraction convention); theta0 is re-centred so
  # completeness ~ 0.75 (the 2025 Beta(150,50) baseline) at a TYPICAL idc ~ 0.12,
  # NOT at idc=0. See priors.R and agent_reviews/2026-06-07.
  expect_equal(unname(p$death_adj$theta0), c(2.0, 0.20))
  expect_equal(unname(p$death_adj$theta_time), c(0, 0.05))
  expect_equal(unname(p$death_adj$static_2025), c(150, 50))
  # Completeness at a typical idc ~ 0.12 returns to the 2025 static baseline ~0.75.
  idc_typical <- 0.12
  baseline <- plogis(p$death_adj$theta0[["mean"]] + p$death_adj$theta_idc[["mean"]] * idc_typical)
  expect_equal(unname(baseline), beta_mean(p$death_adj$static_2025), tolerance = 5e-3)
})

test_that("regression priors match (incidence wide, detection tight)", {
  p <- priors()
  expect_equal(unname(p$inc_intercept), c(0, 10))
  expect_equal(unname(p$det_intercept), c(0, 1))
  # The incidence/detection asymmetry is a deliberate identifiability choice.
  expect_equal(unname(p$inc_coef), c(0, 10))
  expect_equal(unname(p$det_coef), c(0, 1))
})

test_that("death-adjustment drift and GeneXpert coefficient priors are pinned", {
  p <- priors()
  # theta_idc is LOAD-BEARING: informative & negative (it identifies detection vs
  # death-reporting; a flat/symmetric prior leaves them confounded). Anchored to
  # the Chitwood 2021 two-point rho anchors mapped to the completeness convention.
  expect_equal(unname(p$death_adj$theta_idc), c(-7.6, 2.0))
  expect_true(p$death_adj$theta_idc[["mean"]] < 0)        # sign is load-bearing
  # Detection spline tightened so it cannot absorb death-reporting drift; the
  # incidence spline stays wide.
  expect_equal(unname(p$trend_sd_det), c(0, 0.15))
  expect_lt(p$trend_sd_det[["sd"]], p$trend_sd[["sd"]])
  # GeneXpert coef hyperparameter stays (0,1); the >0 sign constraint is in Stan.
  expect_equal(unname(p$genexpert_coef), c(0, 1))
})
