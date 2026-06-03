# Phase 4 (data processing) review

Date: 2026-06-03
Reviewers run (all five, in parallel via /review): data_integrity,
stan_model_review, epidemiology_review, testing, reproducibility.
Scope: the new `code/02_data_processing/` module on branch
`claude/jolly-ramanujan-9aw8U` (prepare_stan_data, load_sim, load_notifications,
load_population, geo_utils, run_data_processing) plus its tests.
Tests: PASS before and after fixes (`Rscript code/07_tests/testthat.R`):
simulate 57, prepare-stan-data 31, load-sim 12, load-notifications 12,
load-population 10, geo-utils 9. No sampler yet, so no R-hat/ESS.

## Entry verdict: Needs work
High findings from epidemiology and reproducibility, plus two environment- or
phase-blocked Criticals.

## Findings and resolutions

### Critical
- **repro C1 - renv.lock empty / unpinned.** NOT resolvable in the web container
  (CRAN + Stan-universe network-blocked). Documented in README + setup_renv.R.
  Must run `setup_renv.R` on a networked machine and commit the lockfile. Carried.
- **data_integrity C1 - committed HEAD used `TPENTRADA`.** Stale: the working
  tree already had the correct `TRATAMENTO`. RESOLVED by committing.
- **testing C1 - no recovery test.** Phase 4 modelling deliverable (Stan base
  model still a stub). Carried.

### High - resolved
- **epidemiology H1 - silent residence->occurrence fallback.** FIXED:
  `coalesce_muni_code()` now attaches `n_fallback`/`n_total`; the loaders expose
  `n_residence_fallback`; the orchestration report logs it. Tested.
- **data_integrity H1 - tidy_population silently dropped NA population.** FIXED:
  now a loud error (every municipality-year needs a denominator). Test updated.
- **data_integrity H2 - contributory-cause fields not searched.** DOCUMENTED:
  underlying-cause-only scope stated in `filter_tb_deaths` docstring and
  priors.md, flagged for PI re-confirmation. (Logic unchanged: PI chose A15-A19.)
- **reproducibility H1 - data vintage not recorded.** FIXED: report now records
  fetch timestamp, R version, microdatasus/sidrar versions, and SIDRA table/var.
- **reproducibility H2 - load-bearing constants as globals in function files.**
  FIXED: `TB_DEATH_ICD3` and `SINAN_ENTRY_KEEP_CODES` moved to `config.R`; pure
  functions no longer depend on global state (filter_tb_deaths has a literal
  default; summarise_notifications requires keep_entry explicitly).
- **data_integrity H3 - treatment-outcome prior-year separation.** DOCUMENTED in
  run_data_processing.R and priors.md (separate fetch, never into the counts).

### Medium - resolved / documented
- stan M2 + testing 7 - X covariate alignment only implicit. FIXED: assertion
  that the covariate ordering is identical to the count ordering; value-alignment
  test added.
- data_integrity M4 - no post-join row-count check. FIXED:
  `stopifnot(nrow(dt) == nrow(pop))`.
- data_integrity M1 - test code legend mislabelled; post-mortem untested. FIXED.
- data_integrity M2 - no post-2022-census caveat. FIXED: warning in
  load_ibge_population for years > 2021.
- data_integrity M3 - stale TPENTRADA docstring. FIXED.
- reproducibility M2 - env-var defaults undocumented. FIXED: moved to config.R
  (YEAR_START_DEFAULT etc.).
- reproducibility M3 - silent overwrite. FIXED: message on overwrite.
- testing 4/5/6/9 - empty-result, covariate-by-year, duplicate-sum, overflow
  tests. FIXED (added).
- testing 2/3 - coalesce_muni_code direct tests + sentinel. FIXED (test-geo-utils.R).
- epidemiology M1 - relapse-vs-re-entry justification. DOCUMENTED in priors.md.
- stan M1 - simulator output not directly consumable by prepare_stan_data
  (recovery seam). CARRIED to the recovery-test task (Phase 4 modelling): the
  test will adapt simulator output (pseudo-codes + covariate table) or bypass
  assembly; documented as the seam to watch.
- epidemiology M2 - state->municipality pi/rho transfer. OPEN, blocking gate for
  real fits (priors.md). Carried.
- epidemiology M3 - notification year basis (DT_DIAG) not finally fixed; NA-date
  screening. Partially documented; confirm with PI. Carried.
- reproducibility M1 - geo_utils sourced 3x. Accepted (idempotent); noted.

### Low - resolved / noted
- testing 9 (.is_count overflow), 10 (attr==0 happy path) - FIXED.
- stan Low1 (log person-years note), Low2 (empty-universe guard) - FIXED.
- reproducibility L1 (code nchar note), L2 (sessionInfo in report) - partially
  addressed (vintage block added). priors.R test infra (testing 8) - Phase 4.

## Carried to Phase 4 modelling
renv.lock population (networked machine); gated recovery test + the
simulator->prepare_stan_data adapter seam; cmdstan version recording in
fit_models.R; resolve pi/rho municipality transfer and the rho regression with
the supplement + PI sign-off; finalise notification year basis; PI
re-confirmation of underlying-cause-only TB deaths.

## Post-fix status
All actionable High/Medium findings resolved or explicitly documented and
carried. Remaining Criticals are environment-blocked (renv) or Phase-4
deliverables (recovery test). Tests pass. The data-processing transforms are
ready to run on the Mac.
