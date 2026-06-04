# Tests for the SINAN state-month transforms. Synthetic frames only; the
# file-reading wrapper load_sinan_records() is side-effecting and not tested.

library(data.table)
source(here::here("code", "02_data_processing", "load_notifications.R"))

# TRATAMENTO: 1=new, 2=relapse, 3=re-entry, 4=unknown, 5=transfer, 6=post-mortem.
KEEP <- c("1", "2")

test_that("sinan_year / sinan_month read YYYYMMDD, ISO, and Date", {
  expect_equal(sinan_year(c("20180101", "20191130")), c(2018L, 2019L))
  expect_equal(sinan_month(c("20180101", "20191130")), c(1L, 11L))
  expect_equal(sinan_month(c("2018-03-21")), 3L)             # ISO
  expect_equal(sinan_month(as.Date("2018-03-21")), 3L)       # Date
})

test_that("standardise_sinan_tb rolls up to state-month and carries fields", {
  raw <- data.table(
    TRATAMENTO = c("1", "2"),
    ID_MN_RESI = c("355030", "330455"),
    ID_MUNICIP = c("355030", "330455"),
    DT_DIAG    = c("20180115", "20180220"),
    SITUA_ENCE = c("1", "3"),
    TEST_MOLEC = c("1", "5")
  )
  recs <- standardise_sinan_tb(raw)
  expect_named(recs, c("entry_type", "uf", "year", "month",
                       "situa_ence", "test_molec"))
  expect_equal(recs$uf, c(35L, 33L))
  expect_equal(recs$month, c(1L, 2L))
})

test_that("standardise_sinan_tb tolerates an absent TEST_MOLEC column", {
  raw <- data.table(TRATAMENTO = "1", ID_MN_RESI = "355030",
                    ID_MUNICIP = "355030", DT_DIAG = "20050615",
                    SITUA_ENCE = "1")                          # pre-GeneXpert
  recs <- standardise_sinan_tb(raw)
  expect_true(all(is.na(recs$test_molec)))
  expect_equal(recs$year, 2005L)
})

test_that("summarise_notifications counts new + relapse by state-month", {
  recs <- data.table(
    entry_type = c("1", "2", "3", "5", "1"),
    uf         = c(35L, 35L, 35L, 35L, 33L),
    year       = rep(2018L, 5),
    month      = rep(3L, 5),
    situa_ence = NA_character_, test_molec = NA_character_
  )
  out <- summarise_notifications(recs, keep_entry = KEEP)
  expect_equal(out[uf == 35L, notifications], 2L)   # two new (re-entry/transfer dropped)
  expect_equal(out[uf == 33L, notifications], 1L)
  expect_error(summarise_notifications(recs), "keep_entry")
})

test_that("treatment_outcomes computes death and abandonment fractions", {
  recs <- data.table(
    entry_type = rep("1", 4),
    uf = rep(35L, 4), year = rep(2018L, 4), month = rep(3L, 4),
    situa_ence = c("1", "3", "2", "4"),   # cure, TB death, abandon, other death
    test_molec = NA_character_
  )
  out <- treatment_outcomes(recs, keep_entry = KEEP)
  expect_equal(out$n_closed, 4L)
  expect_equal(out$pri_mort_t, 0.5)   # death(3) + other-death(4) = 2/4
  expect_equal(out$pri_aban_t, 0.25)  # abandon(2) = 1/4
})

test_that("genexpert_share is the performed-test share among notified", {
  recs <- data.table(
    entry_type = rep("1", 4),
    uf = rep(35L, 4), year = rep(2018L, 4), month = rep(3L, 4),
    situa_ence = NA_character_,
    test_molec = c("1", "3", "5", NA)   # performed(1,3); not-performed(5); missing
  )
  out <- genexpert_share(recs, keep_entry = KEEP)
  expect_equal(out$n_notif, 4L)
  expect_equal(out$n_genexpert, 2L)
  expect_equal(out$genexpert_share, 0.5)
  expect_true(out$genexpert_share >= 0 && out$genexpert_share <= 1)
})
