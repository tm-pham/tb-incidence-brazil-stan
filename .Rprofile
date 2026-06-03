# .Rprofile: sourced at R startup from the project root.
# Activate renv (once initialised), then source the project config so the path
# constants, global seed, and intended core count are available in every
# session. Applying the parallelism side effect lives here, not in config.R,
# which is a pure constants file.
#
# Note: paths here are bare relative paths, not here::here(). This is
# intentional and unavoidable: .Rprofile runs before renv has activated and
# before `here` is guaranteed on the search path. R is launched from the
# project root (the .Rproj and git root anchor this), so the relative paths
# resolve. Do not "fix" these into here::here() calls.

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
    # Apply the parallelism side effect here (config.R stays side-effect free).
    if (exists("MC_CORES")) {
      options(mc.cores = MC_CORES)
      data.table::setDTthreads(MC_CORES)
    }
  }
})
