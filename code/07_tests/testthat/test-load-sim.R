# Tests for the SIM TB-death transform. Synthetic frames only; the DATASUS
# fetch wrapper load_sim_deaths() is side-effecting and not tested here.

library(data.table)
source(here::here("code", "02_data_processing", "load_sim.R"))

test_that("filter_tb_deaths keeps only A15-A19 underlying causes", {
  sim <- data.table(
    cause    = c("A150", "A162", "A199", "B900", "J189", "A179"),
    muni_res = rep("355030", 6),
    muni_occ = rep("355030", 6),
    year     = rep(2018L, 6)
  )
  out <- filter_tb_deaths(sim)
  # A150, A162, A199, A179 are TB; B900 (sequelae) and J189 (pneumonia) are not.
  expect_equal(sum(out$deaths), 4L)
  expect_true(is.integer(out$deaths))
})

test_that("filter_tb_deaths attributes to residence with occurrence fallback", {
  sim <- data.table(
    cause    = c("A150", "A150", "A150"),
    muni_res = c("355030", "", NA),          # row 2 blank, row 3 NA -> fallback
    muni_occ = c("330455", "330455", "330455"),
    year     = c(2019L, 2019L, 2019L)
  )
  out <- filter_tb_deaths(sim)
  # Row 1 -> residence 355030; rows 2 and 3 -> occurrence 330455.
  expect_setequal(out$muni_code, c(355030L, 330455L))
  expect_equal(out[muni_code == 330455L, deaths], 2L)
  expect_equal(out[muni_code == 355030L, deaths], 1L)
})

test_that("filter_tb_deaths aggregates to municipality-year and 6-digit key", {
  sim <- data.table(
    cause    = rep("A160", 4),
    muni_res = c("3550308", "3550308", "3304557", "3550308"),  # 7-digit codes
    muni_occ = rep("3550308", 4),
    year     = c(2018L, 2018L, 2018L, 2019L)
  )
  out <- filter_tb_deaths(sim)
  expect_equal(out[muni_code == 355030L & year == 2018L, deaths], 2L)
  expect_equal(out[muni_code == 355030L & year == 2019L, deaths], 1L)
  expect_equal(out[muni_code == 330455L & year == 2018L, deaths], 1L)
  expect_true(all(out$muni_code < 1e6))  # reduced to 6 digits
})

test_that("filter_tb_deaths returns an empty typed table when nothing matches", {
  sim <- data.table(cause = "J189", muni_res = "355030",
                    muni_occ = "355030", year = 2018L)
  out <- filter_tb_deaths(sim)
  expect_equal(nrow(out), 0L)
  expect_named(out, c("muni_code", "year", "deaths"))
})
