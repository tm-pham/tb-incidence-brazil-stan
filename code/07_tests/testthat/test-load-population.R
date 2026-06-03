# Tests for the IBGE population transform. Synthetic frames only; the sidrar
# fetch wrapper load_ibge_population() is side-effecting and not tested here.

library(data.table)
source(here::here("code", "02_data_processing", "load_population.R"))

test_that("tidy_population standardises and validates a clean frame", {
  raw <- data.table(muni_code = c("3550308", "3304557"),
                    year = c("2018", "2018"),
                    population = c("12000000", "6700000"))
  out <- tidy_population(raw)
  expect_named(out, c("muni_code", "year", "population"))
  expect_true(is.integer(out$year) && is.numeric(out$population))
  expect_equal(out[muni_code == "3550308", population], 12000000)
  expect_equal(attr(out, "n_dropped_missing"), 0L)
})

test_that("tidy_population maps non-default column names", {
  # Mirrors the wrapper renaming SIDRA columns (code/year/value) to the contract.
  raw <- data.table(cod_muni = "3550308", ano = 2019L, valor = 12100000)
  out <- tidy_population(raw, code_col = "cod_muni",
                         year_col = "ano", value_col = "valor")
  expect_equal(nrow(out), 1L)
  expect_equal(out$population, 12100000)
})

test_that("tidy_population errors on a missing population (no silent drop)", {
  # A municipality-year with no denominator would silently drop out of the
  # canonical universe downstream, so it must fail loudly here.
  raw <- data.table(muni_code = c("3550308", "3304557"),
                    year = c(2018L, 2018L),
                    population = c(12000000, NA))
  expect_error(tidy_population(raw), "NA population")
})

test_that("tidy_population rejects non-positive and duplicated cells", {
  raw_neg <- data.table(muni_code = "3550308", year = 2018L, population = 0)
  expect_error(tidy_population(raw_neg), "non-positive")

  raw_dup <- data.table(muni_code = c("3550308", "3550308"),
                        year = c(2018L, 2018L),
                        population = c(12000000, 12000001))
  expect_error(tidy_population(raw_dup), "duplicated")
})

test_that("tidy_population errors on a non-integer year", {
  raw <- data.table(muni_code = "3550308", year = "twenty-eighteen",
                    population = 12000000)
  expect_error(tidy_population(raw), "non-integer year")
})
