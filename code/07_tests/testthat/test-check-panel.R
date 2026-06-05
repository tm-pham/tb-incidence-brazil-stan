# Tests for the panel diagnostics. Synthetic complete panels only.

library(data.table)
source(here::here("code", "04_diagnostics", "check_panel.R"))

# Build a complete synthetic `assembled` list. Defaults produce a CLEAN panel
# (no flags): constant deaths, IDC falling, GeneXpert ~0 pre-2014 then rising.
build <- function(ufs = c(11L, 35L), years = 2013:2015,
                  deaths = 5L,
                  idc = function(y) 0.20 - 0.01 * (y - 2013),
                  gx  = function(y) ifelse(y < 2014L, 0, 0.10 * (y - 2013))) {
  g <- CJ(uf = ufs, year = years, month = 1:12)
  g[, `:=`(notifications = 10L, deaths = deaths, population = 1e6,
           idc = idc(year), genexpert_share = gx(year),
           pri_mort_t = 0.05, pri_aban_t = 0.05)]
  list(panel = g[], n_months = length(years) * 12L, n_states = length(ufs))
}

test_that("a clean panel raises no flags", {
  expect_length(panel_diagnostics(build())$flags, 0L)
})

test_that("a zero-death state-year is flagged (SIM gap, as RN-2010 was)", {
  a <- build()
  a$panel[uf == 11L & year == 2013L, deaths := 0L]   # whole state-year dropped
  flags <- panel_diagnostics(a)$flags
  expect_true(any(grepl("ZERO total TB deaths", flags)))
  expect_true(any(grepl("11/2013", flags)))
})

test_that("a high-burden state with a zero-death month is flagged", {
  a <- build(deaths = 10L)
  a$panel[uf == 35L & year == 2014L & month == 6L, deaths := 0L]
  flags <- panel_diagnostics(a)$flags
  expect_true(any(grepl("zero-death month", flags)))
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
  a$panel[uf == 11L & year == 2013L, deaths := 0L]
  diag <- panel_diagnostics(a)
  f <- tempfile(fileext = ".txt")
  expect_warning(write_panel_report(diag, f), "ZERO total TB deaths")
  expect_true(file.exists(f))
  expect_true(any(grepl("panel diagnostics", readLines(f), ignore.case = TRUE)))
})
