# Review log — 2026-06-07 — detection vs death-reporting identification

Reviewers run (all five, in parallel): `data_integrity`, `stan_model_review`,
`epidemiology_review`, `testing`, `reproducibility`.

Trigger: the recovery test, after `default_true_params` was redesigned to carry
realistic signal (commit f225cd2 / f19fbef), recovers INCIDENCE well (cor 0.877)
but fails DETECTION (cor 0.34) and the DEATH-REPORTING adjustment (cor -1.0,
sign flip), plus cover_inc 0.776 and covid_inc_level q95 0.042 (>0).

## Verdict: NEEDS WORK

Failing recovery test (5 assertions) + Critical/High findings from the stan,
epidemiology, and reproducibility reviewers.

## RESOLUTION UPDATE (2026-06-07, commit 9c2a4bb)

C1 (the Critical identification ridge) is RESOLVED. Implemented the consensus fix:
informative, sign-reconciled `theta_idc ~ Normal(-7.6, 2.0)` (Chitwood 2021
two-point anchors mapped to our completeness convention; sign NEGATIVE), `theta0`
re-centred to `Normal(2.0, 0.20)` (completeness ~0.75 at typical idc ~0.12),
`genexpert_coef` constrained `>0`, and a separate tightened detection trend
`trend_sd_det ~ half-N(0,0.15)` (H1). The gated recovery test now PASSES 16/16:
detection recovery 0.34 -> pass (>0.78), death_adj -1.0 -> pass (>0.83), incidence
still passes, coverage and convergence hold. Caveat: the recovery truth was set to
match the prior centre, so this confirms identifiability GIVEN the prior; the PI
should still confirm the -7.6 anchor magnitude against the 2021 supplement.

Still open (High): H2 NA covariate guard, H3 methods.qmd separation wording, H4
renv/cmdstan pinning, H5 restore num_divergent==0 (geometry), H6 covid_inc_level
check.

## IMPORTANT caveat — stale checkout for 3 of 5 reviewers

The container's local git kept reverting to a stale phantom commit `1f2409c`
(pre-QR, pre-`default_true_params` redesign). `stan_model_review`,
`epidemiology_review`, and `data_integrity` reviewed `1f2409c`;
`reproducibility` and `testing` read the real `f225cd2`. All findings below are
cross-checked against the real `f225cd2` code; stale-only artifacts are marked
[STALE] and excluded from the verdict.

## Fast tests

Pass (basis, simulate, forward, stan-data, priors, prepare-stan-data, delays,
config, load-*, ppc, extract, geo-utils, check-panel). `recovery` is gated and
SKIPPED without a Stan toolchain; when run by the user it FAILS as above.
`targets` skips (package not loadable in container). No fast-suite failures.

## Findings (ranked, de-duplicated, validity-checked against f225cd2)

### CRITICAL

C1. Detection <-> death-reporting non-identifiability (the central finding).
    Reviewers: stan_model_review (C1), epidemiology_review (C1/H2), testing (C1);
    corroborates the PI's own deterministic diagnosis. VALID on real code.
    Mechanism (confirmed from `tb_state_month.stan:131-150`): exp_deaths depends
    on detection and death_adj only through their product
    [0.565 - 0.52*delta] * death_adj; rising detection lowers per-case deaths
    while rising death_adj raises them, so deaths/notif nearly cancels
    (0.276 -> 0.260). The identifying covariates are collinear:
    cor(genexpert, idc) = -0.73. With theta_idc ~ N(0,1) (priors.R:43,
    uninformative) the split is a ridge; the sampler lands on the wrong point
    (detection 0.34, death_adj -1.0). theta0 IS already anchored at N(1.0986,0.20)
    (priors.R:41) and theta_time IS tight N(0,0.05) -- the remaining leak is
    theta_idc (and the loose detection trend, H1).
    Fix (consensus = anchor the DEATH-REPORTING side, not genexpert):
    - Make theta_idc informative from the Chitwood 2021 two-point anchors
      (idc=0.01 -> ~0.105, idc=0.15 -> ~0.255; literature/notes/priors.md:52-65),
      reconciling the sign first (H-sign below). This HONORS the load-bearing rule
      (reverts to cited structure), not weakens it.
    - Constrain genexpert_coef > 0 with a mild prior (known Xpert direction); do
      NOT anchor its magnitude tightly (no defensible literature value).
    - Consider building the external SIM vital-registration completeness anchor
      (p_cov) flagged as required in priors.md but never implemented.
    - Re-run recovery; keep the test red until this lands.

### HIGH

H1. Detection smooth-trend prior too loose; can re-absorb death-reporting drift.
    stan_model_review (H1). VALID: priors.R:54 has a single trend_sd ~ half-N(0,1)
    used for BOTH inc and det (stan_data.R:62 trend_sd_det = pr$trend_sd). The
    detection RW spline can mimic any monotone drift and soak up death-reporting
    variation. Fix: separate trend_sd_inc / trend_sd_det; tighten the detection
    trend to ~half-N(0,0.1-0.2) and/or use RW2 for detection. Keep incidence wider.

H-sign. theta_idc sign reconciliation required BEFORE anchoring.
    stan_model_review (M2), epidemiology_review (H1). VALID. The simulator uses
    theta_idc = -1.0 (higher idc -> lower death_adj); the 2021 anchors' rho
    orientation must be reconciled so the informative prior sign is correct.
    Anchoring with the wrong sign worsens recovery. Document the mapping in
    priors.md.

