# Tests for the SINAN notification transform. Synthetic frames only; the DATASUS
# fetch wrapper load_sinan_tb_notifications() is side-effecting and not tested.

library(data.table)
source(here::here("code", "02_data_processing", "load_notifications.R"))

# SINAN TRATAMENTO codes (per the dictionary): 1 = new case, 2 = relapse,
# 3 = re-entry after abandonment, 4 = unknown, 5 = transfer, 6 = post-mortem (v5).
KEEP <- c("1", "2")

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
