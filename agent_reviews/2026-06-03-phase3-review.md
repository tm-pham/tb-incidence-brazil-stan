# Phase 3 review — config, environment, simulator

Date: 2026-06-03
Reviewers run (all five, in parallel via /review): data_integrity,
stan_model_review, epidemiology_review, testing, reproducibility.
Suite: 13 tests pass (`Rscript code/07_tests/testthat.R`).

## Verdict

Entry: **Needs work** (High findings from stan_model_review and reproducibility).
After fixes below: the actionable High/Medium items are resolved or converted to
documented, PI-facing decisions. The two remaining High items (H1/H2 below) are
load-bearing identification decisions that depend on the Chitwood supplement,
which is not present in this container; they are deferred to Phase 4 with the
simulator built so no refactor is needed when they are settled.

## Findings and resolutions

### stan_model_review
- **H1 `rho` is a fixed scalar** (spec wants logit-linear in poorly-defined-cause
  fraction). DEFERRED to Phase 4: recorded as open decision 1 in
  `literature/notes/priors.md`; `simulate_tb_counts()` accepts area-varying
  `pi`/`rho` so adding the regression needs no refactor. Needs supplement + PI.
- **H2 `pi*rho` confounded / `pi=0.9`, `rho=0.85` uncited.** DEFERRED similarly;
  open decision 2; documented as provisional in priors.md and the simulator.
- **M1 `priors.md` missing.** FIXED: created `literature/notes/priors.md`.
- M2 (cfr_treated data-vs-prior boundary), L1 (sum-to-zero convention), L2
  (small RW SD): noted for Phase 4 Stan model / recovery harness.

### reproducibility
- **H1 `GLOBAL_SEED` defined but unused.** PARTIALLY FIXED: `testthat.R` now sets
  the launch seed from `GLOBAL_SEED`; `config.R` documents that orchestration
  scripts and `_targets.R` (Phase 4-5) pass it to the simulator and the
  cmdstanr fit. Full wiring lands with those scripts.
- **M2 `config.R` mutates options.** FIXED: `options(mc.cores)`/`setDTthreads()`
  moved to `.Rprofile`; `config.R` is now pure constants.
- **M1 `renv.lock` placeholder.** DOCUMENTED: README note + `setup_renv.R` header.
- **L1 `.Rprofile` relative paths.** FIXED: bootstrapping comment added.
- M3 (cmdstan version recording), L2 (test seeds): Phase 4 / acceptable.

### testing (suite passes)
- **H1 defaults not pinned numerically.** FIXED: new test pins `mu, delta, pi,
  rho, p_death_tx, p_ltfu` and the derived CFRs to documented values.
- **H2 tautological CFR assertions.** FIXED by the same numeric pins.
- M (RNG isolation for `simulate_tb_dataset`, input-validation tests, integer
  type via `is.integer`, expect_true labels), L (hardcoded death_mean anchor):
  FIXED.
- Gated recovery test: Phase 4 deliverable (Stan model still a stub).

### epidemiology_review (no Critical/High)
- Estimand kept distinct, person-time correct, CFR structure correct.
- Medium-1 (prior provenance): addressed via priors.md. Medium-2 (data-vs-prior
  boundary for `p_death_tx`/`p_ltfu`): documented in `tb_natural_history()`.
- Forward guidance recorded: SIM deaths must be the only death count (no
  double counting with SINAN deaths-on-treatment); reconcile in Phase 4.

### data_integrity (no Critical/High; pipeline not yet built)
- **M population time-invariant within area.** FIXED: `simulate_tb_dataset()`
  now grows population per area-year (`pop_growth_sd`), with a test.
- **M grid completeness/uniqueness untested.** FIXED: assertion added.
- L (population units doc): FIXED in roxygen.
- ICD-10 / SINAN-exclusion / join checks: apply once
  `code/02_data_processing/` exists.

## Carried to Phase 4
Gated recovery test; cmdstan version recording in `fit_models.R`; resolve H1/H2
(`rho` regression + `pi`/`rho` anchoring) against the supplement with PI sign-off;
Stan sum-to-zero convention to match the simulator's demeaning; SIM-only death
count to avoid double counting.
