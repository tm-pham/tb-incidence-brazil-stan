# Simulator <-> Stan agreement (without a Stan toolchain): the R mirror of the
# Stan transformed-parameters block (tb_forward) must reproduce the simulator's
# expected counts and latent estimands for the same design and parameters. A
# divergence here means the Stan model and the simulator would disagree.

source(here::here("code", "01_functions", "simulate.R"))
source(here::here("code", "03_modeling", "stan_data.R"))
source(here::here("code", "03_modeling", "forward.R"))

test_that("tb_forward reproduces the simulator's expected counts exactly", {
  pr <- priors()
  kernels <- build_delay_kernels(pr$delays)
  n_obs <- 96L
  design <- build_design(n_obs, n_pre = default_n_pre(pr), start_month_of_year = 1L,
                         covid_break = 80L, n_trend_knots = 7L, n_harmonics = 2L)
  params <- default_true_params(design, seed = 5L)
  cov <- synthetic_covariates(n_obs)

  # Simulator computes exp_notif / exp_deaths internally; build Stan data from
  # the SAME observed series and run the forward mirror with the SAME params.
  sim <- simulate_state_month(design, kernels, params, cov, seed = 5L)
  obs <- list(population = cov$population, sinan = sim$notifications,
              sim = sim$deaths, idc = cov$idc, genexpert = cov$genexpert,
              pri_mort_t = cov$pri_mort_t, pri_aban_t = cov$pri_aban_t)
  sd <- build_stan_model_data(obs, design, kernels, pr)
  fwd <- tb_forward(sd, params)

  expect_equal(fwd$exp_notif, sim$exp_notif, tolerance = 1e-9)
  expect_equal(fwd$exp_deaths, sim$exp_deaths, tolerance = 1e-9)
  expect_equal(fwd$incidence_rate, sim$true_gamma, tolerance = 1e-9)
  expect_equal(fwd$detection, sim$true_delta, tolerance = 1e-9)
  expect_equal(fwd$death_adj, sim$true_death_adj, tolerance = 1e-9)
})
