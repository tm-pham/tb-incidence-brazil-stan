# setup_renv.R
# One-time environment setup. Run on a machine with CRAN access (your Mac or the
# cluster); the web/CI container has CRAN blocked, so renv cannot initialise
# there. After running this, commit the regenerated renv.lock.
#
#   Rscript code/00_config/setup_renv.R
#
# This is a side-effecting script (it installs packages and writes renv.lock);
# that is why it lives here and not in code/01_functions/.

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")

renv::init(bare = TRUE)

pkgs <- c(
  "data.table",   # all data work (not dplyr)
  "here",         # relative paths
  "cmdstanr",     # Stan inference (not rstan)
  "posterior",    # posterior summaries / draws
  "targets",      # pipeline
  "testthat",     # tests
  "withr",        # scoped RNG state in the simulator
  "ggplot2",      # figures
  "geobr",        # municipality spatial data
  "microdatasus", # SIM mortality from DATASUS
  "sidrar"        # IBGE population from SIDRA
)

# cmdstanr is not on CRAN; install from the Stan R-universe.
options(repos = c(
  stan = "https://stan-dev.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))

renv::install(pkgs)

# Install CmdStan itself and record the version (see code/03_modeling/fit_models.R
# for where the version is logged alongside each fit).
cmdstanr::install_cmdstan()
cat("cmdstan version:", cmdstanr::cmdstan_version(), "\n")

renv::snapshot()
