# Pin the load-bearing config constants that define the estimand, so a silent
# edit (e.g. adding B90 to the TB-death set, or re-entry to the SINAN keep-set)
# fails loudly. (data_integrity / testing review L-3.)

source(here::here("code", "00_config", "config.R"))

test_that("estimand-defining constants are pinned", {
  expect_identical(TB_DEATH_ICD3, c("A15", "A16", "A17", "A18", "A19"))
  expect_identical(SINAN_ENTRY_KEEP_CODES, c("1", "2"))
  expect_identical(SINAN_GENEXPERT_PERFORMED, c("1", "2", "3", "4"))
  expect_identical(IDC_ICD_PREFIX, "R")
  expect_equal(length(UF_CODES), 27L)
  expect_true(all(UF_CODES >= 11L & UF_CODES <= 53L))
  expect_equal(length(UF_ABBREV), 27L)
  expect_identical(UF_ABBREV[["24"]], "RN")
  expect_equal(COVID_BREAK_YEAR, 2020L)
  expect_equal(COVID_BREAK_MONTH, 4L)
  expect_equal(c(YEAR_START_DEFAULT, YEAR_END_DEFAULT), c(2003L, 2023L))
  expect_true(is.numeric(GLOBAL_SEED) && length(GLOBAL_SEED) == 1L)
})
