# Tests for the Stan data bridge (no Stan toolchain needed): shapes, the
# pre-window extension, and that prior hyperparameters come from priors.R.

source(here::here("code", "03_modeling", "stan_data.R"))
source(here::here("code", "01_functions", "simulate.R"))

build_obs <- function(n_obs = 48L) {
  pr <- priors()
  kernels <- build_delay_kernels(pr$delays)
  design <- build_design(n_obs, n_pre = default_n_pre(pr), start_month_of_year = 1L,
                         covid_break = 40L, n_trend_knots = 6L, n_harmonics = 2L)
  d <- simulate_state_month(design, kernels, default_true_params(design),
                            synthetic_covariates(n_obs), seed = 3L)
  obs <- list(population = d$population, sinan = d$notifications, sim = d$deaths,
              idc = d$idc, genexpert = d$genexpert,
              pri_mort_t = d$pri_mort_t, pri_aban_t = d$pri_aban_t)
  list(obs = obs, design = design, kernels = kernels, pr = pr, n_obs = n_obs)
}

test_that("build_stan_model_data has consistent shapes and an extended axis", {
  b <- build_obs()
  sd <- build_stan_model_data(b$obs, b$design, b$kernels, b$pr)
  N_total <- sd$N_pre + sd$N_obs
  expect_equal(sd$N_obs, b$n_obs)
  expect_equal(dim(sd$B_trend), c(N_total, sd$K_trend))
  expect_equal(length(sd$covid_level), N_total)
  expect_equal(length(sd$genexpert_ext), N_total)
  expect_equal(length(sd$pri_mort_ext), N_total)
  expect_equal(length(sd$idc), sd$N_obs)
  expect_length(sd$sinan, sd$N_obs)
  expect_true(is.integer(sd$sinan) && is.integer(sd$sim))
  # pre-window GeneXpert is zero (no Xpert before the series starts)
  expect_true(all(sd$genexpert_ext[seq_len(sd$N_pre)] == 0))
  # delay kernels sum to 1
  expect_equal(sum(sd$phi_lambda), 1)
})

test_that("prior hyperparameters are sourced from priors()", {
  b <- build_obs()
  sd <- build_stan_model_data(b$obs, b$design, b$kernels, b$pr)
  expect_equal(sd$inc_intercept_sd, 10)         # incidence ~ Normal(., 10)
  expect_equal(sd$det_intercept_sd, 1)          # detection ~ Normal(0, 1)
  expect_equal(c(sd$pmort_nonotif_a, sd$pmort_nonotif_b), c(113, 87))
  expect_equal(c(sd$pmort_aban_a, sd$pmort_aban_b), c(10, 190))
  expect_equal(sd$theta_time_sd, 0.05)
  expect_equal(sd$prior_only, 0L)
})

test_that("prior_only flag is passed through", {
  b <- build_obs()
  sd <- build_stan_model_data(b$obs, b$design, b$kernels, b$pr, prior_only = TRUE)
  expect_equal(sd$prior_only, 1L)
})

test_that("a length mismatch errors", {
  b <- build_obs()
  bad <- b$obs; bad$idc <- bad$idc[-1L]
  expect_error(build_stan_model_data(bad, b$design, b$kernels, b$pr), "wrong length")
})
