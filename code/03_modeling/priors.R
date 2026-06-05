# priors.R
# Single source of the load-bearing priors and fixed constants for the monthly
# state-level TB model (Chitwood 2025 base + project extensions). The simulator
# (code/01_functions/) and the Stan data prep both read from here; the Stan model
# receives the numeric hyperparameters as data. Every value is documented in
# literature/notes/priors.md with its citation. Do NOT weaken the load-bearing
# natural-history priors silently (see CLAUDE.md).

#' The prior/constant table.
#'
#' Distributions are given as named numeric vectors of hyperparameters: Beta as
#' c(a, b); Normal/half-Normal as c(mean, sd).
#' @return A named list.
priors <- function() {
  list(
    # --- Fixed delay kernels (Chitwood 2025 Table S2; maxima from the prose) ---
    # NOT estimated: the convolution kernels are fixed.
    delays = list(
      lambda_shape = 1.75, lambda_scale = 25, lambda_max = 60L, # Weibull infection->symptom (mean 22.25 mo)
      gamma_shape  = 10,   gamma_rate   = 4,  gamma_max  = 7L,  # Gamma symptom->detectable (mean 2.5 mo)
      mort_shape   = 12,   mort_rate    = 3,  mort_max   = 10L  # Gamma detectable->death (mean 4 mo)
    ),

    # --- Case fatality (load-bearing; held CONSTANT over time per our
    # convention -- 2025 split these pre/post, we deliberately do not). ---
    p_mort_nonotif = c(a = 113, b = 87),  # Beta, death|undiagnosed ~0.565 (Chitwood 2021/2025)
    p_mort_aban    = c(a = 10,  b = 190), # Beta, death|LTFU ~0.05 (2025; Table S2 SD 0.15 is a typo for 0.015)

    # --- Death-reporting adjustment: TIME-VARYING logit-linear in IDC (our
    # extension of the 2025 static Beta(150,50), using the Chitwood 2021
    # structure). On the logit scale; theta_time is per YEAR. ---
    death_adj = list(
      theta0      = c(mean = 0, sd = 1),     # intercept ~ Normal(0,1)
      theta_time  = c(mean = 0, sd = 0.05),  # per-year trend ~ Normal(0,0.05) (Chitwood 2021)
      theta_idc   = c(mean = 0, sd = 1),     # IDC coefficient ~ Normal(0,1)
      static_2025 = c(a = 150, b = 50)       # reference only: 2025 static Beta(150,50)
    ),

    # --- Latent-series regression priors (Chitwood 2025 Table S2) ---
    inc_intercept = c(mean = 0, sd = 10),   # alpha_lambda ~ Normal(0,10)
    inc_coef      = c(mean = 0, sd = 10),   # incidence trend/COVID coefs
    det_intercept = c(mean = 0, sd = 1),    # alpha_delta ~ Normal(0,1)
    det_coef      = c(mean = 0, sd = 1),    # detection trend/COVID coefs

    # --- Smoothness / extension priors (no 2025 precedent; our choice) ---
    trend_sd       = c(mean = 0, sd = 1),   # half-Normal on the spline-coef RW penalty
    season_sd      = c(mean = 0, sd = 1),   # half-Normal on seasonal coefs
    genexpert_coef = c(mean = 0, sd = 1)    # GeneXpert detection covariate coef
  )
}

#' Beta mean from a c(a, b) hyperparameter vector.
beta_mean <- function(ab) unname(ab[["a"]] / (ab[["a"]] + ab[["b"]]))
