# Tests for the estimates figure. The data prep is pure (runs here); the ggplot
# builder skips cleanly where ggplot2 is not installed.

library(data.table)
source(here::here("code", "00_config", "config.R"))
source(here::here("code", "06_visualization", "plot_estimates.R"))

make_inputs <- function() {
  g <- CJ(uf = c(35L, 33L), year = 2003L, month = 1:2)
  estimates <- copy(g)[, `:=`(incidence_rate = 4e-5, incidence_lo = 3e-5,
                              incidence_hi = 5e-5)]
  panel <- copy(g)[, `:=`(notifications = 20L, population = 1e6)]
  list(estimates = estimates, panel = panel)
}

test_that("prepare_incidence_plot_data joins and scales to per-100k", {
  io <- make_inputs()
  pd <- prepare_incidence_plot_data(io$estimates, io$panel, per = 1e5)
  expect_true(all(c("uf", "uf_label", "date", "incidence", "incidence_lo",
                    "incidence_hi", "notification_rate") %in% names(pd)))
  expect_s3_class(pd$date, "Date")
  expect_equal(unique(pd$incidence), 4)                  # 4e-5 * 1e5
  expect_equal(unique(pd$notification_rate), 2)          # 20 / 1e6 * 1e5
  expect_equal(pd[uf == 35L, unique(uf_label)], "SP")
  expect_equal(pd[uf == 33L, unique(uf_label)], "RJ")
  expect_equal(pd[uf == 35L, unique(uf_name)], "Sao Paulo")
  expect_equal(pd[uf == 33L, unique(uf_name)], "Rio de Janeiro")
  expect_match(attr(pd, "rate_label"), "per month")
})

test_that("annualize multiplies monthly rates by 12", {
  io <- make_inputs()
  pd <- prepare_incidence_plot_data(io$estimates, io$panel, annualize = TRUE)
  expect_equal(unique(pd$incidence), 48)                 # 4 * 12
  expect_equal(unique(pd$notification_rate), 24)
  expect_match(attr(pd, "rate_label"), "per year")
})

test_that("a missing panel population errors", {
  io <- make_inputs()
  est <- rbind(io$estimates,
               data.table(uf = 99L, year = 2003L, month = 1L,
                          incidence_rate = 1e-5, incidence_lo = 0.5e-5,
                          incidence_hi = 1.5e-5))
  expect_error(prepare_incidence_plot_data(est, io$panel), "no matching panel")
})

test_that("plot_state_incidence returns a ggplot", {
  testthat::skip_if_not_installed("ggplot2")
  io <- make_inputs()
  pd <- prepare_incidence_plot_data(io$estimates, io$panel)
  g <- plot_state_incidence(pd)
  expect_s3_class(g, "ggplot")
})
