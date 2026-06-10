# Tests for the launch convergence-summary collation (pure; no Stan).

source(here::here("code", "04_diagnostics", "convergence_summary.R"))

good <- list(max_rhat = 1.03, min_ess_bulk = 360, min_ess_tail = 300,
             max_rhat_estimand = 1.004, min_ess_bulk_estimand = 850,
             num_divergent = 12L, num_max_treedepth = 4000L)

test_that("a state with healthy ESTIMANDS passes despite slow nuisance scalars", {
  # Overall min ESS is low (360) and treedepth fully saturated, but the estimands
  # are fine -> OK. This is the whole point of the ship-diag_e decision.
  r <- convergence_row(35L, good, abbrev = "SP", runtime_sec = 5400)
  expect_equal(r$status, "OK")
  expect_equal(r$uf, 35L)
  expect_equal(r$abbrev, "SP")
  expect_equal(r$runtime_min, 90)
  expect_equal(r$notes, "")
  expect_equal(r$num_max_treedepth, 4000L)
})

test_that("poor estimand R-hat or ESS trips a WARN with a reason", {
  bad_rhat <- modifyList(good, list(max_rhat_estimand = 1.05))
  r1 <- convergence_row(33L, bad_rhat, abbrev = "RJ")
  expect_equal(r1$status, "WARN")
  expect_match(r1$notes, "R-hat")

  bad_ess <- modifyList(good, list(min_ess_bulk_estimand = 120))
  r2 <- convergence_row(29L, bad_ess, abbrev = "BA")
  expect_equal(r2$status, "WARN")
  expect_match(r2$notes, "ESS")
})

test_that("thresholds are configurable", {
  r <- convergence_row(35L, good, ess_min = 1000)   # 850 now fails
  expect_equal(r$status, "WARN")
})

test_that("collate puts WARN states first then orders by code", {
  rows <- list(
    convergence_row(35L, good, abbrev = "SP"),
    convergence_row(33L, modifyList(good, list(max_rhat_estimand = 1.2)), abbrev = "RJ"),
    convergence_row(11L, good, abbrev = "RO"))
  out <- collate_convergence(rows)
  expect_equal(nrow(out), 3L)
  expect_equal(out$status[1], "WARN")    # RJ surfaces first
  expect_equal(out$uf[1], 33L)
  expect_equal(out$uf[2:3], c(11L, 35L)) # OK states ordered by code
})

test_that("missing a required diagnostic field errors loudly", {
  expect_error(convergence_row(35L, good[setdiff(names(good), "num_max_treedepth")]),
               "num_max_treedepth")
})
