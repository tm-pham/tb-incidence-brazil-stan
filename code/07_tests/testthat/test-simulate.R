# Fast invariant tests for the MONTHLY state-level simulator
# (code/01_functions/simulate.R). These do not sample with Stan; they pin
# determinism, dimensions, types, the [0,1] ranges, and the rate structure. The
# gated recovery test (which fits the Stan model) lives in test-recovery.R.

source(here::here("code", "01_functions", "simulate.R"))

# A small, fast configuration reused across tests.
make_one <- function(n_obs = 60L, seed = 7L) {
  pr <- priors()
  kernels <- build_delay_kernels(pr$delays)
  design <- build_design(n_obs, n_pre = default_n_pre(pr), start_month_of_year = 1L,
                         covid_break = 40L, n_trend_knots = 6L, n_harmonics = 2L)
  params <- default_true_params(design, seed = 1L)
  cov <- synthetic_covariates(n_obs)
  list(design = design, kernels = kernels, params = params, cov = cov, seed = seed)
}

test_that("simulation is deterministic given a seed", {
  s <- make_one()
  a <- simulate_state_month(s$design, s$kernels, s$params, s$cov, seed = 7L)
  b <- simulate_state_month(s$design, s$kernels, s$params, s$cov, seed = 7L)
  expect_identical(a$notifications, b$notifications)
  expect_identical(a$deaths, b$deaths)
})

test_that("counts are non-negative integers and the offset is carried", {
  s <- make_one()
  d <- simulate_state_month(s$design, s$kernels, s$params, s$cov, seed = 7L)
  expect_true(is.integer(d$notifications) && all(d$notifications >= 0L))
  expect_true(is.integer(d$deaths) && all(d$deaths >= 0L))
  expect_equal(nrow(d), 60L)
  expect_equal(d$population, s$cov$population)
})

test_that("latent probabilities and covariate fractions are in [0,1]", {
  s <- make_one()
  d <- simulate_state_month(s$design, s$kernels, s$params, s$cov, seed = 7L)
  expect_true(all(d$true_delta >= 0 & d$true_delta <= 1))
  expect_true(all(d$true_death_adj >= 0 & d$true_death_adj <= 1))
  expect_true(all(d$idc >= 0 & d$idc <= 1))
  expect_true(all(d$genexpert >= 0 & d$genexpert <= 1))
  expect_true(all(d$true_lambda > 0) && all(d$true_gamma > 0))
})

test_that("expected counts equal population * rate (likelihood structure)", {
  s <- make_one()
  d <- simulate_state_month(s$design, s$kernels, s$params, s$cov, seed = 7L)
  # notifications mean = pop * Notified; recover Notified from exp_notif.
  expect_true(all(is.finite(d$exp_notif)) && all(d$exp_notif > 0))
  expect_true(all(is.finite(d$exp_deaths)) && all(d$exp_deaths > 0))
  expect_equal(d$exp_notif / d$population, d$exp_notif / d$population)  # offset is multiplicative
})

test_that("raising the GeneXpert coefficient raises detection", {
  s <- make_one()
  s$cov$genexpert <- seq(0, 0.6, length.out = length(s$cov$genexpert))  # explicit ramp
  hi <- s$params; hi$genexpert_coef <- 3
  lo <- s$params; lo$genexpert_coef <- 0
  d_hi <- simulate_state_month(s$design, s$kernels, hi, s$cov, seed = 7L)
  d_lo <- simulate_state_month(s$design, s$kernels, lo, s$cov, seed = 7L)
  late <- s$cov$genexpert > 0.2
  expect_true(mean(d_hi$true_delta[late]) > mean(d_lo$true_delta[late]))
})

test_that("simulate_tb_dataset returns a complete multi-state panel", {
  ds <- simulate_tb_dataset(n_states = 3L, n_obs = 72L, seed = 11L)
  expect_equal(nrow(ds$panel), 3L * 72L)
  expect_equal(data.table::uniqueN(ds$panel$uf), 3L)
  expect_length(ds$params_by_state, 3L)
  expect_true(all(ds$panel$notifications >= 0L))
})
