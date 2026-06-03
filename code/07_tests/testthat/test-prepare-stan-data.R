# Tests for prepare_stan_data() and its municipality-code helper. These use
# small synthetic data.tables, so they run anywhere (no SINAN/SIM/IBGE access).

library(data.table)
source(here::here("code", "02_data_processing", "prepare_stan_data.R"))

# A tiny well-formed universe: 3 municipalities x 2 years.
make_pop <- function() {
  CJ(muni_code = c(355030L, 330455L, 530010L), year = c(2018L, 2019L)) |>
    (\(d) d[, population := c(1e6, 1.1e6, 8e5, 8.5e5, 3e6, 3.1e6)][])()
}

test_that("normalise_muni6 reduces 7-digit codes and validates input", {
  expect_identical(normalise_muni6(c("3550308", "3304557")),
                   c(355030L, 330455L))
  expect_identical(normalise_muni6(c(355030L, 330455L)),
                   c(355030L, 330455L))
  expect_error(normalise_muni6(c("3550308", NA)), "NA or empty")
  expect_error(normalise_muni6("12345"), "6 or 7 digits")
})

test_that("prepare_stan_data assembles a correct Stan list on the happy path", {
  pop <- make_pop()
  notif <- data.table(muni_code = c(3550308L, 3304557L),
                      year = c(2018L, 2019L),
                      notifications = c(50L, 40L))
  dth <- data.table(muni_code = 3550308L, year = 2018L, deaths = 3L)

  out <- prepare_stan_data(notif, dth, pop)

  expect_equal(out$N, 6L)
  expect_equal(out$n_areas, 3L)
  expect_equal(out$n_years, 2L)
  # Every municipality kept; cells with no record zero-filled, not dropped.
  expect_equal(sum(out$notifications), 90L)
  expect_equal(sum(out$deaths), 3L)
  expect_equal(out$report$notifications_zero_filled, 4L)
  expect_equal(out$report$deaths_zero_filled, 5L)
  # Offset is log person-time, aligned row-for-row with the counts.
  expect_equal(out$log_pop_offset, log(out$population))
  expect_true(is.integer(out$notifications) && is.integer(out$deaths))
  expect_true(all(out$area %in% 1:3) && all(out$year %in% 1:2))
})

test_that("prepare_stan_data errors on a count outside the population universe", {
  pop <- make_pop()
  # A notification for a year not in the universe is a mismatch, not a drop.
  notif <- data.table(muni_code = 3550308L, year = 2020L, notifications = 5L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  expect_error(prepare_stan_data(notif, dth, pop),
               "absent from the population universe")
})

test_that("prepare_stan_data rejects bad denominators", {
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 1L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())

  pop_neg <- make_pop(); pop_neg[1L, population := 0]
  expect_error(prepare_stan_data(notif, dth, pop_neg), "strictly positive")

  pop_na <- make_pop(); pop_na[1L, population := NA_real_]
  expect_error(prepare_stan_data(notif, dth, pop_na), "NA values")

  pop_dup <- rbind(make_pop(), make_pop()[1L])
  expect_error(prepare_stan_data(notif, dth, pop_dup), "duplicated")
})

test_that("prepare_stan_data rejects non-integer counts", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 2.5)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  expect_error(prepare_stan_data(notif, dth, pop), "non-negative integers")
})

test_that("fill_missing_counts = FALSE turns absent cells into an error", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 1L)
  dth <- data.table(muni_code = 3550308L, year = 2018L, deaths = 0L)
  expect_error(prepare_stan_data(notif, dth, pop, fill_missing_counts = FALSE),
               "no record")
})

test_that("year_range restricts the universe before assembly", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 7L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  out <- prepare_stan_data(notif, dth, pop, year_range = c(2018L, 2018L))
  expect_equal(out$n_years, 1L)
  expect_equal(out$N, 3L)
})

test_that("covariates must cover the universe", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 1L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  # One municipality missing from covariates -> error.
  cov <- data.table(muni_code = c(355030L, 330455L), fhs = c(0.1, -0.2))
  expect_error(prepare_stan_data(notif, dth, pop, covariates = cov),
               "covariates miss")
  # Full coverage -> returns an X matrix aligned to the universe.
  cov_ok <- data.table(muni_code = c(355030L, 330455L, 530010L),
                       fhs = c(0.1, -0.2, 0.3))
  out <- prepare_stan_data(notif, dth, pop, covariates = cov_ok)
  expect_equal(nrow(out$X), out$N)
  expect_equal(colnames(out$X), "fhs")
})

test_that("X rows carry the covariate of the area they are aligned to", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 1L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  cov <- data.table(muni_code = c(355030L, 330455L, 530010L),
                    fhs = c(-1.0, 0.0, 1.0))
  out <- prepare_stan_data(notif, dth, pop, covariates = cov)
  # For each row, X's fhs must equal the covariate for that row's muni_code.
  lookup <- setNames(cov$fhs, as.character(cov$muni_code))
  expect_equal(as.numeric(out$X[, "fhs"]),
               unname(lookup[as.character(out$key$muni_code)]))
})

test_that("year-varying covariates join on muni_code AND year", {
  pop <- make_pop()  # 3 munis x 2 years
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 1L)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  munis <- c(355030L, 330455L, 530010L)
  cov_full <- CJ(muni_code = munis, year = c(2018L, 2019L))[
    , fhs := seq_len(.N) / 10][]
  out <- prepare_stan_data(notif, dth, pop, covariates = cov_full)
  expect_equal(nrow(out$X), out$N)
  # Drop one (muni, year) cell -> the by-year gap check must fire.
  cov_gap <- cov_full[!(muni_code == 530010L & year == 2019L)]
  expect_error(prepare_stan_data(notif, dth, pop, covariates = cov_gap),
               "covariates miss")
})

test_that("prepare_stan_data sums duplicate count rows for the same cell", {
  pop <- make_pop()
  notif <- data.table(muni_code = c(3550308L, 3550308L), year = c(2018L, 2018L),
                      notifications = c(30L, 20L))
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  out <- prepare_stan_data(notif, dth, pop)
  idx <- out$key[muni_code == 355030L & year == 2018L, area_idx]
  cell <- out$key[muni_code == 355030L & year == 2018L, notifications]
  expect_equal(cell, 50L)
  expect_equal(sum(out$notifications), 50L)
})

test_that("prepare_stan_data reports a clean error on integer overflow", {
  pop <- make_pop()
  notif <- data.table(muni_code = 3550308L, year = 2018L, notifications = 3e9)
  dth <- data.table(muni_code = integer(), year = integer(), deaths = integer())
  expect_error(prepare_stan_data(notif, dth, pop), "non-negative integers")
})
