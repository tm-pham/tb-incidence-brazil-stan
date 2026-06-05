# Modeling (Phase B/C)

The monthly, **per-state** TB incidence/detection model (Chitwood 2025 structure
+ project extensions). Fit one state at a time over 2003-2023 (252 months); no
joint hierarchy, no BYM2, no monthly AR-1 (see `CLAUDE.md`).

## The process (simulator and Stan share it)

On an extended axis (a pre-window so the convolutions are complete for observed
months):

```
lambda = exp(intercept + B-spline trend + seasonal harmonics + COVID)   # infections, per-capita
gamma  = conv(lambda, phi_lambda)                                       # symptomatic = incidence
delta  = invlogit(intercept + trend + seasonal + COVID + GeneXpert)     # detection probability
detect = conv(gamma, phi_gamma)
Notified = delta * detect ;  Missed = (1-delta) * detect
DeadNotif = Notified * (pri_mort_t + pri_aban_t * p_mort_aban)
AllDeaths = conv(DeadNotif, phi_mort) + conv(Missed * p_mort_nonotif, phi_mort)
DeathAdj  = invlogit(theta0 + theta_time*year + theta_idc*idc)          # time-varying (our extension)
SINAN ~ Poisson(pop * Notified) ;  SIM ~ Poisson(pop * AllDeaths * DeathAdj)
```

Fixed delay kernels (Chitwood 2025 Table S2): Weibull(1.75, 25) infection->symptom,
Gamma(10, 4) symptom->detectable, Gamma(12, 3) detectable->death.

## Files

- `priors.R` -- single source of the verified priors/constants (`priors()`).
- `../01_functions/delays.R` -- discretised delay kernels + `causal_convolve()`.
- `../01_functions/basis.R` -- shared trend/seasonal/COVID design matrices.
- `../01_functions/simulate.R` -- the generative simulator (Phase B).
- `stan/tb_state_month.stan` -- the Stan model (Phase C).
- `stan_data.R` -- `build_stan_model_data()` / `stan_data_from_panel()` bridge.
- `forward.R` -- R mirror of the Stan `transformed parameters`, tested to match
  the simulator exactly (simulator <-> Stan agreement without compiling Stan).
- `fit_models.R` -- `compile_tb_model()`, seeded per-state `fit_base_model()`.
- `../04_diagnostics/ppc.R` -- prior/posterior predictive checks.
- `../05_analysis/extract_estimates.R` -- tidy state x year-month estimates.

## Running (needs cmdstanr + a cmdstan toolchain)

The whole pipeline (data + per-state fits) is `targets::tar_make()`. To validate
the model first, run the recovery test (the model must recover known incidence
and detection from simulated data):

```r
RUN_RECOVERY_TEST=1 Rscript code/07_tests/testthat.R
```

Expect convergence on the 252-month series to be the hard part: reparameterise
(the spline is already non-centred) rather than only raising `adapt_delta`.
Record the cmdstan version (done by `fit_base_model()`), and pin it + `renv`.
