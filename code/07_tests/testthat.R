# testthat.R: entry point for the test suite.
# Runs the fast tests in code/07_tests/testthat/. The gated recovery test (which
# samples with cmdstanr) is tagged and skipped here unless RUN_RECOVERY_TEST is
# set; run it on demand. See code/07_tests/testthat/.

library(testthat)
library(data.table)

test_dir(
  here::here("code", "07_tests", "testthat"),
  reporter = "summary",
  stop_on_failure = TRUE
)
