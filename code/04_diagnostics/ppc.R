# ppc.R
# Prior- and posterior-predictive checks for the monthly state model. The model
# emits sinan_rep / sim_rep in generated quantities; fitting with prior_only = 1
# gives a prior predictive, prior_only = 0 a posterior predictive. The coverage
# math is a pure function (testable without Stan); predictive_check() is the thin
# fit wrapper.

#' Predictive coverage of observed counts by a replicate matrix.
#'
#' @param rep_matrix Numeric matrix, draws x N (one column per observed month).
#' @param observed Integer/numeric vector length N.
#' @param prob Central interval mass (default 0.90).
#' @return list(coverage, mean_bayes_p, interval) where coverage is the fraction
#'   of months whose observed value lies in the central `prob` predictive
#'   interval, mean_bayes_p is the mean posterior-predictive p-value
#'   (Pr(rep >= obs)); a value near 0 or 1 flags systematic misfit.
ppc_coverage <- function(rep_matrix, observed, prob = 0.90) {
  if (ncol(rep_matrix) != length(observed)) {
    stop("ppc_coverage: rep_matrix has ", ncol(rep_matrix),
         " columns but observed has length ", length(observed), ".")
  }
  a <- (1 - prob) / 2
  lo <- apply(rep_matrix, 2L, stats::quantile, probs = a)
  hi <- apply(rep_matrix, 2L, stats::quantile, probs = 1 - a)
  bayes_p <- vapply(seq_along(observed),
                    function(j) mean(rep_matrix[, j] >= observed[j]), numeric(1))
  list(
    coverage = mean(observed >= lo & observed <= hi),
    mean_bayes_p = mean(bayes_p),
    interval = data.frame(lo = lo, hi = hi, observed = observed, bayes_p = bayes_p)
  )
}

#' Prior/posterior predictive check from a fit.
#'
#' @param fit A CmdStanFit (with sinan_rep / sim_rep in generated quantities).
#' @param observed_sinan,observed_sim Observed count vectors.
#' @param prob Central interval mass.
#' @return list(sinan = <ppc_coverage>, sim = <ppc_coverage>).
predictive_check <- function(fit, observed_sinan, observed_sim, prob = 0.90) {
  if (!requireNamespace("posterior", quietly = TRUE)) {
    stop("predictive_check: package 'posterior' is required.")
  }
  rep_mat <- function(var) {
    d <- posterior::as_draws_matrix(fit$draws(var))
    matrix(as.numeric(d), nrow = nrow(d))
  }
  list(
    sinan = ppc_coverage(rep_mat("sinan_rep"), observed_sinan, prob),
    sim   = ppc_coverage(rep_mat("sim_rep"), observed_sim, prob)
  )
}
