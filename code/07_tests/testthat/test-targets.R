# Validates that _targets.R defines a coherent pipeline. Skipped where targets
# is not installed (e.g. the web container); runs on a machine with the full
# environment. Does not execute the pipeline, only inspects the DAG.

test_that("_targets.R defines a valid pipeline manifest", {
  skip_if_not_installed("targets")
  script <- here::here("_targets.R")
  skip_if_not(file.exists(script))

  manifest <- targets::tar_manifest(script = script)
  expect_gt(nrow(manifest), 0)
  # The state-month endpoints must be present and the assembly must depend on
  # the notification, TB-death, and population sources.
  expect_true(all(c("notifications", "tb_deaths", "idc", "genexpert",
                    "treatment", "population_monthly", "assembled",
                    "stan_panel_file", "panel_report_file") %in% manifest$name))
  deps <- manifest$command[manifest$name == "assembled"]
  expect_match(deps, "notifications")
  expect_match(deps, "tb_deaths")
  expect_match(deps, "population_monthly")
})
