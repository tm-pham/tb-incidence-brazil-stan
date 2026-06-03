# testthat.R: entry point for the test suite.
# Runs the fast tests in code/07_tests/testthat/. The gated recovery test (which
# samples with cmdstanr) is tagged and skipped here unless RUN_RECOVERY_TEST is
# set; run it on demand. See code/07_tests/testthat/.

library(testthat)
library(data.table)

# Pin the RNG state at suite launch so the run is reproducible. GLOBAL_SEED is
# defined in config.R, sourced by .Rprofile at startup; fall back if a session
# was started without it. Individual tests set their own seeds explicitly.
if (exists("GLOBAL_SEED")) set.seed(GLOBAL_SEED) else set.seed(20240603L)

test_dir(
  here::here("code", "07_tests", "testthat"),
  reporter = "summary",
  stop_on_failure = TRUE
)
