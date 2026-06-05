# Tests for the SIM state-month transforms. Synthetic frames only; the DATASUS
# fetch wrapper load_sim_records() is side-effecting and not tested here.

library(data.table)
source(here::here("code", "02_data_processing", "load_sim.R"))

test_that("sim_year / sim_month read ddmmyyyy (and Date)", {
  expect_equal(sim_year(c("15032018", "01122019")), c(2018L, 2019L))
  expect_equal(sim_month(c("15032018", "01122019")), c(3L, 12L))
  expect_equal(sim_month("1032018"), 3L)          # dropped leading zero on day
  expect_equal(sim_year(as.Date("2018-03-15")), 2018L)
  expect_equal(sim_month(as.Date("2018-03-15")), 3L)
})

test_that("standardise_sim rolls up to state-month with residence fallback", {
  sim <- data.table(
    cause    = c("A150", "J189", "R99"),
    muni_res = c("355030", NA, "330455"),         # row 2 -> occurrence fallback
    muni_occ = c("355030", "355030", "330455"),
    date     = c("15032018", "20062018", "11112019")
  )
  recs <- standardise_sim(sim)
  expect_named(recs, c("cause", "uf", "year", "month"))
  expect_equal(recs$uf, c(35L, 35L, 33L))          # 355030->35, 330455->33
  expect_equal(recs$year, c(2018L, 2018L, 2019L))
  expect_equal(recs$month, c(3L, 6L, 11L))
  expect_equal(attr(recs, "n_residence_fallback"), 1L)
})

test_that("standardise_sim drops unattributable and bad-date records, counting both", {
  sim <- data.table(
    cause    = c("A150", "J189", "R99", "B900"),
    muni_res = c("355030", NA,       "999999", "355030"), # row3 both invalid
    muni_occ = c("355030", "330455", "999999", "355030"), # row2 occ fallback
    date     = c("15032018", "20062018", "11112019", "")  # row4 blank date
  )
  recs <- standardise_sim(sim)
  expect_equal(attr(recs, "n_unattributable"), 1L)   # row 3
  expect_equal(attr(recs, "n_bad_date"), 1L)         # row 4 (blank)
  expect_equal(nrow(recs), 2L)                        # rows 1,2 survive
  expect_false(anyNA(recs$year))
})

test_that("idc_fraction on an empty record set returns no rows", {
  empty <- data.table(cause = character(), uf = integer(),
                      year = integer(), month = integer())
  expect_equal(nrow(idc_fraction(empty)), 0L)
})

test_that("filter_tb_deaths keeps only A15-A19 and counts by state-month", {
  recs <- data.table(
    cause = c("A150", "A162", "A199", "B900", "J189", "A150"),
    uf    = c(35L, 35L, 33L, 35L, 35L, 35L),
    year  = c(2018L, 2018L, 2018L, 2018L, 2018L, 2019L),
    month = c(3L, 3L, 5L, 3L, 3L, 1L)
  )
  out <- filter_tb_deaths(recs)
  expect_equal(out[uf == 35L & year == 2018L & month == 3L, deaths], 2L)  # A150,A162
  expect_equal(out[uf == 33L & year == 2018L & month == 5L, deaths], 1L)  # A199
  expect_equal(out[uf == 35L & year == 2019L & month == 1L, deaths], 1L)
  expect_true(is.integer(out$deaths))
  expect_false(any(out$year == 2018L & out$month == 3L & out$uf == 35L &
                     out$deaths == 3L))  # B900/J189 excluded
})

test_that("idc_fraction is the ill-defined share of all-cause deaths", {
  recs <- data.table(
    cause = c("A150", "R98", "R99", "J189"),   # 2 of 4 are R-codes
    uf    = rep(35L, 4),
    year  = rep(2018L, 4),
    month = rep(3L, 4)
  )
  out <- idc_fraction(recs)
  expect_equal(out$n_deaths, 4L)
  expect_equal(out$n_idc, 2L)
  expect_equal(out$idc, 0.5)
  expect_true(out$idc >= 0 && out$idc <= 1)
})
