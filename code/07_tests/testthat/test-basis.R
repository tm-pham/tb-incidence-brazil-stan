# Tests for the shared design matrices (trend spline, seasonal harmonics, COVID).

source(here::here("code", "01_functions", "basis.R"))

test_that("trend_basis has the right shape and no NA", {
  B <- trend_basis(100L, n_knots = 8L, degree = 3L)
  expect_equal(nrow(B), 100L)
  expect_equal(ncol(B), 8L + 3L)          # n_knots + degree (no intercept col)
  expect_false(anyNA(B))
})

test_that("basis columns are mean-centered (no level direction)", {
  B <- trend_basis(120L, n_knots = 8L, degree = 3L)
  expect_true(all(abs(colMeans(B)) < 1e-9))
  S <- seasonal_basis(1:120, n_harmonics = 2L)
  expect_true(all(abs(colMeans(S)) < 1e-9))
})

test_that("seasonal_basis is cyclic with 12-month period", {
  S <- seasonal_basis(1:24, n_harmonics = 2L)
  expect_equal(ncol(S), 2L * 2L)          # 2 harmonics x (sin, cos)
  # Month m and m+12 give identical seasonal values.
  expect_equal(S[1, ], S[13, ])
  expect_equal(S[5, ], S[17, ])
})

test_that("build_design lays out the extended axis and COVID terms", {
  d <- build_design(n_obs = 24L, n_pre = 10L, start_month_of_year = 1L,
                    covid_break = 16L, n_trend_knots = 6L, n_harmonics = 2L)
  expect_equal(d$n_total, 34L)
  expect_equal(d$obs_index[d$n_pre + 1L], 1L)         # first observed month
  expect_equal(d$obs_index[d$n_total], 24L)
  expect_true(all(d$month_of_year >= 1L & d$month_of_year <= 12L))
  expect_equal(d$month_of_year[d$n_pre + 1L], 1L)     # observed month 1 = January
  # COVID: 0 before break (obs index 16), 1 from there; slope ramps 1,2,...
  expect_equal(sum(d$covid_level), 24L - 16L + 1L)
  expect_true(all(d$covid_level[d$obs_index < 16L] == 0))
  expect_equal(d$covid_slope[d$obs_index == 16L], 1)
  expect_equal(d$covid_slope[d$obs_index == 24L], 9)
  expect_equal(nrow(d$B_trend), 34L)
})

test_that("build_design with no COVID break gives all-zero COVID columns", {
  d <- build_design(n_obs = 24L, n_pre = 10L, covid_break = NULL,
                    n_trend_knots = 6L, n_harmonics = 2L)
  expect_true(all(d$covid_level == 0))
  expect_true(all(d$covid_slope == 0))
})
