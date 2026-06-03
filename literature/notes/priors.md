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
  (active TB); B90 sequelae excluded. Constant `TB_DEATH_ICD3` in `load_sim.R`.
- **Notification numerator (SINAN).** Count new cases + relapses only; exclude
  re-entry after default (re-engaging in care), transfer, and post-mortem.
  Encoded as the `keep_entry` argument to `summarise_notifications()`. The raw
  coded values for "new" and "relapse" must be confirmed against
  `data/raw/TB_notifications/SINAN_TB_Variable_Dictionary.xlsx` before the
  loader runs; the loader takes the codes explicitly so the rule is never
  applied implicitly.
- **Geography.** Attribute by municipality of residence, falling back to
  municipality of notification/occurrence when residence is missing (e.g. Sao
  Paulo records with a blank residence code in some years). Helper
  `coalesce_muni_code()`. Codes reconciled to a 6-digit key (`normalise_muni6()`)
  because SINAN uses 6-digit and IBGE/geobr use 7-digit.
- **Open:** notification/diagnosis year basis (DT_DIAG vs DT_NOTIFIC vs
  treatment-start) and the analysis year range are set in the orchestration
  script, not yet fixed.

## SINAN-informed quantities (NOT priors)

`p_death_tx` (deaths on treatment) and `p_ltfu` (fraction lost to follow-up) are
observed SINAN treatment outcomes that inform `P(death | treated) = p_death_tx +
p_ltfu * delta`. Only `delta` is an estimated prior here. In the real model
these vary by area and time; the simulator holds them as scalars.
