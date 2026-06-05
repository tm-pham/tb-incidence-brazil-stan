# Review: Phase A (state-month data layer) — five reviewers

Date: 2026-06-05. Reviewers run in parallel: data_integrity, epidemiology_review,
reproducibility, testing, stan_model_review. Fast suite: PASS (no model fit yet,
so no divergence/R-hat to report).

## Verdict

**Needs work** by the rubric (High/Critical from epidemiology, reproducibility,
and stan). In context, the findings fall into four buckets: (a) genuine Phase-A
code defects — fixed this pass; (b) PI-confirmation gates — logged in priors.md;
(c) environment pinning — needs the PI's machine; (d) Phase B/C scope — the
modeling is not built yet, which the stan/testing Criticals describe.

The data layer's structure is sound: estimands kept distinct from observations,
population is an offset not a covariate, covariates left NA not imputed, SINAN
inclusion + ICD-10 death filter correct, SIM gaps now detectable.

## Findings and resolutions

### Critical (data_integrity) — FIXED
- DI-C1 `prepare_stan_data` did not fail on a wrong-size grid. Added
  `expect_n_states`/`expect_n_months` guards; `_targets.R` passes 27 / 252.
- DI-C2 `check_panel` trend used `mean()` without `na.rm`, silently suppressing
  the IDC/GeneXpert trajectory flags on any NA covariate. Added `na.rm`, explicit
  NA-cell flags, and death/notification-weighted national trend (also DI-M2).

### High — FIXED (code)
- REPRO-H1 `load_sim_records` mutated `options(timeout)` without restoring.
  Wrapped with `on.exit`.
- DI-M3 corrupted SIM dates (NA year/month) silently dropped. `standardise_sim`
  now drops and counts them (`n_bad_date`).
- TEST-H2/H3 + coverage: added tests for COVID level/slope, the unattributable +
  bad-date drops, the treatment join, deaths integer type, the NA all-cause
  branch, the flat-GeneXpert flag, the fallback heuristic, config constants, and
  the `stan_data_for_state` error path.

### High — LOGGED for PI (priors.md open decisions; not code defects)
- EPI-H1 / DI-M1 GeneXpert numerator = "performed" (1-4) vs "detected" (1-2).
- EPI-H2 / DI-H2 / DI-H3 treatment-outcome code sets (death 3,4; abandon 2,10 —
  confirm code 10 in the dictionary) and cohort dating (DT_DIAG vs closure).
- DI-H1 population: confirm SIDRA 6579 is back-revised to the 2000/2010 censuses,
  or add those anchors; pull the 2023 estimate so the final year is not held flat.

### High — DEFERRED (needs the PI's machine)
- REPRO-H2 `renv.lock` has an empty Packages block; cmdstan version unrecorded.
  Run `renv::snapshot()` on the populated library and commit; record cmdstan
  version with the fit. **This is the main open reproducibility gap.**

### Reproducibility — FIXED (code)
- REPRO-M1/M2 `UF_ABBREV` and the SIDRA IDs are now defaulted parameters, not
  bare global references.

### Phase B/C scope (stan_model_review, testing) — addressed by building B/C
- STAN-C1/C3 legacy `simulate.R` (forbidden annual/joint-hierarchical process)
  and `tb_incidence_hierarchical.stan` (BYM2) must be retired/rewritten.
- STAN-C2/H1/H2, TEST-C1/C2 no base Stan model, empty `priors.R`/`fit_models.R`,
  no recovery test. These define the Phase B/C work now in progress.

### Medium/Low — partially addressed / noted
- check_panel weighted trend (DI-M2) fixed. Remaining Lows (uf range vs canonical
  set DI-L3; `method="constant"` wide-window DI-L1; env-var cue/boundary docs
  REPRO-L1/L2; `write_panel_report` side-effect doc REPRO-L3; date-parser
  malformed-input tests) tracked, lower priority.

## Shortlist still open before Phase A is fully closed
1. PI confirmations: GeneXpert numerator; treatment-outcome codes + cohort date;
   IDC code set; population census backbone / 2023 estimate.
2. renv snapshot + cmdstan version pin (PI's machine).
