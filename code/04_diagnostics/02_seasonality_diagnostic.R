#!/usr/bin/env Rscript
# 02_seasonality_diagnostic.R -- is the seasonality in the DATA, and does it drift?
# Data-side check (no model fit): profiles the observed notification and death
# rates by calendar month, detrended within year, split into eras so we can see
# whether the seasonal shape is stable over 2003-2023. Use this to decide whether
# the fixed Fourier seasonal block is justified and whether to make it
# time-varying. Run the data pipeline first (targets::tar_make()).
#
# Configure via environment variables:
#   TB_DIAG_UF     state code (default 35 = Sao Paulo); "all" pools every state.
#   TB_DIAG_ERAS   comma-separated cut years (default "2009,2016" -> three ~7-year
#                  eras). Set to "none" for a single pooled profile.
#
# Run:  Rscript code/04_diagnostics/02_seasonality_diagnostic.R

suppressMessages({library(here); library(data.table)})
source(here("code", "00_config", "config.R"))
source(here("code", "04_diagnostics", "seasonality.R"))

uf_env  <- Sys.getenv("TB_DIAG_UF", "35")
target_uf <- if (identical(tolower(uf_env), "all")) NULL else as.integer(uf_env)
eras_env <- Sys.getenv("TB_DIAG_ERAS", "2009,2016")
era_breaks <- if (identical(tolower(eras_env), "none")) NULL else
  as.integer(strsplit(eras_env, ",")[[1]])

assembled <- tryCatch(
  targets::tar_read(assembled),
  error = function(e) readRDS(file.path(OUT_STAN_DATA, "tb_state_month_panel.rds")))
panel <- assembled$panel
if (!is.null(target_uf) && !target_uf %in% assembled$states) {
  stop("uf ", target_uf, " is not in the assembled panel.")
}
label <- if (is.null(target_uf)) "Brazil (all states pooled)" else
  sprintf("%s (uf %d)", UF_ABBREV[[as.character(target_uf)]], target_uf)

dir.create(OUT_FIGURES, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_ESTIMATES, recursive = TRUE, showWarnings = FALSE)
have_ggplot <- requireNamespace("ggplot2", quietly = TRUE)
if (have_ggplot) source(here("code", "06_visualization", "plot_seasonality.R"))

for (value in c("notifications", "deaths")) {
  sp <- seasonal_profile(panel, value = value, uf = target_uf, era_breaks = era_breaks)
  cat("\n== ", value, " seasonality:", label, "==\n", sep = "")
  cat("Seasonal index = monthly rate / that year's mean (1.00 = annual average).\n")
  cat("amplitude = peak-minus-trough (fraction of annual mean); ",
      "seasonal_strength = share of within-year variance that is the stable ",
      "monthly pattern (0..1).\n", sep = "")
  print(sp$amplitude)

  tag <- if (is.null(target_uf)) "all" else as.character(target_uf)
  saveRDS(sp, file.path(OUT_ESTIMATES, sprintf("seasonality_%s_%s.rds", value, tag)))
  if (have_ggplot) {
    g <- plot_seasonal_profile(
      sp$profile,
      title = sprintf("Observed %s seasonality: %s", value, label),
      ribbon = is.null(era_breaks))
    fig <- file.path(OUT_FIGURES, sprintf("seasonality_%s_%s.png", value, tag))
    ggplot2::ggsave(fig, g, width = 9, height = 5.5, dpi = 150)
    cat("figure ->", fig, "\n")
  }
}
cat("\nReading it: a flat line near 1.0 with low strength => little seasonality.\n",
    "Eras tracking together => stable seasonality (fixed Fourier block is fine).\n",
    "Eras diverging / peak month shifting => time-varying seasonality is warranted.\n", sep = "")