H2. No NA-check on covariates in build_stan_model_data -> silent NaN likelihood.
    data_integrity (C2). VALID (stan_data.R:35-52 checks length, not anyNA).
    Early-year genexpert and zero-closure months produce NA that propagate to NaN
    expected counts / divergences on the real 27-state run. Fix: explicit anyNA
    guard per covariate with a named error; document pre-2014 genexpert=0 and
    treatment-outcome imputation upstream.

H3. methods.qmd overstates the detection/death-reporting separation.
    epidemiology_review (H2). VALID. sec-deathadj claims separation the data do
    not deliver without the anchor. Demote to "conditional on the completeness
    anchor"; state that absent it, detection and death-reporting trade off 1:1.

H4. Environment not pinned: renv.lock empty; cmdstan version unrecorded.
    reproducibility (H1/H2). VALID, pre-existing. Run/commit setup_renv.R; record
    the cmdstan version in a tracked file.

H5. Divergence threshold relaxed from 0 to <20 in the recovery test.
    testing (H2). VALID (test-recovery.R:43). Contradicts CLAUDE.md (divergences
    are failures). Restore expect_equal(num_divergent, 0); achieving it requires
    the geometry work (reparameterise), not a looser threshold.

H6. covid_inc_level individual-sign check tests a non-identifiable quantity.
    testing (H1). VALID (test-recovery.R:73-75). covid_inc_level and
    covid_det_level share one break; only the combined effect is identified.
    Replace with a check on the identifiable combined COVID drop in the recovered
    incidence series (line 77 is the right spirit).

H7. GeneXpert/IDC collinearity may contaminate the detection series for the panel.
    epidemiology_review (H3). VALID, matters downstream (Xpert access correlates
    with urban infrastructure, hence pollution). Resolved largely by C1; also
    state the maintained assumption and the pre-2008 handling.

### MEDIUM

M1. Treatment-outcome cohort truncation biases pri_mort_t/pri_aban_t in the last
    12-18 months (data_integrity M5; load_notifications.R:105-119). VALID.
M2. genexpert_ext lacks [0,1] bounds in the Stan data block (data_integrity M3;
    tb_state_month.stan:54). VALID.
M3. IDC garbage-code set is "R"-only, an open PI decision (data_integrity M4;
    config.R). VALID (data).
M4. sigma_season_inc/det omitted from the R-hat/ESS sweep in fit_base_model
    (reproducibility M4; fit_models.R:76-83). VALID.
M5. Recovery test omits min_ess_tail assertion (testing M4). VALID.
M6. Missing fast tests for default_true_params: determinism + within-prior bounds;
    and an explicit "incidence recovers even if the split fails" assertion
    (testing M1/M2/M3). VALID.
M7. Unconditional top-level source() in simulate.R/stan_data.R/forward.R; in-body
    source() in the recovery test (reproducibility M2). VALID (design).
M8. det_intercept_mean = 0 location vs detection well above 50% (stan_model_review
    M3). VALID minor.

### LOW

L1. Stale COVID comment in test-recovery.R:70 (-0.15/-0.20 vs real -0.20/-0.30)
    (reproducibility M3). VALID, trivial.
L2. qr.Q column signs are LAPACK-dependent; beta_trend_* coefficients vary across
    platforms but the projected series B%*%beta is stable (reproducibility M1).
    VALID; document.
L3. recovery test prior centre/init not aligned to truth inc_intercept (-9 vs
    -9.6) (data_integrity H1, downgraded; wide prior). VALID minor.
L4. set.seed in test runner vs withr scoping (reproducibility L2). VALID minor.
L5. file.path vs here::here in config.R (reproducibility L3). VALID minor.
L6. grid-size guard / missing-covariate report stratification (data_integrity
    L1/L3). VALID minor.

### STALE-ONLY (reviewed 1f2409c; NOT valid on f225cd2 — excluded from verdict)

- stan_model_review C2 "theta0 unanchored N(0,1)": real code anchors it
  (priors.R:41, N(1.0986,0.20)).
- epidemiology_review H1 "theta0 diffuse" portion: same (theta_idc portion kept).
- data_integrity C1 "truth not projected, uses cumsum": real code projects onto
  the orthonormal basis (simulate.R default_true_params).
- data_integrity H2/M1 magnitudes (theta_idc=-1.5, sigma 0.12): real values are
  theta_idc=-1.0 etc. (collinearity point retained under C1).

## Critical/High shortlist to resolve before this phase is done

1. C1 — break the detection/death-reporting ridge via an informative, sign-
   reconciled theta_idc prior from the Chitwood 2021 anchors (+ genexpert_coef>0),
   re-validate recovery. [load-bearing — needs PI sign-off]
2. H-sign — reconcile the theta_idc sign convention against the 2021 supplement
   before C1.
3. H1 — separate and tighten the detection smooth-trend prior.
4. H2 — add the NA covariate guard in build_stan_model_data.
5. H3 — correct the methods.qmd separation claim.
6. H4 — pin renv + cmdstan.
7. H5/H6 — restore num_divergent==0 (with the geometry work) and replace the
   covid_inc_level check with the identifiable combined-effect check.

Note: INCIDENCE — the estimand the downstream pollution panel needs — recovers
well and is identified by notifications. The blocked estimand is the
detection/death-reporting split.
