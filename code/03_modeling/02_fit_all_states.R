#!/usr/bin/env Rscript
# 02_fit_all_states.R -- production fit of tb_state_month.stan for ALL 27 states.
# Each state is an independent 252-month fit (CLAUDE.md: no joint hierarchy). Runs
# sequentially here (compile once, reuse); on the cluster prefer the SLURM array
# (code/00_chpc_scripts/fit_all_states.slurm), one state per task, which calls
# 01_fit_one_state.R. This script is the canonical home of the PRODUCTION sampler
# config and writes a per-state convergence summary for monitoring.
#
# PRODUCTION CONFIG (decided 2026-06-10): diagonal metric. The dense metric was
# tested and REJECTED (it wrecked mixing: R-hat 1.08, ESS 35). The
# incidence<->detection level ridge is intrinsic to the data, so diag_e gives
# valid draws (R-hat ~1.01 on the estimands) at the cost of treedepth saturation
# (an efficiency, not validity, issue). See agent_reviews/2026-06-10-*.
#
# Configure via environment variables:
#   TB_FIT_STATES   comma-separated UF codes (default: all 27). e.g. "35,33,29".
#   TB_FIT_WARMUP / TB_FIT_SAMPLING / TB_FIT_ADAPT_DELTA / TB_FIT_TREEDEPTH /
#   TB_FIT_CHAINS   override sampler effort (defaults below).
#
# Run:  Rscript code/03_modeling/02_fit_all_states.R

suppressMessages({library(here); library(data.table)})
source(here("code", "00_config", "config.R"))
source(here("code", "03_modeling", "stan_data.R"))
source(here("code", "03_modeling", "fit_models.R"))
source(here("code", "05_analysis", "extract_estimates.R"))
source(here("code", "04_diagnostics", "convergence_summary.R"))

# Production sampler defaults (env-overridable).
states  <- {
  s <- Sys.getenv("TB_FIT_STATES", "")
  if (nzchar(s)) as.integer(strsplit(s, ",")[[1]]) else UF_CODES
}
warmup   <- as.integer(Sys.getenv("TB_FIT_WARMUP", "4000"))
sampling <- as.integer(Sys.getenv("TB_FIT_SAMPLING", "2000"))  # 2x base to lift ESS off the ridge
adapt    <- as.numeric(Sys.getenv("TB_FIT_ADAPT_DELTA", "0.95"))
treedepth<- as.integer(Sys.getenv("TB_FIT_TREEDEPTH", "12"))
n_chains <- as.integer(Sys.getenv("TB_FIT_CHAINS", "4"))

bad <- setdiff(states, UF_CODES)
if (length(bad)) stop("Unknown UF code(s): ", paste(bad, collapse = ", "))

assembled <- tryCatch(
  targets::tar_read(assembled),
  error = function(e) readRDS(file.path(OUT_STAN_DATA, "tb_state_month_panel.rds")))
present <- intersect(states, assembled$states)
if (!length(present)) stop("None of the requested states are in the assembled panel.")

dir.create(OUT_MODEL_FITS, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_ESTIMATES, recursive = TRUE, showWarnings = FALSE)

message("Fitting ", length(present), " state(s): ", paste(present, collapse = ", "),
        "\n  metric diag_e, ", warmup, " warmup + ", sampling, " sampling, ",
        n_chains, " chains, adapt_delta ", adapt, ", max_treedepth ", treedepth,
        ".\n  Each is one ~250-month series; expect ~1-2 h per state.")

model <- compile_tb_model()            # compile once, reuse across states
rows <- vector("list", length(present))

for (i in seq_along(present)) {
  uf <- present[i]
  abb <- UF_ABBREV[[as.character(uf)]]
  message("\n[", i, "/", length(present), "] uf ", uf, " (", abb, ") ...")
  sd <- stan_data_from_panel(assembled, uf, start_month_of_year = 1L)
  t0 <- Sys.time()
  res <- fit_base_model(
    sd, seed = GLOBAL_SEED + uf, model = model,
    chains = n_chains, parallel_chains = n_chains,
    iter_warmup = warmup, iter_sampling = sampling,
    adapt_delta = adapt, max_treedepth = treedepth, refresh = 0L)
  dt_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  res$fit$save_object(file.path(OUT_MODEL_FITS, sprintf("fit_uf_%d.rds", uf)))
  ps <- assembled$panel[uf == ..uf]
  data.table::setorder(ps, year, month)
  est <- tidy_state_estimates(res, uf, ps$year, ps$month)
  saveRDS(est, file.path(OUT_ESTIMATES, sprintf("estimates_uf_%d.rds", uf)))

  rows[[i]] <- convergence_row(uf, res$diagnostics, abbrev = abb, runtime_sec = dt_sec)
  print(rows[[i]][, .(uf, abbrev, status, max_rhat_estimand,
                      min_ess_bulk_estimand, num_divergent, num_max_treedepth, runtime_min)])
  # Write the running summary after each state so a crash still leaves a record.
  data.table::fwrite(collate_convergence(data.table::rbindlist(rows[seq_len(i)])),
                     file.path(OUT_ESTIMATES, "convergence_summary.csv"))
}

summary_dt <- collate_convergence(data.table::rbindlist(rows))
cat("\n== convergence summary (WARN states first) ==\n")
print(summary_dt[, .(uf, abbrev, status, max_rhat_estimand,
                     min_ess_bulk_estimand, num_divergent, num_max_treedepth, notes)])
n_warn <- summary_dt[status == "WARN", .N]
cat("\n", summary_dt[, .N], " state(s) fitted; ", n_warn,
    " flagged WARN (inspect before trusting their estimands).\n", sep = "")
cat("summary -> ", file.path(OUT_ESTIMATES, "convergence_summary.csv"), "\n", sep = "")
