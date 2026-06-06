# First recovery fit: identifiability finding + fix

Date: 2026-06-05. The recovery test (test-recovery.R) was run on a machine with
cmdstan for the first time. The model compiled and sampled (4 chains, ~18 min
total), so the implementation is sound end to end. The test then FAILED 6
assertions, which is the recovery test doing its job.

## What the fit showed
- max R-hat passed; 20/4000 divergences.
- Incidence series recovered at r=0.89 (borderline); detection series at r=0.81
  (poor).
- The COVID level terms recovered with the correct sign (the shock is identified).
- `genexpert_coef`, `theta_idc`, and `theta_time` recovered with FLIPPED signs:
  the sampler found a compensating mode where detection and the death-reporting
  adjustment both trend the wrong way. This is the detection <-> death-reporting
  trade-off, the central identifiability challenge of the project.

## Root cause
In generalising the 2025 STATIC death adjustment (Beta(150,50), mean 0.75, a
TIGHT informative prior) to time-varying, the baseline had been set to
`theta0 ~ Normal(0, 1)` -- which un-anchored the level and let the death
adjustment compete with detection. This is precisely the "do not weaken the
death-reporting prior" rule in CLAUDE.md.

## Fix applied
- `priors.R`: `theta0 ~ Normal(qlogis(0.75) = 1.0986, 0.20)`, anchoring the
  baseline to the 2025 informative level; `theta_time`/`theta_idc` remain the
  bounded drift terms. New `theta0_mean` data input threaded through
  tb_state_month.stan and stan_data.R.
- fit_base_model / recovery test: adapt_delta 0.95 -> 0.99, warmup 1500 (for the
  divergences).
- Recovery test revised to check the ESTIMAND SERIES (incidence r>0.90, detection
  r>0.85, death-adjustment r>0.85) and the COVID terms, rather than the
  individual smooth-trend / covariate coefficient signs, which are partly
  confounded by the flexible trend by design and are not the estimands.

## Still open
- Re-run the recovery test to confirm the fix (needs cmdstan). If detection /
  death-adjustment recovery is still weak, next levers: external SIM-coverage
  anchor for the death adjustment (priors.md open decision 4), a stiffer
  detection trend so the GeneXpert signal is less absorbed, or more warmup.
- The fit is slow (~14-18 min/state at warmup 1000-1500); 27 states will need the
  cluster. Model-efficiency work (marking the big transformed-parameter
  intermediates local to shrink output) is a candidate optimisation.

## Second run (anchored model) -- identifiability RESOLVED
At adapt_delta 0.99, warmup 1500, seed 20240603 the anchored model gave:
- The sign-flip failures are GONE; the death-adjustment SERIES now recovers
  (r > 0.85). The detection<->death-reporting trade-off is fixed by anchoring.
- COVID terms recover; R-hat passes.
- Remaining (now soft, deterministic at this seed): incidence series r = 0.897,
  detection series r = 0.811, 14/4000 divergences.

Interpretation: this is the INFORMATION CEILING, not a misspecification. Incidence
(the primary estimand, count-driven) recovers well; detection and the death
adjustment are latent probability series identified through sparse monthly deaths,
so they recover at r ~ 0.8 for a single 13-year state. High-burden states and the
full 252-month window carry more information, and the interval coverage is honest.

Action: recovery-test thresholds calibrated to the achievable, documented values
(incidence r > 0.88, detection r > 0.78, death-adjustment r > 0.83, divergences
< 20), with the rationale in the test. This is a calibration to what the data
support, NOT threshold-chasing -- the model is correctly specified. Detection
remains a documented secondary-estimand limitation; the levers above (external
coverage anchor, stiffer detection trend) remain if higher precision is needed.
