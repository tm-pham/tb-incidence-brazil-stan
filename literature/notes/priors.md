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

## Reference implementation (retrieved 2026-06-04) — VERIFY against the PDFs

Source: `mel-hc/TB_saie`, file `SpatialModel/Spatial_model.stan` (Chitwood 2022
spatial, `chitwood2022spatial`). The repo has NO licence, so we use only the
published model structure and prior VALUES (facts), and write our own Stan; we do
not copy its code. The base model follows `chitwood2021bes` (Epidemics, annual),
which may differ slightly from the 2022 spatial values below — the 2021 supplement
is the source of truth for the base model and must be checked.

Likelihood (Poisson), municipality i:
```
notif[i]  ~ Poisson( pop100k[i] * inc[i] * ft[i] )
deaths[i] ~ Poisson( m_deaths[i] * p_cov[i] * (1 - death_adj[i]) )
  m_deaths[i] = pop100k[i] * inc[i] *
                ( ft[i]*p_mort_notif[i] + (1-ft[i])*(1 - p_surv_no_notif) )
  p_mort_notif[i] = p_mort_mort*mort_treat[i] + p_mort_abandon*aban_treat[i]
inc = exp(beta_inc_0 + beta_in*sigma_in + cov_in %*% betas_cov_inc)
ft  = inv_logit(beta_ft_0 + beta_ft*sigma_ft + cov_ft %*% betas_cov_ft)
death_adj = inv_logit(beta_0 + idc*beta_1 + theta_d*sigma_d)
```

Priors (verbatim from the reference Stan):

| Parameter | Prior | Note |
|-----------|-------|------|
| `p_surv_no_notif` | Normal(0.3, 0.001) | untreated survival/self-cure ~0.30 -> untreated CFR ~0.70 |
| `p_mort_mort` | Beta(28.4, 11.6) | ~0.71; death prob in the on-treatment-mortality group |
| `p_mort_abandon` | Beta(2.14, 40.7) | ~0.05; death prob among abandoners |
| `mort_treat[i]` | Beta(10*pri_mort_t[i], 10*(1-pri_mort_t[i])) | DATA-informed per area |
| `aban_treat[i]` | Beta(10*pri_aban_t[i], 10*(1-pri_aban_t[i])) | DATA-informed per area |
| `beta_inc_0`, `beta_ft_0`, `betas_cov_*` | Normal(0, 10) | regression |
| death_adj `beta_0`, `beta_1` | Normal(0, 1) | logit-linear in `idc` |
| `theta_d` / `sigma_d` | Normal(0,1) / Cauchy(0,2) | death-adj random effect |
| anchor `a` (idc=0.01) | Beta(52.97, 451.15) | ~0.105 |
| anchor `b` (idc=0.15) | Beta(97.83, 285.81) | ~0.255 |
| `theta_in`, `theta_ft` | Normal(0,1) | BYM2 non-spatial part |
| `rho_in`, `rho_ft` | Beta(1.5, 1.5) | BYM2 spatial-variance fraction |
| `sigma_in`, `sigma_ft` | Cauchy(0, 2) | BYM2 scales |
| ICAR `phi` | pairwise-difference + mean(phi) ~ Normal(0, 0.001) | soft sum-to-zero |

### DISCREPANCY with the provisional table above (resolve with PI)

The provisional load-bearing values at the top of this file (`mu`=0.435
Beta(25.65,33.32); `delta`=0.05 Beta(4.29,81.47); scalar `pi`=0.90, `rho`=0.85)
do NOT match the reference spatial model, which instead uses untreated
survival `p_surv_no_notif`~Normal(0.3,0.001) (CFR_untreated ~0.70, not 0.565),
a two-component treated CFR (`p_mort_mort`/`p_mort_abandon` with data-informed
`mort_treat`/`aban_treat`), `p_cov` (= `pi`) supplied as DATA per area (not a
scalar prior), and `death_adj` (= 1 - `rho`) as a logit-linear function of `idc`.
The simulator and provisional priors must be reconciled to whichever the 2021
base / 2022 spatial supplements specify.

### Required DATA inputs (beyond notifications/deaths/population)

The model needs these per municipality-year; flagged because our data processing
does not yet produce them:

- `p_cov` — vital-registration completeness (proportion of true deaths captured
  by SIM). NOT computable from SIM alone; an EXTERNAL estimate (paper supplement
  / Brazilian VR-completeness studies). **Need a source.**
- `idc` — fraction of all-cause deaths with ill-defined (garbage) causes
  (ICD-10 R00-R99 etc.). Computable from SIM all-cause deaths. **New loader.**
- `pri_mort_t`, `pri_aban_t` — treatment death and abandonment fractions, from
  SINAN closure status (`SITUA_ENCE`). Computable from the notification export.
  **New loader.**

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
