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
    # death_adj here is the COMPLETENESS multiplier (fraction of true TB deaths
    # captured by SIM): exp_deaths = pop * alldeaths * death_adj. This is the 2025
    # convention. Note Chitwood 2021 parameterises rho as the MISSED fraction with
    # (1 - rho) in the likelihood, so OUR theta_idc has the OPPOSITE SIGN of 2021's
    # idc coefficient: ours is NEGATIVE (more ill-defined-cause deaths => lower
    # completeness).
    #
    # theta_idc is LOAD-BEARING: it is what identifies detection vs death-reporting
    # (a flat/symmetric prior leaves the two confounded along a ridge -- recovery
    # then sign-flips death_adj; see agent_reviews/2026-06-07). It is anchored to
    # the Chitwood 2021 two-point expert anchors for rho (the missed fraction):
    # idc=0.01 -> 0.105, idc=0.15 -> 0.255 (Table S1; literature/notes/priors.md).
    # Mapping to OUR completeness convention (death_adj = 1 - rho) and solving the
    # two-point logit line gives slope theta_idc ~ -7.6 and intercept ~ 2.2; we
    # re-centre theta0 so completeness ~ 0.75 (the 2025 Beta(150,50) baseline) at a
    # typical idc ~ 0.12: theta0 = qlogis(0.75) + 7.6*0.12 ~ 2.0. The level
    # difference vs the raw 2021 (1 - rho) ~ 0.8 is the external SIM coverage
    # (p_cov < 1) folded into theta0 (we have no separate coverage series; open
    # decision 4 in priors.md). [LOAD-BEARING; PI to confirm the anchor magnitude.]
    death_adj = list(
      theta0      = c(mean = 2.0,  sd = 0.20),  # completeness ~0.75 at typical idc~0.12 (2025 baseline + idc offset)
      theta_time  = c(mean = 0, sd = 0.05),     # per-year drift ~ Normal(0,0.05) (Chitwood 2021)
      theta_idc   = c(mean = -7.6, sd = 2.0),   # IDC slope, informative & NEGATIVE (Chitwood 2021 anchors, completeness convention)
      static_2025 = c(a = 150, b = 50)          # reference: 2025 static Beta(150,50)
    ),

    # --- Latent-series regression priors (Chitwood 2025 Table S2) ---
    inc_intercept = c(mean = 0, sd = 10),   # alpha_lambda ~ Normal(0,10)
    inc_coef      = c(mean = 0, sd = 10),   # incidence trend/COVID coefs
    det_intercept = c(mean = 0, sd = 1),    # alpha_delta ~ Normal(0,1)
    det_coef      = c(mean = 0, sd = 1),    # detection trend/COVID coefs

    # --- Smoothness / extension priors (no 2025 precedent; our choice) ---
    # Incidence trend stays flexible (notifications identify it). The DETECTION
    # trend is tightened (trend_sd_det) so its smooth component cannot absorb the
    # secular death-reporting drift -- a second leak into the detection/
    # death-reporting confound (stan review H1, agent_reviews/2026-06-07). The
    # detection rise is meant to be carried by the GeneXpert covariate, not a free
    # smooth trend.
    trend_sd       = c(mean = 0, sd = 1),    # half-Normal on the incidence spline coefs
    trend_sd_det   = c(mean = 0, sd = 0.15), # half-Normal on the detection spline coefs (tight)
    season_sd      = c(mean = 0, sd = 1),    # half-Normal on seasonal coefs
    genexpert_coef = c(mean = 0, sd = 1)     # half-Normal (coef constrained >0 in Stan): Xpert improves detection
  )
}

#' Beta mean from a c(a, b) hyperparameter vector.
beta_mean <- function(ab) unname(ab[["a"]] / (ab[["a"]] + ab[["b"]]))
