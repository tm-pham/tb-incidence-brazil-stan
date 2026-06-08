# plot_seasonality.R
# Render the calendar-month seasonal profile from seasonal_profile(). One line per
# era so drift over the 21-year window is visible at a glance: parallel lines = a
# stable seasonal shape (the fixed Fourier block is adequate); diverging lines or
# a shifting peak = the seasonality is changing (motivates time-varying season).
# Pure builder: returns a ggplot; the runner script saves it.

#' Plot month-of-year seasonal index by era.
#'
#' @param profile The `profile` table from `seasonal_profile()`.
#' @param title,subtitle Plot labels.
#' @param ribbon If TRUE, draw the 5-95%-across-years band (omit when comparing
#'   several eras, where overlapping ribbons clutter).
#' @return A ggplot object.
plot_seasonal_profile <- function(profile, title = "Observed seasonal profile",
                                  subtitle = "Monthly rate / annual mean (1.0 = annual average); detrended within year",
                                  ribbon = TRUE) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plot_seasonal_profile: ggplot2 is required.")
  }
  pf <- data.table::copy(profile)
  pf[, month := factor(month, levels = 1:12,
                       labels = c("J","F","M","A","M","J","J","A","S","O","N","D"))]
  multi_era <- data.table::uniqueN(pf$era) > 1L
  g <- ggplot2::ggplot(pf, ggplot2::aes(x = month, y = index_mean,
                                        group = era, colour = era))
  if (ribbon && !multi_era) {
    g <- g + ggplot2::geom_ribbon(
      ggplot2::aes(ymin = index_lo, ymax = index_hi, fill = era),
      alpha = 0.15, colour = NA)
  }
  g +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50") +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 1.6) +
    ggplot2::labs(title = title, subtitle = subtitle,
                  x = "Calendar month", y = "Seasonal index",
                  colour = "Era", fill = "Era") +
    ggplot2::theme_minimal()
}
