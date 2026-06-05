# Tests for the state population transforms. Synthetic frames only; the sidrar
# fetch wrapper load_ibge_state_population() is side-effecting and not tested.

library(data.table)
source(here::here("code", "02_data_processing", "load_population.R"))

test_that("tidy_state_population standardises and validates", {
  raw <- data.table(uf = c("35", "33"), year = c("2018", "2018"),
                    population = c("45000000", "17000000"))
  out <- tidy_state_population(raw)
  expect_named(out, c("uf", "year", "population"))
  expect_true(is.integer(out$uf) && is.integer(out$year))
  expect_equal(out[uf == 35L, population], 45000000)
})

test_that("tidy_state_population rejects missing / non-positive / duplicate", {
  expect_error(tidy_state_population(
    data.table(uf = 35L, year = 2018L, population = NA_real_)), "strictly")
  expect_error(tidy_state_population(
    data.table(uf = 35L, year = 2018L, population = 0)), "strictly")
  expect_error(tidy_state_population(
    data.table(uf = c(35L, 35L), year = c(2018L, 2018L),
               population = c(1, 2))), "duplicated")
})

test_that("expand_population_monthly fills the full state-month grid", {
  annual <- data.table(uf = c(35L, 35L, 33L, 33L),
                       year = c(2018L, 2019L, 2018L, 2019L),
                       population = c(45e6, 45.5e6, 17e6, 17.1e6))
  out <- expand_population_monthly(annual, 2018L, 2019L, method = "linear")
  expect_equal(nrow(out), 2L * 2L * 12L)            # 2 states x 2 years x 12
  expect_true(all(out$population > 0))
  # Linear interpolation lies between the annual anchors for SP.
  sp <- out[uf == 35L]
  expect_true(all(sp$population >= 45e6 - 1 & sp$population <= 45.5e6 + 1))
  # Monotone increase across the year for SP (population rising).
  expect_true(all(diff(sp[order(year, month), population]) >= 0))
})

test_that("expand_population_monthly constant method repeats annual values", {
  annual <- data.table(uf = 35L, year = c(2018L, 2019L),
                       population = c(45e6, 46e6))
  out <- expand_population_monthly(annual, 2018L, 2019L, method = "constant")
  expect_equal(unique(out[year == 2018L, population]), 45e6)
  expect_equal(unique(out[year == 2019L, population]), 46e6)
})

test_that("expand_population_monthly holds years past the last anchor", {
  # estimates to 2021 + a 2022 census anchor; 2023 has no anchor.
  annual <- data.table(uf = 35L, year = c(2021L, 2022L),
                       population = c(46e6, 44e6))   # census revised down
  out <- expand_population_monthly(annual, 2021L, 2023L, method = "linear")
  expect_equal(nrow(out), 3L * 12L)
  expect_equal(unique(out[year == 2023L, population]), 44e6)  # held at 2022, not 2021
})

test_that("combine_population_sources prefers the census over the estimate", {
  est <- data.table(uf = c(35L, 35L), year = c(2021L, 2022L),
                    population = c(46e6, 46.2e6))    # stale 2022 projection
  cen <- data.table(uf = 35L, year = 2022L, population = 44e6)  # 2022 census
  out <- combine_population_sources(list(census2022 = cen, estimates = est),
                                    priority = c("census2022", "estimates"))
  expect_equal(out[year == 2022L, population], 44e6)            # census wins
  expect_equal(out[year == 2022L, source], "census2022")
  expect_equal(out[year == 2021L, population], 46e6)            # estimate kept
  expect_equal(nrow(out), 2L)
})

test_that("combine_population_sources drops NULL sources and errors usefully", {
  est <- data.table(uf = 35L, year = 2021L, population = 46e6)
  out <- combine_population_sources(list(census2022 = NULL, estimates = est),
                                    priority = c("census2022", "estimates"))
  expect_equal(nrow(out), 1L)
  expect_error(combine_population_sources(list()), "no population source")
  expect_error(
    combine_population_sources(list(x = est), priority = c("estimates")),
    "missing from")
})
