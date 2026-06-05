# check_panel.R
# Side-effect-free diagnostics on the assembled state-month panel. Splits HARD
# invariants (always true; asserted) from SOFT plausibility checks (data-
# dependent; surfaced as WARN flags + a report for human review, since they
# cannot be unit-tested on synthetic data). Wired as a pipeline target so the
# checks run automatically on every assembly instead of by hand.

#' Diagnostics on an assembled panel.
#'
#' @param assembled Output of `prepare_stan_data()` (`$panel`, `$n_months`).
#' @param genexpert_era_year Year Xpert scaled up nationally (default 2014).
#' @param big_state_min_rate Mean monthly TB deaths above which a state should
#'   essentially never have a zero-death month; a zero there flags a possible SIM
#'   gap (this is what would have caught the RN-2010 drop).
#' @return A list of summary values, a by-year covariate `trend` table, a
#'   `per_state` table, `zero_death_by_state`, and `flags` (WARN messages).
panel_diagnostics <- function(assembled, genexpert_era_year = 2014L,
                              big_state_min_rate = 5) {
  p <- assembled$panel
  n_states <- data.table::uniqueN(p$uf)
  n_months <- assembled$n_months
  flags <- character()
  add <- function(cond, msg) if (isTRUE(cond)) flags <<- c(flags, msg)

  # --- HARD invariants (a failure here is a bug, not a data quirk) ----------
  stopifnot(nrow(p) == n_states * n_months)
  stopifnot(all(p[, .N, by = uf]$N == n_months))
  stopifnot(all(p$notifications >= 0L), all(p$deaths >= 0L))
  stopifnot(all(p$population > 0))

  # --- Covariate ranges in [0,1] -------------------------------------------
  for (cv in c("idc", "genexpert_share", "pri_mort_t", "pri_aban_t")) {
    if (cv %in% names(p)) {
      v <- p[[cv]][!is.na(p[[cv]])]
      if (length(v)) add(min(v) < 0 || max(v) > 1,
        sprintf("covariate %s outside [0,1] (range %.3f..%.3f)", cv, min(v), max(v)))
    }
  }

  # --- SIM-gap detection ----------------------------------------------------
  # DEFINITIVE when all-cause deaths are available: every state-month has
  # hundreds of all-cause deaths, so an absent/zero all-cause cell is a download
  # gap, whereas zero TB deaths with all-cause present is a real low-count zero
  # (small state, early year, poor registration) and is NOT flagged. Falls back
  # to a TB-only heuristic when all-cause is not carried (e.g. synthetic panels).
  zero_tb_months <- p[deaths == 0, .N]
  if ("allcause_deaths" %in% names(p)) {
    gaps <- p[is.na(allcause_deaths) | allcause_deaths == 0]
    add(nrow(gaps) > 0, sprintf(
      "%d state-month(s) with ZERO all-cause SIM deaths (download gap, refetch): %s",
      nrow(gaps), paste0(gaps$uf, "/", gaps$year, "-", gaps$month, collapse = ", ")))
    # also flag if all-cause looks implausibly thin (possible partial truncation)
    thin <- p[!is.na(allcause_deaths) & allcause_deaths > 0 & allcause_deaths < 10]
    add(nrow(thin) > 0, sprintf(
      "%d state-month(s) with <10 all-cause SIM deaths (possible partial gap): %s",
      nrow(thin), paste0(thin$uf, "/", thin$year, "-", thin$month, collapse = ", ")))
  } else {
    dy <- p[, .(deaths = sum(deaths)), by = .(uf, year)]
    zsy <- dy[deaths == 0]
    add(nrow(zsy) > 0, sprintf(
      "%d state-year(s) with ZERO total TB deaths (no all-cause check available): %s",
      nrow(zsy), paste0(zsy$uf, "/", zsy$year, collapse = ", ")))
    st <- p[, .(tot = sum(deaths), zero_months = sum(deaths == 0)), by = uf]
    susp <- st[tot >= big_state_min_rate * n_months & zero_months > 0]
    add(nrow(susp) > 0, sprintf(
      "state(s) averaging >=%g deaths/month yet with zero-death month(s): %s",
      big_state_min_rate, paste0(susp$uf, "(", susp$zero_months, "mo)", collapse = ", ")))
  }

  # --- Covariate trajectories (the load-bearing time-varying signal) -------
  # Report NA covariate cells loudly (NA would otherwise silently null out the
  # trend means and suppress these flags). Aggregate the national trend with the
  # right weights: death-weighted IDC (small high-IDC states must not dominate)
  # and notification-weighted GeneXpert share. Death-weighted IDC uses
  # idc * allcause_deaths / sum(allcause_deaths) when all-cause is carried.
  n_idc_na <- sum(is.na(p$idc))
  n_gx_na  <- sum(is.na(p$genexpert_share))
  add(n_idc_na > 0, sprintf("%d idc NA cell(s) in the panel (check SIM coverage)", n_idc_na))
  add(n_gx_na > 0, sprintf("%d genexpert_share NA cell(s) (expected only where a state-month has no notifications)", n_gx_na))
  has_ac <- "allcause_deaths" %in% names(p)
  trend <- p[, {
    idc_w <- if (has_ac) sum(idc * allcause_deaths, na.rm = TRUE) /
                         sum(allcause_deaths, na.rm = TRUE)
             else mean(idc, na.rm = TRUE)
    list(idc = idc_w,
         genexpert = stats::weighted.mean(genexpert_share,
                                          w = pmax(notifications, 1L), na.rm = TRUE),
         notif = sum(notifications), deaths = sum(deaths))
  }, by = year][order(year)]
  idc_first <- trend[year == min(year), idc]
  idc_last  <- trend[year == max(year), idc]
  add(!(idc_last < idc_first), sprintf(
    "IDC fraction did not fall over the window (%.3f -> %.3f); death registration was expected to improve",
    idc_first, idc_last))
  gx_pre  <- trend[year < genexpert_era_year, if (.N) max(genexpert) else 0]
  gx_last <- trend[year == max(year), genexpert]
  add(gx_pre > 0.05, sprintf(
    "GeneXpert share >5%% before %d (%.3f); national rollout was ~2014",
    genexpert_era_year, gx_pre))
  add(!(gx_last > gx_pre), "GeneXpert share did not rise after the rollout era")

  list(
    n_states = n_states, n_months = n_months, n_cells = nrow(p),
    total_notifications = sum(p$notifications),
    total_deaths = sum(p$deaths),
    zero_death_months = zero_tb_months,
    trend = trend,
    per_state = p[, .(months = .N, notif = sum(notifications),
                      deaths = sum(deaths)), by = uf][order(uf)],
    zero_death_by_state = p[deaths == 0, .N, by = uf][order(-N)],
    flags = flags
  )
}

#' Render diagnostics to a human-readable report; warn on each flag.
#'
#' @param diag Output of `panel_diagnostics()`.
#' @param path Output file path.
#' @param warn If TRUE, emit an R warning per flag (so a CI/pipeline run surfaces
#'   them) in addition to writing them to the report.
#' @return `path` (invisibly).
write_panel_report <- function(diag, path, warn = TRUE) {
  lines <- c(
    "== TB state-month panel diagnostics ==",
    sprintf("generated:   %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("grid:        %d states x %d months = %d cells",
            diag$n_states, diag$n_months, diag$n_cells),
    sprintf("notifications: %d", diag$total_notifications),
    sprintf("TB deaths:     %d", diag$total_deaths),
    sprintf("zero-death state-months: %d", diag$zero_death_months),
    "",
    "-- covariate trend by year (idc should fall; genexpert ~0 pre-2014 then rise) --",
    paste(utils::capture.output(print(diag$trend)), collapse = "\n"),
    "",
    "-- flags --",
    if (length(diag$flags)) paste0("WARN: ", diag$flags) else "none"
  )
  writeLines(lines, path)
  if (warn) for (f in diag$flags) warning("panel_diagnostics: ", f, call. = FALSE)
  invisible(path)
}
