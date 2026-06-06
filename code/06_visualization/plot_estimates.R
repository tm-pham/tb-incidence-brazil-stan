# plot_estimates.R
# Figures for the per-state estimates. The headline plot overlays, for each
# state, the estimated TB incidence rate (posterior median + credible-interval
# ribbon) and the observed notification rate, so the gap between them reads as
# under-detection. prepare_incidence_plot_data() is pure (data.table only) and
# tested; plot_state_incidence() needs ggplot2.

#' Assemble the data for the incidence-vs-notification figure.
#'
#' Joins the tidy per-state estimates (incidence rate, per-capita monthly, with a
#' 5-95% interval) to the observed notifications and population, and expresses
#' both incidence and the notification rate on a common scale.
#'
#' @param estimates data.table from tidy_state_estimates(): uf, year, month,
#'   incidence_rate, incidence_lo, incidence_hi (per-capita per month).
#' @param panel The assembled panel (prepare_stan_data()$panel): uf, year, month,
#'   notifications, population.
#' @param per Rate denominator (default 100000).
#' @param annualize If TRUE, multiply monthly rates by 12 (per-100k-per-year
#'   equivalent); else per-100k per month.
#' @param uf_abbrev Named map of UF code -> abbreviation for facet labels.
#' @return data.table(uf, uf_label, date, incidence, incidence_lo, incidence_hi,
#'   notification_rate) with a `rate_label` attribute.
prepare_incidence_plot_data <- function(estimates, panel, per = 1e5,
                                        annualize = FALSE, uf_abbrev = UF_ABBREV,
                                        uf_names = UF_NAMES) {
  estimates <- data.table::as.data.table(estimates)
  panel <- data.table::as.data.table(panel)
  for (col in c("incidence_rate", "incidence_lo", "incidence_hi")) {
    if (!col %in% names(estimates)) stop("prepare_incidence_plot_data: estimates missing `", col, "`.")
  }
  obs <- panel[, .(uf, year, month, notifications, population)]
  d <- merge(estimates[, .(uf, year, month, incidence_rate, incidence_lo, incidence_hi)],
             obs, by = c("uf", "year", "month"), all.x = TRUE)
  if (anyNA(d$population)) {
    stop("prepare_incidence_plot_data: ", sum(is.na(d$population)),
         " estimate cell(s) have no matching panel population.")
  }
  mult <- per * (if (annualize) 12 else 1)
  d[, `:=`(
    date = as.Date(sprintf("%04d-%02d-01", year, month)),
    uf_label = unname(uf_abbrev[as.character(uf)]),
    uf_name = unname(uf_names[as.character(uf)]),
    incidence = incidence_rate * mult,
    incidence_lo = incidence_lo * mult,
    incidence_hi = incidence_hi * mult,
    notification_rate = notifications / population * mult
  )]
  data.table::setorder(d, uf, date)
  out <- d[, .(uf, uf_label, uf_name, date, incidence, incidence_lo, incidence_hi,
               notification_rate)]
  data.table::setattr(out, "rate_label",
                      sprintf("TB cases per %s per %s", format(per, big.mark = ","),
                              if (annualize) "year" else "month"))
  out[]
}

#' Faceted incidence-vs-notification time-series figure (one panel per state).
#'
#' @param plot_data Output of prepare_incidence_plot_data().
#' @param states Optional vector of UF codes to restrict to.
#' @param ncol Facet columns (default lets ggplot choose).
#' @param free_y Per-state y-axis (states differ hugely in magnitude); default TRUE.
#' @param facet_by "name" for the full state name (default) or "abbrev".
#' @param ci_pct Credible-interval mass shown, for the subtitle (default 95).
#' @return A ggplot object.
plot_state_incidence <- function(plot_data, states = NULL, ncol = NULL,
                                 free_y = TRUE, facet_by = c("name", "abbrev"),
                                 ci_pct = 95) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plot_state_incidence: ggplot2 is required.")
  }
  facet_by <- match.arg(facet_by)
  facet_var <- if (facet_by == "name") "uf_name" else "uf_label"
  pd <- data.table::as.data.table(plot_data)
  if (!is.null(states)) pd <- pd[uf %in% states]
  rate_label <- attr(plot_data, "rate_label") %||% "rate"
  cols <- c("Estimated incidence" = "#2c7fb8", "Notification rate" = "#d95f02")
  ggplot2::ggplot(pd, ggplot2::aes(x = date)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = incidence_lo, ymax = incidence_hi,
                                      fill = "Estimated incidence"), alpha = 0.20) +
    ggplot2::geom_line(ggplot2::aes(y = incidence, colour = "Estimated incidence"),
                       linewidth = 0.5) +
    ggplot2::geom_line(ggplot2::aes(y = notification_rate, colour = "Notification rate"),
                       linewidth = 0.5) +
    ggplot2::facet_wrap(ggplot2::vars(.data[[facet_var]]),
                        scales = if (free_y) "free_y" else "fixed", ncol = ncol) +
    ggplot2::scale_colour_manual(values = cols, name = NULL) +
    ggplot2::scale_fill_manual(values = cols, guide = "none") +
    ggplot2::labs(x = NULL, y = rate_label,
                  title = "Estimated TB incidence vs observed notification rate, by state",
                  subtitle = sprintf("Posterior median and %d%% credible interval; the gap reflects under-detection", ci_pct)) +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom",
                   panel.grid.minor = ggplot2::element_blank())
}

# Null-coalescing helper (base R has none).
`%||%` <- function(a, b) if (is.null(a)) b else a
