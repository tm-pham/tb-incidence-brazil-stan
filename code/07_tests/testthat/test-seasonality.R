# Tests for the calendar-month seasonality diagnostic (data-side; no Stan).
# Build a synthetic state-month panel with a KNOWN injected seasonal multiplier on
# top of a declining long-run trend, and confirm the detrended profile recovers
# the injected peak month, amplitude, and strength -- and that a flat series reads
# as no seasonality and an era-growing signal reads as drift.

source(here::here("code", "04_diagnostics", "seasonality.R"))

# rate(year, month) = base * trend(year) * (1 + amp(year) * cos(2pi (m - peak)/12)).
# Dividing by each year's mean removes base and trend, leaving the multiplier; the
# cosine sums to 0 over the 12 months so the yearly mean of the multiplier is 1,
# i.e. the recovered index amplitude is 2 * amp and the peak sits at `peak`.
make_panel <- function(amp = 0.10, peak = 7L, years = 2003:2023, ufs = 35L,
                       pop = 2e6, base = 5e-4, noise_sd = 0, seed = 1L) {
  withr::with_seed(seed, {
    grid <- data.table::CJ(uf = ufs, year = years, month = 1:12)
    grid[, trend := exp(-0.01 * (year - min(year)))]
    a <- if (is.function(amp)) vapply(grid$year, amp, numeric(1)) else amp
    grid[, mult := 1 + a * cos(2 * pi * (month - peak) / 12)]
    grid[, eps := if (noise_sd > 0) stats::rnorm(.N, 0, noise_sd) else 0]
    grid[, rate := base * trend * mult * (1 + eps)]
    grid[, population := pop]
    grid[, notifications := as.integer(round(rate * population))]
    grid[, deaths := as.integer(round(0.04 * rate * population))]
    grid[, .(uf, year, month, population, notifications, deaths)]
  })
}

test_that("seasonal_profile recovers a known injected seasonal signal", {
  panel <- make_panel(amp = 0.10, peak = 7L)
  sp <- seasonal_profile(panel, value = "notifications", uf = 35L)
  expect_equal(nrow(sp$profile), 12L)              # one era, 12 months
  expect_equal(sp$amplitude$peak_month, 7L)
  expect_equal(sp$amplitude$trough_month, 1L)      # cos = -1 at m = 1
  expect_equal(sp$amplitude$amplitude, 0.20, tolerance = 0.01)   # 2 * amp
  expect_gt(sp$amplitude$seasonal_strength, 0.99)  # deterministic -> ~1
  # Index is centred on 1 and the peak is above, trough below.
  expect_equal(mean(sp$profile$index_mean), 1, tolerance = 1e-3)
  expect_gt(sp$profile$index_mean[7], sp$profile$index_mean[1])
})

test_that("a flat series reads as no seasonality", {
  panel <- make_panel(amp = 0, noise_sd = 0.02, seed = 5L)
  sp <- seasonal_profile(panel, value = "notifications", uf = 35L)
  expect_lt(sp$amplitude$amplitude, 0.03)          # only noise survives averaging
  expect_lt(sp$amplitude$seasonal_strength, 0.30)  # no stable monthly pattern
})

test_that("era split reveals a strengthening seasonal signal (drift)", {
  amp_fun <- function(y) if (y <= 2009) 0.05 else if (y <= 2016) 0.15 else 0.25
  panel <- make_panel(amp = amp_fun, peak = 7L)
  sp <- seasonal_profile(panel, value = "notifications", uf = 35L,
                         era_breaks = c(2009L, 2016L))
  expect_equal(data.table::uniqueN(sp$profile$era), 3L)
  a <- sp$amplitude[order(era)]                    # eras sort chronologically
  expect_equal(a$amplitude, c(0.10, 0.30, 0.50), tolerance = 0.02)  # 2 * amp per era
  expect_true(all(a$peak_month == 7L))             # phase stable, amplitude grows
})

test_that("pooling across states and the deaths channel both run", {
  panel <- make_panel(amp = 0.08, peak = 6L, ufs = c(35L, 33L))
  pooled <- seasonal_profile(panel, value = "deaths", uf = NULL)
  expect_equal(nrow(pooled$profile), 12L)
  expect_equal(pooled$amplitude$peak_month, 6L)
})

test_that("seasonal_profile is deterministic", {
  panel <- make_panel(amp = 0.12, peak = 8L, noise_sd = 0.03, seed = 9L)
  a <- seasonal_profile(panel, uf = 35L)
  b <- seasonal_profile(panel, uf = 35L)
  expect_equal(a$profile, b$profile)
  expect_equal(a$amplitude, b$amplitude)
})
