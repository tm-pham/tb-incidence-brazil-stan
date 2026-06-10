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

Then fit one state as a sanity check, and all 27 for production:

```r
# one state (Sao Paulo), local:
Rscript code/03_modeling/01_fit_one_state.R              # TB_FIT_UF=35 by default
# all 27 states, sequential (compile once), writes outputs/estimates/convergence_summary.csv:
Rscript code/03_modeling/02_fit_all_states.R
```

On CHPC, prefer the SLURM array (one state per task): submit the compile step
first so the 27 tasks reuse one binary, then the array with a dependency:

```bash
cid=$(sbatch --parsable --wrap "Rscript code/03_modeling/00_precompile_model.R")
sbatch --dependency=afterok:$cid code/00_chpc_scripts/fit_all_states.slurm
```

### Sampler config and convergence (decided 2026-06-10)

Production uses the **diagonal** metric: 4000 warmup + 2000 sampling, adapt_delta
0.95, max_treedepth 12, 4 chains. The dense metric was tested and **rejected** (it
wrecked mixing: R-hat 1.08, ESS 35). The incidence<->detection level / death-channel
ridge is intrinsic to the data (notifications pin only the product; the split rests
on sparse deaths + priors), so no metric removes it -- diag_e gives valid draws at
the cost of treedepth saturation (an efficiency, not a validity, issue). See
`agent_reviews/2026-06-10-convergence-decision-ship-diag_e.md`.

Convergence is judged on the **estimands**: `fit_base_model()` reports
`max_rhat_estimand` / `min_ess_bulk_estimand` (over `incidence_rate` / `detection`)
and `02_fit_all_states.R` flags a state WARN if estimand R-hat > 1.01 or estimand
bulk ESS < 400. Slow nuisance level / death-channel scalars and 100% treedepth are
expected. A state whose ESTIMANDS warn needs the deferred model-level reparam of
the ridge, not a sampler tweak. Reparameterise rather than only raising
`adapt_delta`; record the cmdstan version (done by `fit_base_model()`), pin it + `renv`.
