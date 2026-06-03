# .Rprofile: sourced at R startup from the project root.
# Activate renv (once initialised), then source the project config so the path
# constants, global seed, and mc.cores are available in every session.

if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

# Source the project config when its dependencies are available. Guarded so a
# bare R session (e.g. during package installation) still starts cleanly.
local({
  cfg <- file.path("code", "00_config", "config.R")
  if (file.exists(cfg) &&
      requireNamespace("here", quietly = TRUE) &&
      requireNamespace("data.table", quietly = TRUE)) {
    source(cfg)
  }
})
