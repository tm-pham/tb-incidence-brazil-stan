# Reviewer design doc: epidemiology_review

Source of truth for the `epidemiology_review` subagent. Keep them in sync.

## Mandate

Verify that the analysis is epidemiologically sound: that the estimands (true
incidence and case-detection probability) are kept distinct from what is observed,
that state person-time is handled correctly across 2003-2023, that the
load-bearing priors are justified, that the death-reporting adjustment is
time-varying, that the GeneXpert detection covariate is handled correctly, that
there is no double counting between data sources, and that the assumptions linking
these estimates to the air-pollution panel are stated. Read only.

## What to check

1. **Estimands kept distinct from observations.** True incidence and the
   case-detection probability are the targets and are not directly observed.
   Notifications (SINAN) and deaths (SIM) are observations generated from
   incidence through the detection and mortality process. Flag any place where
   notifications are treated as incidence, or where "cases" conflates incident,
   notified, and detected cases.

2. **Person-time denominators.** IBGE state population must be used as person-time
   (`gamma`), an offset/denominator, not a covariate. Rates must be per
   person-time and aligned to state-month. Denominators span the 2000/2010/2022
   censuses; flag use of a single census, missing intercensal interpolation, or
   ignoring the 2022 revision. Flag population used as a regression covariate or
   denominators that do not match the count's state-month.

3. **Time-varying death-reporting adjustment (first-order).** The death channel
   identifies detection. Over 2003-2023 SIM coverage and the ill-defined-cause
   fraction improved substantially, so a STATIC death adjustment confounds
   improving death registration with falling incidence and rising detection -
   flag a static adjustment as Critical. Confirm it is time-varying (time trend +
   actual ill-defined-cause series), anchored to external SIM coverage where
   possible. Also confirm the load-bearing natural-history priors (survival
   without treatment `mu`, death-given-undiagnosed / death-given-LTFU) are
   justified against the 2025 supplement; any weakening is a change to the
   identification strategy.

4. **Double counting between SINAN deaths-on-treatment and SIM.** Deaths that
   occur on treatment appear in SINAN treatment outcomes and may also appear in
   SIM. Check that the death likelihood does not double count them, and that the
   treated-death term and the SIM death count are reconciled.

5. **GeneXpert detection covariate and the panel maintained assumption.**
   GeneXpert (rolled out ~2014) plausibly raised detection, not incidence, and is
   an identifying covariate that helps separate detection changes from
   death-registration drift and incidence trends. Confirm it sits on the detection
   sub-model only (no mortality-side term), and that the share-among-notified
   proxy is interpreted as a capacity proxy (its denominator is the modelled
   notified set). Confirm the maintained assumption is stated: the panel relabels
   the air-pollution effect as an incidence effect assuming pollution affects
   incidence, not within-state-month detection; GeneXpert access has
   municipality-level structure tied to urban infrastructure that can correlate
   with pollution. Flag missing statements of this assumption and missing
   early-period (pre-2008) robustness handling.

## Severity guidance

- **Critical/High**: estimand conflated with observations, population misused or
  wrong census handling, a STATIC death-reporting adjustment, a load-bearing prior
  weakened or unjustified, double counting of deaths across SINAN and SIM,
  GeneXpert placed on the mortality side.
- **Medium/Low**: missing caveat/maintained-assumption text where the analysis is
  otherwise correct, unclear but defensible prior or covariate choices.

Any Critical/High finding from this reviewer means the phase is **Needs work.**

## Output format

Findings ranked Critical > High > Medium > Low, each with location, the issue,
the epidemiological consequence, and a concrete fix or the question the PI must
resolve.
