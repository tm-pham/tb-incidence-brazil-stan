# forward.R
# Deterministic R mirror of the Stan model's `transformed parameters` block
# (tb_state_month.stan), computed from a Stan data list and a parameter list.
# This exists so the simulator <-> Stan agreement can be checked WITHOUT a Stan
# toolchain: for the same parameters and design, tb_forward() on the Stan data
# must reproduce simulate_state_month()'s expected counts to numerical precision.
# Keep this in lockstep with both tb_state_month.stan and simulate.R.

source(here::here("code", "01_functions", "delays.R"))

#' Forward model: expected counts and latent estimands from Stan data + params.
#'
#' @param sd A Stan data list from `build_stan_model_data()`.
#' @param p A list of NATURAL parameters (the Stan transformed parameters):
#'   inc_intercept, beta_trend_inc, beta_season_inc, covid_inc_level,
#'   covid_inc_slope, det_intercept, beta_trend_det, beta_season_det,
#'   covid_det_level, covid_det_slope, genexpert_coef, theta0, theta_time,
#'   theta_idc, p_mort_aban, p_mort_nonotif. (Names match simulate.R's params.)
#' @return list(exp_notif, exp_deaths, incidence_rate, detection, death_adj).
tb_forward <- function(sd, p) {
  N_total <- sd$N_pre + sd$N_obs
  obs <- (sd$N_pre + 1L):N_total

  lambda <- exp(p$inc_intercept +
                  as.numeric(sd$B_trend %*% p$beta_trend_inc) +
                  as.numeric(sd$S_season %*% p$beta_season_inc) +
                  p$covid_inc_level * sd$covid_level +
                  p$covid_inc_slope * sd$covid_slope)
  gamma <- causal_convolve(lambda, sd$phi_lambda)

  delta <- stats::plogis(p$det_intercept +
                           as.numeric(sd$B_trend %*% p$beta_trend_det) +
                           as.numeric(sd$S_season %*% p$beta_season_det) +
                           p$covid_det_level * sd$covid_level +
                           p$covid_det_slope * sd$covid_slope +
                           p$genexpert_coef * sd$genexpert_ext)

  detect <- causal_convolve(gamma, sd$phi_gamma)
  notified <- delta * detect
  missed <- (1 - delta) * detect
  dead_notif <- notified * (sd$pri_mort_ext + sd$pri_aban_ext * p$p_mort_aban)
  alldeaths <- causal_convolve(dead_notif, sd$phi_mort) +
    causal_convolve(missed * p$p_mort_nonotif, sd$phi_mort)

  death_adj <- stats::plogis(p$theta0 + p$theta_time * sd$year_idx +
                               p$theta_idc * sd$idc)
  list(
    exp_notif = sd$population * notified[obs],
    exp_deaths = sd$population * alldeaths[obs] * death_adj,
    incidence_rate = gamma[obs], detection = delta[obs], death_adj = death_adj
  )
}
