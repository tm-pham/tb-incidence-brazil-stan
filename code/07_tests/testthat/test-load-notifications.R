# Tests for the SINAN notification transforms. Synthetic frames only; the
# file-reading wrapper load_sinan_tb_notifications() is side-effecting and not
# tested here (it reads the local SINAN-TB export).

library(data.table)
source(here::here("code", "02_data_processing", "load_notifications.R"))

# SINAN TRATAMENTO codes (per the dictionary): 1 = new case, 2 = relapse,
# 3 = re-entry after abandonment, 4 = unknown, 5 = transfer, 6 = post-mortem (v5).
KEEP <- c("1", "2")

test_that("sinan_year extracts the year from SINAN and ISO dates and Dates", {
  expect_equal(sinan_year(c("20150321", "20191130")), c(2015L, 2019L))
  expect_equal(sinan_year(c("2015-03-21", "2019-11-30")), c(2015L, 2019L))
  expect_equal(sinan_year(as.Date(c("2015-03-21", "2019-11-30"))),
               c(2015L, 2019L))
})

test_that("standardise_sinan_tb maps dictionary columns to the contract", {
  raw <- data.table(TRATAMENTO = c("1", "2"),
                    ID_MN_RESI = c("355030", "330455"),
                    ID_MUNICIP = c("355030", "330455"),
                    DT_DIAG    = c("20180101", "20180202"),
                    other_col  = c("x", "y"))
  s <- standardise_sinan_tb(raw)
  expect_named(s, c("entry_type", "muni_res", "muni_occ", "year"))
  expect_equal(s$entry_type, c("1", "2"))
  expect_equal(s$year, c(2018L, 2018L))
})

test_that("standardise_sinan_tb errors when dictionary columns are missing", {
  expect_error(standardise_sinan_tb(data.table(foo = 1L)),
               "missing column")
})

test_that("standardise_sinan_tb feeds summarise_notifications end to end", {
  raw <- data.table(TRATAMENTO = c("1", "2", "3", "6"),
                    ID_MN_RESI = rep("3550308", 4),
                    ID_MUNICIP = rep("3550308", 4),
                    DT_DIAG    = rep("20180101", 4))
  out <- summarise_notifications(standardise_sinan_tb(raw), keep_entry = KEEP)
  # new + relapse counted (2); re-entry and post-mortem dropped.
  expect_equal(sum(out$notifications), 2L)
  expect_equal(out$muni_code, 355030L)
})

test_that("summarise_notifications keeps only the requested entry types", {
  sinan <- data.table(
    entry_type = c("1", "2", "3", "4", "5", "6", "1"),
    muni_res   = rep("355030", 7),
    muni_occ   = rep("355030", 7),
    year       = rep(2018L, 7)
  )
  out <- summarise_notifications(sinan, keep_entry = KEEP)
  # New (x2) + relapse (x1) counted; re-entry(3), unknown(4), transfer(5), and
  # post-mortem(6) all dropped.
  expect_equal(sum(out$notifications), 3L)
  expect_true(is.integer(out$notifications))
})

test_that("summarise_notifications returns an empty typed table when none match", {
  sinan <- data.table(entry_type = c("3", "5", "6"),
                      muni_res = rep("355030", 3), muni_occ = rep("355030", 3),
                      year = rep(2018L, 3))
  out <- summarise_notifications(sinan, keep_entry = KEEP)
  expect_equal(nrow(out), 0L)
  expect_named(out, c("muni_code", "year", "notifications"))
  expect_true(is.integer(out$notifications))
})

test_that("summarise_notifications requires keep_entry to be supplied", {
  sinan <- data.table(entry_type = "1", muni_res = "355030",
                      muni_occ = "355030", year = 2018L)
  expect_error(summarise_notifications(sinan), "keep_entry must list")
  expect_error(summarise_notifications(sinan, keep_entry = character()),
               "keep_entry must list")
})

test_that("summarise_notifications uses residence with notification fallback", {
  sinan <- data.table(
    entry_type = c("1", "1", "2"),
    muni_res   = c("355030", NA, "999999"),   # row 2 NA, row 3 sentinel
    muni_occ   = c("330455", "330455", "330455"),
    year       = rep(2020L, 3)
  )
  out <- summarise_notifications(sinan, keep_entry = KEEP)
  expect_equal(out[muni_code == 330455L, notifications], 2L)
  expect_equal(out[muni_code == 355030L, notifications], 1L)
})

test_that("summarise_notifications aggregates to municipality-year", {
  sinan <- data.table(
    entry_type = rep("1", 4),
    muni_res   = c("3550308", "3550308", "3304557", "3550308"),
    muni_occ   = rep("3550308", 4),
    year       = c(2018L, 2018L, 2018L, 2019L)
  )
  out <- summarise_notifications(sinan, keep_entry = KEEP)
  expect_equal(out[muni_code == 355030L & year == 2018L, notifications], 2L)
  expect_equal(out[muni_code == 355030L & year == 2019L, notifications], 1L)
  expect_equal(out[muni_code == 330455L & year == 2018L, notifications], 1L)
})
