# Tests for the panel diagnostics. Synthetic complete panels only.

library(data.table)
source(here::here("code", "04_diagnostics", "check_panel.R"))

# Build a complete synthetic `assembled` list. Defaults produce a CLEAN panel
# (no flags): constant deaths, IDC falling, GeneXpert ~0 pre-2014 then rising.
build <- function(ufs = c(11L, 35L), years = 2013:2015,
                  deaths = 5L, allcause = 1000L,
                  idc = function(y) 0.20 - 0.01 * (y - 2013),
                  gx  = function(y) ifelse(y < 2014L, 0, 0.10 * (y - 2013))) {
  g <- CJ(uf = ufs, year = years, month = 1:12)
  g[, `:=`(notifications = 10L, deaths = deaths, population = 1e6,
           allcause_deaths = allcause, idc = idc(year), genexpert_share = gx(year),
           pri_mort_t = 0.05, pri_aban_t = 0.05)]
  list(panel = g[], n_months = length(years) * 12L, n_states = length(ufs))
}

test_that("a clean panel raises no flags", {
  expect_length(panel_diagnostics(build())$flags, 0L)
})

test_that("zero TB deaths but all-cause present is a real zero, NOT flagged", {
  a <- build()
  a$panel[uf == 11L & year == 2013L, deaths := 0L]   # real low-count zeros
  flags <- panel_diagnostics(a)$flags
  expect_false(any(grepl("gap", flags)))
})

test_that("a zero all-cause state-month is flagged as a download gap", {
  a <- build()
  a$panel[uf == 35L & year == 2014L & month == 6L, allcause_deaths := 0L]
  flags <- panel_diagnostics(a)$flags
  expect_true(any(grepl("ZERO all-cause SIM deaths", flags)))
  expect_true(any(grepl("35/2014-6", flags)))
})

test_that("an implausibly thin all-cause month is flagged (partial gap)", {
  a <- build()
  a$panel[uf == 35L & year == 2014L & month == 6L, allcause_deaths := 3L]
  expect_true(any(grepl("partial gap", panel_diagnostics(a)$flags)))
})

test_that("without all-cause, falls back to the TB-only heuristic", {
  a <- build()
  a$panel[, allcause_deaths := NULL]
  a$panel[uf == 11L & year == 2013L, deaths := 0L]
  expect_true(any(grepl("ZERO total TB deaths", panel_diagnostics(a)$flags)))
})

test_that("a covariate outside [0,1] is flagged", {
  a <- build()
  a$panel[1L, genexpert_share := 1.5]
  expect_true(any(grepl("genexpert_share outside \\[0,1\\]",
                        panel_diagnostics(a)$flags)))
})

test_that("IDC failing to fall over the window is flagged", {
  a <- build(idc = function(y) 0.10 + 0.01 * (y - 2013))   # rising
  expect_true(any(grepl("IDC fraction did not fall", panel_diagnostics(a)$flags)))
})

test_that("GeneXpert present before the rollout era is flagged", {
  a <- build(gx = function(y) ifelse(y < 2014L, 0.20, 0.30))  # high pre-2014
  expect_true(any(grepl("GeneXpert share >5%", panel_diagnostics(a)$flags)))
})

test_that("write_panel_report writes a file and warns on flags", {
  a <- build()
  a$panel[uf == 11L & year == 2013L & month == 1L, allcause_deaths := 0L]
  diag <- panel_diagnostics(a)
  f <- tempfile(fileext = ".txt")
  expect_warning(write_panel_report(diag, f), "ZERO all-cause SIM deaths")
  expect_true(file.exists(f))
  expect_true(any(grepl("panel diagnostics", readLines(f), ignore.case = TRUE)))
})
