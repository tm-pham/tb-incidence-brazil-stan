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

1. **Joins keep every municipality.** Merges between notifications, deaths,
   population, and covariates must not silently drop municipalities. Look for
   inner joins that should be left joins, post-join row-count assertions, and
   handling of municipalities with zero TB deaths or zero notifications (these
   are valid, not missing). The Stan data assembly must fail loudly if
   municipality coverage does not match across all four inputs.

2. **Counts are non-negative integers.** Notifications and deaths must be
   non-negative integers. Flag any place a count could become fractional
   (e.g. an aggregation producing a mean) or negative (e.g. a subtraction of
   overlapping categories).

3. **SINAN exclusions applied correctly.** Notification types "re-engaging in
   care" and "transfer" and post-mortem diagnoses must be excluded, because they
   are not new treatment initiations. Confirm the exclusion is on the correct
   field and value codes, and that the one extra earlier year used for
   treatment-outcome priors is handled separately, not mixed into the main
   notification counts.

4. **ICD-10 death definition correct.** A death is TB-related if a TB ICD-10
   code (A15.0-A19.9, B20.0, K67.3, K93.0, M49.0, N74.1, P37.0, U84.3) is a
   primary OR contributory cause. Confirm the code list and range matching is
   exact (A15.0-A19.9 is a range), and that contributory-cause fields are
   actually searched, not just the primary cause.

5. **Population denominators present and year-aligned.** Every municipality-year
   used in the likelihood must have an IBGE population denominator for the same
   year. Population is person-time (`gamma`), not a covariate. Flag any year
   misalignment and the post-2022 census revision caveat if the period extends
   beyond 2021.

6. **NA handling explicit.** No silent `na.rm = TRUE` that hides missing
   denominators or covariates. Missingness should be detected and either
   resolved or made to fail loudly, never quietly dropped.

## Severity guidance

- **Critical/High**: dropped municipalities, wrong ICD-10 set, wrong SINAN
  exclusion, counts that are not non-negative integers, denominators missing or
  misaligned, silent NA drops that change the likelihood inputs.
- **Medium/Low**: missing post-join assertions where the join is currently
  correct, unclear provenance documentation, style.

## Output format

Report findings ranked Critical > High > Medium > Low, each with file:line, what
is wrong, why it matters, and a concrete fix. If nothing in scope has changed or
exists yet, say so.
