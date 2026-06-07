#!/usr/bin/env Rscript
# 01_fit_one_state.R -- fit tb_state_month.stan for ONE state, locally.
# A sanity check before the full 27-state cluster run. Needs cmdstan and the
# assembled panel: run the data pipeline first (`targets::tar_make()`, which
# builds `assembled` / outputs/stan_data/tb_state_month_panel.rds).
#
# Configure via environment variables (or edit the defaults):
#   TB_FIT_UF    state code (default 35 = Sao Paulo: high-burden and
#                well-identified, a good first test). Others: 33 RJ, 29 BA, 43 RS.
#   TB_FIT_FAST  set to "1" for a quicker look (1500 warmup) instead of the full
#                4000; use only to check it runs, not for final estimates.
#   TB_FIT_CHAINS  chains (default 4); lower to 2 to ease a laptop.
#
# Run:  Rscript code/03_modeling/01_fit_one_state.R
#  or:  source(here::here("code", "03_modeling", "01_fit_one_state.R"))

suppressMessages({library(here); library(data.table)})
source(here("code", "00_config", "config.R"))
source(here("code", "03_modeling", "stan_data.R"))
source(here("code", "03_modeling", "fit_models.R"))
source(here("code", "05_analysis", "extract_estimates.R"))

target_uf  <- as.integer(Sys.getenv("TB_FIT_UF", "35"))
fast       <- nzchar(Sys.getenv("TB_FIT_FAST"))
n_chains   <- as.integer(Sys.getenv("TB_FIT_CHAINS", "4"))
# Sampler effort. Defaults: full = 4000 warmup, FAST = 1500. Override directly
# with TB_FIT_WARMUP / TB_FIT_SAMPLING / TB_FIT_ADAPT_DELTA to run longer or
# tighten the sampler (e.g. TB_FIT_WARMUP=6000 TB_FIT_ADAPT_DELTA=0.995).
warmup     <- as.integer(Sys.getenv("TB_FIT_WARMUP", if (fast) "1500" else "4000"))
sampling   <- as.integer(Sys.getenv("TB_FIT_SAMPLING", "1000"))
adapt      <- as.numeric(Sys.getenv("TB_FIT_ADAPT_DELTA", "0.99"))
treedepth  <- as.integer(Sys.getenv("TB_FIT_TREEDEPTH", "12"))

# Load the assembled panel (prefer the targets store; fall back to the rds).
assembled <- tryCatch(
  targets::tar_read(assembled),
  error = function(e) readRDS(file.path(OUT_STAN_DATA, "tb_state_month_panel.rds")))
if (!target_uf %in% assembled$states) {
  stop("uf ", target_uf, " is not in the assembled panel (states: ",
       paste(assembled$states, collapse = ", "), ").")
}

message("Fitting uf ", target_uf, " (", UF_ABBREV[[as.character(target_uf)]], "); ",
        warmup, " warmup + ", sampling, " sampling, ", n_chains,
        " chains, adapt_delta ", adapt,
        ". One ~250-month series; expect tens of minutes to a few hours.")

sd <- stan_data_from_panel(assembled, target_uf, start_month_of_year = 1L)
res <- fit_base_model(
  sd, seed = GLOBAL_SEED + target_uf, chains = n_chains, parallel_chains = n_chains,
  iter_warmup = warmup, iter_sampling = sampling, adapt_delta = adapt,
  max_treedepth = treedepth, refresh = 200L)

cat("\n== convergence diagnostics ==\n"); str(res$diagnostics)
cat("cmdstan version:", res$cmdstan_version, "\n")
if (res$diagnostics$max_rhat >= 1.01 || res$diagnostics$num_divergent > 0) {
  message("NOTE: R-hat >= 1.01 or divergences present -- inspect before trusting; ",
          "consider raising adapt_delta / warmup.")
}

# Save the fit and the tidy state x month estimates.
dir.create(OUT_MODEL_FITS, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_ESTIMATES, recursive = TRUE, showWarnings = FALSE)
res$fit$save_object(file.path(OUT_MODEL_FITS, sprintf("fit_uf_%d.rds", target_uf)))
ps <- assembled$panel[uf == target_uf]
data.table::setorder(ps, year, month)
est <- tidy_state_estimates(res, target_uf, ps$year, ps$month)
saveRDS(est, file.path(OUT_ESTIMATES, sprintf("estimates_uf_%d.rds", target_uf)))
cat("\nestimates ->", file.path(OUT_ESTIMATES, sprintf("estimates_uf_%d.rds", target_uf)), "\n")

# Figure: estimated incidence (with CI) vs observed notification rate.
if (requireNamespace("ggplot2", quietly = TRUE)) {
  source(here("code", "06_visualization", "plot_estimates.R"))
  pd <- prepare_incidence_plot_data(est, ps, annualize = TRUE)
  g <- plot_state_incidence(pd, states = target_uf)
  dir.create(OUT_FIGURES, recursive = TRUE, showWarnings = FALSE)
  fig <- file.path(OUT_FIGURES, sprintf("incidence_uf_%d.png", target_uf))
  ggplot2::ggsave(fig, g, width = 10, height = 6, dpi = 150)
  cat("figure    ->", fig, "\n")
}
