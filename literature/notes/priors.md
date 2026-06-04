# Prior specifications (provisional)

Single source of truth for the model priors. Cited from the kickoff
specification and CLAUDE.md. **Provisional**: the Chitwood PDFs are not yet
present in `literature/private_pdfs/` (git ignored, not in this container), so
the entries below have NOT been verified against the supplements. The literature
agent must confirm every value and add a page/table reference once the PDFs are
available. Cite, never invent.

## Load-bearing natural-history priors (Chitwood 2021 annual core)

These four identify the model. Treat any change as a change to the
identification strategy (see CLAUDE.md). The simulator defaults in
`code/01_functions/simulate.R` (`tb_natural_history()`) and the future
`code/03_modeling/priors.R` must both read from this table.

| Param | Meaning | Prior | Mean | Verified? |
|-------|---------|-------|------|-----------|
| `mu` | survival untreated / self-cure | Beta(25.65, 33.32) | 0.435 | mean matches Beta; supplement page TBD |
| `delta` | P(death \| lost to follow-up) | Beta(4.29, 81.47) | 0.050 | mean matches Beta; supplement page TBD |
| `pi` | SIM mortality-system coverage | TBD | 0.900 (provisional) | **No cited distribution yet** |
| `rho` | TB-death under-reporting adjustment | logit-linear in poorly-defined-cause fraction (see below) | 0.850 (provisional scalar) | **Structure not yet implemented** |

The death under-reporting adjustment `rho` is anchored by an expert-opinion
survey at two poorly-defined-cause settings:

| Anchor | Setting | Prior | Mean |
|--------|---------|-------|------|
| A | low (1% poorly-defined cause) | Beta(52.97, 451.2) | ~0.105 |
| B | high (15% poorly-defined cause) | Beta(97.83, 285.8) | ~0.255 |

with logit-linear trend parameters `theta0 ~ Normal(0, 1)`,
`theta2 ~ Normal(0, 0.05)`, `theta3 ~ Normal(0, 1)`.

## Regression and random-effect priors (Chitwood 2021)

| Param | Prior |
|-------|-------|
| regression coefficients (`phi`, `omega`) | Normal(0, 10) |
| random-effect scales | half-Cauchy(0, 2) |

## Monthly extension priors (Chitwood 2025, Table S2) — for later

Incidence intercept/slope ~ Normal(0, 10); fraction-detected intercept/slope ~
Normal(0, 1); P(death | lost-to-follow-up) ~ Beta(10, 190); P(death |
undiagnosed) ~ Beta(113, 87); death reporting adjustment ~ Beta(150, 50).

## Open decisions (need PI input + the supplement)

These are load-bearing and depend on values not yet available in this container.
They are deliberately deferred; the simulator uses provisional scalars in the
meantime, with `simulate_tb_counts()` already accepting area-varying `pi`/`rho`
so no refactor is needed once resolved.

1. **`rho` parameterisation.** The spec models `rho` as `inv_logit` of a
   logit-linear function of the municipality poorly-defined-cause fraction
   (via `theta0/theta2/theta3`, anchored by A and B). The simulator currently
   uses a fixed scalar `rho = 0.85`. The relationship between the A/B anchor
   means (~0.105, ~0.255) and a central `rho` near 0.85 must be reconciled from
   the supplement before the recovery test can exercise the `theta` parameters.
   (stan_model_review H1.)
2. **`pi` value and identifiability.** `pi` and `rho` enter the death mean only
   as the product `pi * rho`, so they are jointly identified only through their
   priors. The provisional `pi = 0.90` has no cited distribution yet.
   (stan_model_review H2.)
3. **Municipality transfer.** SIM coverage (`pi`) and the poorly-defined-cause
   fraction behind `rho` vary across municipalities far more than across states.
   Uncritical reuse of state-level values would be a High epidemiology finding;
   justify or re-anchor when municipality data lands.

