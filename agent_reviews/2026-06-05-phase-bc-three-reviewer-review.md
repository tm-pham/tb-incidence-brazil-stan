# Review: Phase B/C (monthly simulator + Stan model) — three reviewers

Date: 2026-06-05. Reviewers: stan_model_review, testing, reproducibility (the
modeling-relevant three; epidemiology/data_integrity covered the data layer
earlier). No Stan toolchain in the container, so the model was reviewed by reading
(stanc could not run) and the simulator<->Stan agreement was checked via the R
forward mirror (test-forward.R, agreement to 1e-9). Fast suite: PASS.

## Verdict

**Needs work** by the rubric (reproducibility Highs + the pre-existing renv
Critical). All code-level Highs were FIXED this pass; the remaining blockers need
the PI's machine (compile + recovery fit; renv snapshot).

## Findings and resolutions

### stan_model_review — no Critical/High. Mediums addressed:
- M3 detection prior could not be relocated -> added `det_intercept_mean` data
  input (default 0) to tb_state_month.stan + stan_data.R. FIXED.
- M2 overflow risk from exp() under the wide Normal(.,10) incidence prior -> the
  realistic convergence threat. Mitigated by seeded inits near -9; documented in
  the modeling README; added a 252-month forward finiteness test. The tighter
  working prior is left as a documented PI knob (not silently changed).
- M1 inc_intercept_mean is prior-centring only -> documented.
- Confirmed: Stan syntax sound for cmdstan >= 2.30; fidelity to the 2025 monthly
  structure; identification intact; forward mirror matches the .stan line-by-line.

### testing — Critical/High FIXED:
- C1 diagnostics computed over only 8 scalars -> fit_base_model now summarises
  R-hat/ESS over incidence_rate, detection, and all coefficients. FIXED.
- C2 recovery test made no COVID/seasonal/death-adjustment assertions -> added
  sign-recovery checks for covid_inc/det_level, theta_time, theta_idc,
  genexpert_coef, plus COVID-period correlation and direct estimand R-hat. FIXED.
- H1 tautological assertion -> replaced with a real offset/per-capita-rate check.
- H2 non-finite guard untested -> added a test. H3 stan_data_from_panel untested
  -> added an integration test (COVID break inferred from a real assembled panel).
  H4 tidy_state_estimates untested -> added a mock-fit test (schema + x1e5 scaling
  + dimension guard). All FIXED.
- Mediums: pinned inc_coef/det_coef/theta/genexpert priors; added a different-
  seeds test; documented the recovery ESS floor; tightened the ppc bound. FIXED.

### reproducibility — Highs FIXED; Critical deferred to the PI machine:
- C1 renv.lock empty -> DEFERRED (run setup_renv.R + commit on a machine with
  CRAN; this is the main open reproducibility gap, also from the Phase A review).
- H1 init_tb_model used unseeded rnorm -> fit_base_model now scopes the R RNG with
  withr::local_seed(seed) so per-chain inits are reproducible. FIXED.
- H2 GLOBAL_SEED was a hidden global -> added tar_target(global_seed, ...,
  cue=always); the fit uses global_seed + uf. FIXED.
- H3 cmdstan version not queryable -> state_estimate writes a per-state provenance
  file (cmdstan version, seed, R-hat/ESS/divergences) and attaches the version to
  the estimate. FIXED.
- M2 top-level source() chains -> guarded with if(!exists(...)). FIXED.
- L1 set.seed in tests -> withr::local_seed. FIXED.
- M1 fit files are side effects -> documented (tar_invalidate to regenerate); L2
  data/synthetic noted. Low priority.

## Shortlist still open (need the PI's machine)
1. Compile + run the gated recovery test (`RUN_RECOVERY_TEST=1`): the real check
   that the model samples and recovers truth (R-hat<1.01, ESS, coverage, COVID/
   death-adjustment sign recovery). Convergence on 252 months is expected to be
   the hard part (watch the exp() overflow / inc_intercept).
2. `renv::snapshot()` + pin the cmdstan version.
3. The Phase A PI-confirmation items (priors.md open decisions).
