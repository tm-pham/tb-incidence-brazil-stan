# Validates that _targets.R defines a coherent pipeline. Skipped where targets
# is not installed (e.g. the web container); runs on a machine with the full
# environment. Does not execute the pipeline, only inspects the DAG.

test_that("_targets.R defines a valid pipeline manifest", {
  skip_if_not_installed("targets")
  script <- here::here("_targets.R")
  skip_if_not(file.exists(script))

  manifest <- targets::tar_manifest(script = script)
  expect_gt(nrow(manifest), 0)
  # The data-processing endpoints must be present and the assembly must depend
  # on all three raw sources.
  expect_true(all(c("raw_notifications", "raw_deaths", "raw_population",
                    "stan_data", "stan_data_file") %in% manifest$name))
  deps <- manifest$command[manifest$name == "stan_data"]
  expect_match(deps, "raw_notifications")
  expect_match(deps, "raw_deaths")
  expect_match(deps, "raw_population")
})
