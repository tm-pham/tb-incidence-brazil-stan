# convergence_summary.R
# Side-effect-free collation of per-state fit diagnostics into a launch
# monitoring table. The production decision (ship diag_e) accepts treedepth
# saturation and a few divergences as an EFFICIENCY cost of the intrinsic
# incidence<->detection level ridge, so a state PASSES on ESTIMAND health
# (incidence_rate / detection R-hat and ESS), not on the slow nuisance scalars.
# Pure: the runner script does the fitting and the I/O.

#' One convergence-summary row for a fitted state.
#'
#' @param uf State code.
#' @param diagnostics The `diagnostics` list from `fit_base_model()` (must carry
#'   max_rhat_estimand / min_ess_bulk_estimand; see fit_models.R).
#' @param abbrev Optional postal abbreviation.
#' @param runtime_sec Optional wall-clock seconds for the fit.
#' @param rhat_max,ess_min Estimand pass thresholds (default 1.01 and 400).
#' @return A one-row data.table: uf, abbrev, status ("OK"/"WARN"), the estimand
#'   and overall convergence numbers, divergences, treedepth hits, runtime_min,
#'   and `notes` naming any tripped check.
convergence_row <- function(uf, diagnostics, abbrev = NA_character_,
                            runtime_sec = NA_real_,
                            rhat_max = 1.01, ess_min = 400) {
  d <- diagnostics
  for (f in c("max_rhat_estimand", "min_ess_bulk_estimand", "max_rhat",
              "min_ess_bulk", "min_ess_tail", "num_divergent", "num_max_treedepth")) {
    if (is.null(d[[f]])) stop("convergence_row: diagnostics missing `", f, "`.")
  }
  notes <- character()
  if (!is.finite(d$max_rhat_estimand) || d$max_rhat_estimand > rhat_max)
    notes <- c(notes, sprintf("estimand R-hat %.3f > %.2f", d$max_rhat_estimand, rhat_max))
  if (!is.finite(d$min_ess_bulk_estimand) || d$min_ess_bulk_estimand < ess_min)
    notes <- c(notes, sprintf("estimand ESS %.0f < %d", d$min_ess_bulk_estimand, ess_min))
  status <- if (length(notes)) "WARN" else "OK"

  data.table::data.table(
    uf = as.integer(uf),
    abbrev = as.character(abbrev),
    status = status,
    max_rhat_estimand = d$max_rhat_estimand,
    min_ess_bulk_estimand = d$min_ess_bulk_estimand,
    max_rhat = d$max_rhat,
    min_ess_bulk = d$min_ess_bulk,
    min_ess_tail = d$min_ess_tail,
    num_divergent = as.integer(d$num_divergent),
    num_max_treedepth = as.integer(d$num_max_treedepth),
    runtime_min = round(runtime_sec / 60, 1),
    notes = if (length(notes)) paste(notes, collapse = "; ") else ""
  )
}

#' Bind per-state rows and order states by status then code (WARN first).
#'
#' @param rows A list of `convergence_row()` outputs (or one data.table).
#' @return A single data.table, WARN states first so problems surface at the top.
collate_convergence <- function(rows) {
  dt <- if (data.table::is.data.table(rows)) rows else data.table::rbindlist(rows)
  data.table::setorder(dt, -status, uf)   # "WARN" sorts after "OK"; -status puts it first
  dt[]
}
