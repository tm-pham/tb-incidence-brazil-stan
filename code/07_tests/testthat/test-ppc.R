# Tests for the predictive-check coverage math (pure; no Stan needed).

source(here::here("code", "04_diagnostics", "ppc.R"))

test_that("ppc_coverage recovers nominal coverage for well-calibrated reps", {
  withr::local_seed(1)
  N <- 200L; draws <- 2000L
  means <- runif(N, 5, 50)
  rep_matrix <- sapply(means, function(m) rpois(draws, m))   # draws x N
  observed <- rpois(N, means)                                 # from the same DGP
  res <- ppc_coverage(rep_matrix, observed, prob = 0.90)
  expect_gt(res$coverage, 0.80)            # ~0.90 nominal, allow MC slack
  expect_lt(res$coverage, 0.98)            # not an over-wide interval
  expect_gt(res$mean_bayes_p, 0.3)         # centred, not systematically off
  expect_lt(res$mean_bayes_p, 0.7)
})

test_that("ppc_coverage flags a systematic shift", {
  withr::local_seed(2)
  N <- 100L; draws <- 1000L
  rep_matrix <- sapply(rep(10, N), function(m) rpois(draws, m))
  observed <- rep(40L, N)                  # far above the predictive mass
  res <- ppc_coverage(rep_matrix, observed, prob = 0.90)
  expect_lt(res$coverage, 0.1)
  expect_lt(res$mean_bayes_p, 0.05)        # reps almost never exceed obs
})

test_that("ppc_coverage errors on a shape mismatch", {
  expect_error(ppc_coverage(matrix(0, 10, 5), 1:6), "columns")
})
