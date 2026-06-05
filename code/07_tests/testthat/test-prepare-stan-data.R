# Tests for the state-month assembly. Synthetic frames only.

library(data.table)
source(here::here("code", "02_data_processing", "prepare_stan_data.R"))

UFS <- c(35L, 33L)
YS <- 2018L; YE <- 2019L

# Full population grid for the test universe (2 states x 2 years x 12 months).
make_pop <- function() {
  g <- CJ(uf = UFS, year = YS:YE, month = 1:12)
  g[, population := 1e6 + uf * 1000L + (year - YS) * 100L][]
}

args0 <- function(...) {
  list(year_start = YS, year_end = YE, uf_codes = UFS,
       covid_break_year = 2020L, covid_break_month = 4L, ...)
}

test_that("prepare_stan_data builds the complete grid and zero-fills", {
  pop <- make_pop()
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 50L)
  dth   <- data.table(uf = 35L, year = 2018L, month = 3L, deaths = 4L)
  out <- do.call(prepare_stan_data,
                 c(list(notif, dth, pop), args0()))
  expect_equal(out$n_states, 2L)
  expect_equal(out$n_months, 24L)
  expect_equal(nrow(out$panel), 2L * 24L)           # complete 2 x 24 grid
  expect_equal(sum(out$panel$notifications), 50L)
  expect_equal(sum(out$panel$deaths), 4L)
  expect_equal(out$report$notifications_zero_filled, 2L * 24L - 1L)
  expect_true(is.integer(out$panel$notifications))
  expect_equal(out$panel$log_pop_offset, log(out$panel$population))
})

test_that("time, COVID, and seasonal columns are correct", {
  pop <- make_pop()
  notif <- data.table(uf = integer(), year = integer(), month = integer(),
                      notifications = integer())
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0()))
  p <- out$panel
  expect_equal(p[uf == 35L & year == 2018L & month == 1L, t], 1L)
  expect_equal(p[uf == 35L & year == 2019L & month == 12L, t], 24L)
  expect_true(all(p$month_of_year %in% 1:12))
  # COVID break is in 2020, outside this 2018-2019 window, so no cell is post.
  expect_equal(sum(p$covid_level), 0L)
})

test_that("covariates join and undefined cells are reported as NA", {
  pop <- make_pop()
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 10L)
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  gx <- data.table(uf = 35L, year = 2018L, month = 3L, genexpert_share = 0.4)
  out <- do.call(prepare_stan_data,
                 c(list(notif, dth, pop), args0(genexpert = gx)))
  expect_equal(out$panel[uf == 35L & year == 2018L & month == 3L,
                         genexpert_share], 0.4)
  expect_equal(out$report$genexpert_missing, 2L * 24L - 1L)  # only one cell set
})

test_that("all-cause deaths (n_deaths) carry through from idc as allcause_deaths", {
  pop <- make_pop()
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 10L)
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  idc <- data.table(uf = 35L, year = 2018L, month = 3L, idc = 0.1, n_deaths = 500L)
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0(idc = idc)))
  expect_true("allcause_deaths" %in% names(out$panel))
  expect_equal(out$panel[uf == 35L & year == 2018L & month == 3L, allcause_deaths],
               500L)
})

test_that("missing population denominator errors", {
  pop <- make_pop()[-1L]   # drop one grid cell
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 1L)
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  expect_error(do.call(prepare_stan_data, c(list(notif, dth, pop), args0())),
               "no population denominator")
})

test_that("a count outside the grid errors (orphan)", {
  pop <- make_pop()
  notif <- data.table(uf = 99L, year = 2018L, month = 3L, notifications = 1L)
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  expect_error(do.call(prepare_stan_data, c(list(notif, dth, pop), args0())),
               "outside the grid")
})

test_that("COVID level/slope are correct when the break is inside the window", {
  ufs <- c(35L, 33L)
  pop <- CJ(uf = ufs, year = 2019:2021, month = 1:12)[, population := 1e6][]
  notif <- data.table(uf = integer(), year = integer(), month = integer(),
                      notifications = integer())
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  out <- prepare_stan_data(notif, dth, pop, year_start = 2019L, year_end = 2021L,
                           uf_codes = ufs, covid_break_year = 2020L,
                           covid_break_month = 4L)
  p <- out$panel[uf == 35L][order(year, month)]
  # Apr 2020 .. Dec 2021 = 9 + 12 = 21 post-break months.
  expect_equal(sum(p$covid_level), 21L)
  expect_equal(p[year == 2020L & month == 3L, covid_level], 0L)
  expect_equal(p[year == 2020L & month == 4L, covid_level], 1L)
  expect_equal(p[covid_level == 1L, covid_slope], 1:21)
  expect_true(all(p[covid_level == 0L, covid_slope] == 0L))
})

test_that("treatment covariates join and report missing", {
  pop <- make_pop()
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 10L)
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  trt <- data.table(uf = 35L, year = 2018L, month = 3L,
                    pri_mort_t = 0.04, pri_aban_t = 0.1)
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0(treatment = trt)))
  expect_equal(out$panel[uf == 35L & year == 2018L & month == 3L, pri_mort_t], 0.04)
  expect_equal(out$report$treatment_missing, 2L * 24L - 1L)
})

test_that("deaths are integer and the zero-fill count is reported", {
  pop <- make_pop()
  notif <- data.table(uf = integer(), year = integer(), month = integer(),
                      notifications = integer())
  dth <- data.table(uf = 35L, year = 2018L, month = 3L, deaths = 4L)
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0()))
  expect_true(is.integer(out$panel$deaths))
  expect_equal(out$report$deaths_zero_filled, 2L * 24L - 1L)
})

test_that("the grid-size guard fails loudly on a wrong grid", {
  pop <- make_pop()
  notif <- data.table(uf = integer(), year = integer(), month = integer(),
                      notifications = integer())
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  expect_error(
    do.call(prepare_stan_data, c(list(notif, dth, pop), args0(expect_n_states = 27L))),
    "expected 27 states")
  expect_error(
    do.call(prepare_stan_data, c(list(notif, dth, pop), args0(expect_n_months = 252L))),
    "expected 252 months")
})

test_that("stan_data_for_state errors on an unknown state", {
  pop <- make_pop()
  notif <- data.table(uf = integer(), year = integer(), month = integer(),
                      notifications = integer())
  dth <- data.table(uf = integer(), year = integer(), month = integer(),
                    deaths = integer())
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0()))
  expect_error(stan_data_for_state(out, 99L), "no rows for uf")
})

test_that("stan_data_for_state slices one state's 252-month series", {
  pop <- make_pop()
  notif <- data.table(uf = 35L, year = 2018L, month = 3L, notifications = 7L)
  dth <- data.table(uf = 35L, year = 2018L, month = 3L, deaths = 1L)
  gx <- data.table(uf = 35L, year = 2018L, month = 3L, genexpert_share = 0.4)
  out <- do.call(prepare_stan_data, c(list(notif, dth, pop), args0(genexpert = gx)))
  sd <- stan_data_for_state(out, 35L)
  expect_equal(sd$N, 24L)
  expect_equal(sd$uf, 35L)
  expect_equal(sd$t, 1:24)
  expect_equal(sum(sd$notifications), 7L)
  expect_true("genexpert_share" %in% names(sd))
})