## Data definitions (PI decisions, 2026-06-03)

These define the observed numerators/denominators and so are part of the
estimand. Encoded in `code/02_data_processing/`; do not change silently.

- **TB-death definition (SIM).** Underlying cause (`CAUSABAS`) in A15-A19 only
  (active TB); B90 sequelae excluded. Constant `TB_DEATH_ICD3` in `config.R`.
  Scope: only the underlying cause is searched, NOT the contributory-cause lines
  (`LINHAA`-`LINHAD`, `LINHAII`). This is the PI decision; TB deaths recorded
  only as a contributory cause are intentionally not counted. (Flag for PI
  re-confirmation: is underlying-cause-only intended, or should contributory
  A15-A19 also count? A sensitivity analysis may be warranted.)
- **Notification source (SINAN-TB).** SINAN-TB is NOT available through
  `microdatasus::fetch_datasus()` (it serves only a few SINAN systems, none of
  them TB), so notifications are read from the PI's local export in
  `data/raw/TB_notifications/` (`.dbc`/`.dbf`/`.csv`/`.rds`), not pulled over the
  network. Only SIM (mortality) and IBGE (population) come from DATASUS/IBGE.
- **Notification numerator (SINAN).** Count new cases + relapses only; exclude
  re-entry after default (re-engaging in care), transfer, and post-mortem.
  Encoded as the `keep_entry` argument to `summarise_notifications()`. Confirmed
  against `SINAN_TB_Variable_Dictionary.xlsx`: the entry-type variable is
  `TRATAMENTO` with 1=New case, 2=Relapse, 3=Re-entry after abandonment,
  4=Unknown, 5=Transfer, 6=Post-mortem. Keep-set = codes `c("1", "2")`
  (`SINAN_ENTRY_KEEP_CODES` in `config.R`), version-safe across SINAN v4/v5.
  Estimand justification: the model identifies the rate of exit from untreated
  active disease via treatment initiation. A new case (1) and a relapse (2, a
  genuinely new episode after cure) are incident episodes and belong in the
  numerator; re-entry after abandonment (3) is the SAME episode re-engaging in
  care, so counting it would double-count one incident episode. (Flag for PI:
  if some municipalities code treatment re-starts as new cases (1) rather than
  re-entry (3), the exclusion will not catch them, a spatially heterogeneous
  over-count; consider a code-1-vs-3 sensitivity analysis.)
- **Treatment-outcome prior year (separation).** If a pre-baseline year is later
  pulled to inform `p_death_tx`/`p_ltfu`, it must be a SEPARATE
  `load_sinan_tb_notifications()` call and must NOT be passed to
  `prepare_stan_data()`; mixing it into the main notification counts would
  double-count cases. Noted in `run_data_processing.R`.
- **Geography.** Attribute by municipality of residence, falling back to
  municipality of notification/occurrence when residence is missing (e.g. Sao
  Paulo records with a blank residence code in some years). Helper
  `coalesce_muni_code()`. Codes reconciled to a 6-digit key (`normalise_muni6()`)
  because SINAN uses 6-digit and IBGE/geobr use 7-digit. Records with neither a
  valid residence nor a valid notification/occurrence code cannot be placed in
  any municipality and are dropped; the count is reported per source
  (`n_unattributable`) in the processing log. A large count is a data-quality
  flag to raise with the PI.
- **Open:** notification/diagnosis year basis (DT_DIAG vs DT_NOTIFIC vs
  treatment-start) and the analysis year range are set in the orchestration
  script, not yet fixed.

## SINAN-informed quantities (NOT priors)

`p_death_tx` (deaths on treatment) and `p_ltfu` (fraction lost to follow-up) are
observed SINAN treatment outcomes that inform `P(death | treated) = p_death_tx +
p_ltfu * delta`. Only `delta` is an estimated prior here. In the real model
these vary by area and time; the simulator holds them as scalars.
