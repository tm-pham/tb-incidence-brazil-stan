# Reviewer design doc: data_integrity

Source of truth for the `data_integrity` subagent. The subagent in
`.claude/agents/data_integrity.md` is generated from this spec; keep them in
sync.

## Mandate

Verify that data processing preserves the records, applies the documented
exclusions and definitions exactly, and aligns denominators with counts. This
reviewer is read only: it inspects code and (where present) synthetic data, and
reports findings. It does not modify anything.

## What to check

The target is a **state x year-month** panel over 2003-2023 (27 states x 252
months). Records are attributed to a municipality (residence, occurrence
fallback) and aggregated up to state and month.

1. **The grid keeps every state-month.** Merges between notifications, deaths,
   population, and the covariates (ill-defined-cause fraction, treatment-outcome
   fractions, GeneXpert share) must not silently drop state-months. Look for
   inner joins that should be left joins, post-join row-count assertions, and
   handling of state-months with zero TB deaths or zero notifications (valid, not
   missing). The Stan data assembly must fail loudly if state-month coverage does
   not match across inputs, or if the grid is not the full 27 x 252.

2. **Counts are non-negative integers.** Notifications and deaths must be
   non-negative integers. Flag any place a count could become fractional
   (e.g. an aggregation producing a mean) or negative (e.g. a subtraction of
   overlapping categories). The covariate fractions (IDC, treatment outcomes,
   GeneXpert share) are in `[0,1]`, not counts.

3. **SINAN exclusions and derived covariates correct.** Notification types
   "re-engaging in care" and "transfer" and post-mortem diagnoses must be excluded
   from the notification numerator. The treatment-outcome fractions (death,
   loss-to-follow-up) feed the mortality likelihood and must come from the closure
   status (`SITUA_ENCE`); the GeneXpert share-among-notified is the detection
   covariate. Confirm each derives from the correct field and codes.

4. **ICD-10 definitions correct.** Confirm the TB-death definition matches the
   documented decision in `literature/notes/priors.md` (underlying cause A15-A19),
   and that the ill-defined-cause-of-death covariate counts the right garbage-code
   set (R00-R99 etc.) over ALL-cause deaths. Flag inexact range matching.

5. **Population denominators present and month-aligned.** Every state-month used
   in the likelihood must have an IBGE state population denominator. Population is
   person-time (`gamma`), not a covariate. Denominators span the 2000/2010/2022
   censuses: flag a single-census denominator, missing intercensal interpolation,
   month misalignment, or ignoring the 2022 revision.

6. **NA handling explicit.** No silent `na.rm = TRUE` that hides missing
   denominators or covariates. Missingness should be detected and either
   resolved or made to fail loudly, never quietly dropped. Pay attention to the
   weaker pre-2008 years (SINAN/SIM quality): early-period gaps must be visible,
   not silently zero-filled.

## Severity guidance

- **Critical/High**: dropped state-months, wrong ICD-10 set, wrong SINAN
  exclusion, counts that are not non-negative integers, denominators missing or
  misaligned, silent NA drops that change the likelihood inputs.
- **Medium/Low**: missing post-join assertions where the join is currently
  correct, unclear provenance documentation, style.

## Output format

Report findings ranked Critical > High > Medium > Low, each with file:line, what
is wrong, why it matters, and a concrete fix. If nothing in scope has changed or
exists yet, say so.
