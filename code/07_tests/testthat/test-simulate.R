# Fast invariant tests for the generative simulator (code/01_functions/simulate.R).
# These do not sample with Stan; they pin determinism, dimensions, types, and the
# rate/likelihood structure. The gated recovery test lives separately.

source(here::here("code", "01_functions", "simulate.R"))

test_that("tb_natural_history returns valid probabilities and derived CFRs", {
  nat <- tb_natural_history()
  for (p in c("mu", "delta", "p_death_tx", "p_ltfu", "pi", "rho")) {
    expect_true(nat[[p]] >= 0 && nat[[p]] <= 1)
  }
  expect_equal(nat$cfr_untreated, 1 - nat$mu)
  expect_equal(nat$cfr_treated, nat$p_death_tx + nat$p_ltfu * nat$delta)
  expect_true(nat$cfr_treated >= 0 && nat$cfr_treated <= 1)
})

test_that("tb_natural_history rejects out-of-range parameters", {
  expect_error(tb_natural_history(mu = 1.2))
  expect_error(tb_natural_history(delta = -0.1))
})

test_that("simulate_tb_counts is reproducible given a seed", {
  pop <- rep(5e4, 20); a <- rep(4e-4, 20); b <- rep(0.85, 20)
  d1 <- simulate_tb_counts(pop, a, b, seed = 42L)
  d2 <- simulate_tb_counts(pop, a, b, seed = 42L)
  expect_identical(d1$notifications, d2$notifications)
  expect_identical(d1$deaths, d2$deaths)
})

test_that("simulate_tb_counts does not touch the global RNG state", {
  set.seed(99L); before <- runif(1)
  set.seed(99L)
  invisible(simulate_tb_counts(rep(5e4, 5), rep(4e-4, 5), rep(0.8, 5), seed = 7L))
  after <- runif(1)
  expect_identical(before, after)
})

test_that("simulate_tb_counts returns non-negative integer counts", {
  d <- simulate_tb_counts(rep(5e4, 50), rep(4e-4, 50), rep(0.85, 50), seed = 1L)
  for (col in c("notifications", "deaths")) {
    x <- d[[col]]
    expect_true(all(x >= 0))
    expect_true(all(x == as.integer(x)))
  }
})

test_that("simulate_tb_counts expected means follow the likelihood formula", {
  nat <- tb_natural_history()
  pop <- 5e4; a <- 4e-4; b <- 0.85
  d <- simulate_tb_counts(pop, a, b, nat = nat, seed = 1L)
  dpc <- b * nat$cfr_treated + (1 - b) * nat$cfr_untreated
  expect_equal(d$notif_mean, pop * a * b)
  expect_equal(d$death_mean, pop * a * dpc * nat$pi * nat$rho)
})

test_that("simulate_tb_counts validates its inputs", {
  expect_error(simulate_tb_counts(c(1, 2), c(1, 2, 3), c(0.5, 0.5)))
  expect_error(simulate_tb_counts(c(-1), c(1e-4), c(0.5)))
  expect_error(simulate_tb_counts(c(1e4), c(-1e-4), c(0.5)))
  expect_error(simulate_tb_counts(c(1e4), c(1e-4), c(1.5)))
})

test_that("simulate_tb_dataset has correct dimensions and columns", {
  out <- simulate_tb_dataset(n_areas = 30L, n_years = 4L, seed = 3L)
  expect_equal(nrow(out$data), 30L * 4L)
  expect_setequal(
    names(out$data),
    c("area", "year", "population", "fhs", "log_gdp", "notifications", "deaths")
  )
  expect_equal(length(out$truth$alpha), 30L * 4L)
  expect_equal(length(out$truth$beta), 30L * 4L)
})

test_that("simulate_tb_dataset keeps rates in valid ranges", {
  out <- simulate_tb_dataset(n_areas = 40L, n_years = 5L, seed = 5L)
  expect_true(all(out$truth$alpha > 0))
  expect_true(all(out$truth$beta >= 0 & out$truth$beta <= 1))
  expect_true(all(out$data$population > 0))
  expect_true(all(out$data$notifications >= 0))
  expect_true(all(out$data$deaths >= 0))
  expect_true(all(out$data$notifications == as.integer(out$data$notifications)))
  expect_true(all(out$data$deaths == as.integer(out$data$deaths)))
})

test_that("simulate_tb_dataset is reproducible and seed-sensitive", {
  a <- simulate_tb_dataset(n_areas = 25L, n_years = 4L, seed = 11L)
  b <- simulate_tb_dataset(n_areas = 25L, n_years = 4L, seed = 11L)
  c <- simulate_tb_dataset(n_areas = 25L, n_years = 4L, seed = 12L)
  expect_identical(a$data$notifications, b$data$notifications)
  expect_identical(a$data$deaths, b$data$deaths)
  expect_false(identical(a$data$notifications, c$data$notifications))
})

test_that("demeaned area and year effects identify the intercepts", {
  # With covariate coefficients zeroed and no count noise, the mean of log alpha
  # over the grid should equal phi0 (area and year effects demean out).
  out <- simulate_tb_dataset(n_areas = 200L, n_years = 6L,
                             phi0 = -7.8, omega0 = 1.7,
                             phi = c(0, 0), omega = c(0, 0), seed = 21L)
  expect_equal(mean(log(out$truth$alpha)), -7.8, tolerance = 1e-8)
  expect_equal(mean(stats::qlogis(out$truth$beta)), 1.7, tolerance = 1e-8)
})
