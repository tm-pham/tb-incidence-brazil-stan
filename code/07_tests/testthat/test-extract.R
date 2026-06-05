# Tests for tidy_state_estimates() using a MOCK fit (no Stan toolchain): the
# output schema, the per-100k scaling, and the dimension guard.

source(here::here("code", "05_analysis", "extract_estimates.R"))

# Minimal stand-in for a CmdStanFit: $summary(var, ...) returns median/lo/hi.
mock_res <- function(n = 3L) {
  fit <- list(summary = function(var, ...) {
    if (var == "incidence_rate") {
      data.frame(variable = paste0("incidence_rate[", seq_len(n), "]"),
                 median = c(1e-4, 2e-4, 3e-4)[seq_len(n)],
                 lo = c(0.8e-4, 1.8e-4, 2.8e-4)[seq_len(n)],
                 hi = c(1.2e-4, 2.2e-4, 3.2e-4)[seq_len(n)])
    } else {
      data.frame(variable = paste0("detection[", seq_len(n), "]"),
                 median = c(0.5, 0.6, 0.7)[seq_len(n)],
                 lo = c(0.4, 0.5, 0.6)[seq_len(n)],
                 hi = c(0.6, 0.7, 0.8)[seq_len(n)])
    }
  })
  list(fit = fit)
}

test_that("tidy_state_estimates produces the expected schema and scaling", {
  est <- tidy_state_estimates(mock_res(3L), uf = 35L,
                              year = c(2003L, 2003L, 2003L), month = 1:3)
  expect_equal(nrow(est), 3L)
  expect_true(all(c("uf", "year", "month", "incidence_rate", "incidence_lo",
                    "incidence_hi", "incidence_per100k", "detection",
                    "detection_lo", "detection_hi") %in% names(est)))
  expect_equal(est$incidence_rate, c(1e-4, 2e-4, 3e-4))
  expect_equal(est$incidence_per100k, c(10, 20, 30))   # per-capita * 1e5
  expect_equal(est$detection, c(0.5, 0.6, 0.7))
  expect_true(all(est$uf == 35L))
})

test_that("tidy_state_estimates errors on a month-count mismatch", {
  expect_error(
    tidy_state_estimates(mock_res(3L), uf = 35L, year = c(2003L, 2003L),
                         month = 1:2),
    "incidence rows")
})
