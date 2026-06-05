# Tests for the fixed-delay convolution kernels.

source(here::here("code", "01_functions", "delays.R"))
source(here::here("code", "03_modeling", "priors.R"))

test_that("discretised kernels are valid pmfs summing to 1", {
  k <- build_delay_kernels(priors()$delays)
  expect_equal(sum(k$phi_lambda), 1)
  expect_equal(sum(k$phi_gamma), 1)
  expect_equal(sum(k$phi_mort), 1)
  expect_true(all(k$phi_lambda >= 0))
  expect_length(k$phi_gamma, 7L + 1L)     # lags 0..7
  expect_length(k$phi_mort, 10L + 1L)
})

test_that("kernel means are near the documented monthly delays (floor-bucketed)", {
  k <- build_delay_kernels(priors()$delays)
  lag_mean <- function(p) sum((seq_along(p) - 1) * p)
  # Floor bucketing puts the discretised mean ~0.5 mo below the continuous mean.
  expect_equal(lag_mean(k$phi_gamma), 2.0, tolerance = 0.2)   # cont. 2.5
  expect_equal(lag_mean(k$phi_mort), 3.5, tolerance = 0.2)    # cont. 4.0
  expect_equal(lag_mean(k$phi_lambda), 21.4, tolerance = 1.0) # cont. 22.25 (trunc 60)
})

test_that("causal_convolve shifts and respects the available past", {
  x <- c(1, 2, 3, 4)
  expect_equal(causal_convolve(x, c(1)), x)            # lag-0 kernel = identity
  expect_equal(causal_convolve(x, c(0, 1)), c(0, 1, 2, 3))  # pure 1-month shift
  # Half now, half next month:
  expect_equal(causal_convolve(c(2, 0, 0), c(0.5, 0.5)), c(1, 1, 0))
})

test_that("discretise_delay rejects a degenerate kernel and bad max_months", {
  expect_error(discretise_delay(function(x) rep(0, length(x)), 5L), "degenerate")
  expect_error(weibull_delay(1.75, 25, -1L), "max_months")
})
