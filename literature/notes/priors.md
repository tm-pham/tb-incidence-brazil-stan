# Prior specifications (provisional)

Single source of truth for the model priors. The base model is the **Chitwood
2025 (IJE) monthly natural-history model** fit per state over 2003-2023; its
supplement (Table S2) is the primary source for the priors and delay
distributions. The 2021 annual evidence-synthesis paper is the precedent for the
death-reporting-adjustment structure (now made time-varying) and some priors.
**Provisional**: the Chitwood PDFs are not yet present in
`literature/private_pdfs/` (git ignored, not in this container), so the entries
below have NOT been verified against the supplements. The literature agent must
confirm every value and add a page/table reference once the PDFs are available.
Cite, never invent.

## Load-bearing natural-history priors (Chitwood 2025 monthly base)

These identify the model and must come from the 2025 supplement (Table S2). Treat
any change as a change to the identification strategy (see CLAUDE.md). The
simulator (`code/01_functions/simulate.R`) and `code/03_modeling/priors.R` must
both read from this table. Parameters the 2025 model split pre/post-COVID
(self-cure, case fatality) should be kept biologically constant here (with
sensitivity); only reporting-related quantities drift over time.

Verification status (2026-06-04): the 2021 and 2022 supplements were read
directly (`literature/open_access_pdfs/`); confirmations below cite Chitwood 2021
Table S1 / Appendix 2 unless noted. The 2025 supplement is still NOT in the repo,
so genuinely 2025-only values are flagged "2025-only (unverified)". The
main-article bodies are not text-extractable, so the ICD-10 sets / SINAN
exclusions could not be confirmed from these files.

| Param | Meaning | Prior | Verified? |
|-------|---------|-------|-----------|
| `mu` | survival without treatment / self-cure | Beta(25.65, 33.32), mean ~0.45 | **CONFIRMED** (2021 Table S1; 2022 rounds 25.7,33.3). Untreated CFR = 1 - mu ~ 0.55. |
| `delta` = Pr(death \| lost to follow-up) | treated CFR among LTFU | Beta(4.29, 81.47), mean ~0.035 | **CONFIRMED** (2021 Table S1). NB the Beta(10,190) once listed here is 2025-only (unverified), not in 2021/2022. |
| Pr(death \| undiagnosed) | untreated case fatality | Beta(113, 87) | **2025-only (unverified)**. In 2021/2022 this is just `1 - mu` (~0.55), numerically close. |
| incidence intercept + covariate coefs | log-incidence | Normal(0, 10) | **CONFIRMED** (2021/2022). |
| detection intercept + covariate coefs | logit-detection | Normal(0, 10) | **CONFIRMED** (2021). NB Normal(0,1) applies to the *random effects*, not the intercept/coefs. |
| death-reporting adjustment | see below (now TIME-VARYING) | logit-linear (2021); static Beta(150,50) is 2025-only | **structure CONFIRMED (2021)**; generalise to time-varying. |
| `lambda` (= `p_mort_mort`) | Pr(a treatment-outcome "death" appears in SIM) | Beta(28.4, 11.6), mean ~0.71 | **CONFIRMED** (2022 Table S1; src Bartholomay 2014). Record-linkage prob, NOT an on-treatment death prob. |
| `eta` (= `p_mort_abandon`) | Pr(a treatment-outcome "LTFU" appears in SIM) | Beta(2.14, 40.7), mean ~0.05 | **CONFIRMED** (2022 Table S1; src Bartholomay 2014). |

### Death-reporting adjustment (time-varying — first-order requirement)

The 2025 model uses a static death reporting adjustment `~ Beta(150, 50)`. For
2003-2023 this MUST be made time-varying (retain the linear time trend and the
ill-defined-cause-of-death (IDC) covariate from Chitwood 2021, fed the actual IDC
series for all years; anchor to external SIM coverage estimates where possible),
or improving death registration is confounded with falling incidence and rising
detection. The 2021 structure models it as a logit-linear function of the
poorly-defined-cause fraction, anchored by an expert-opinion survey at two
settings:

| Anchor | Setting | Prior | Mean |
|--------|---------|-------|------|
| A | low (1% poorly-defined cause) | Beta(52.97, 451.2) | ~0.105 |
| B | high (15% poorly-defined cause) | Beta(97.83, 285.8) | ~0.255 |

with logit-linear trend parameters `theta0 ~ Normal(0, 1)` (intercept),
`theta2 ~ Normal(0, 0.05)` (linear time trend), `theta3 ~ Normal(0, 1)`
(poorly-defined-cause coefficient). **All CONFIRMED** against Chitwood 2021
Table S1 (2026-06-04). The full 2021 form is
`rho_ij = inv_logit(theta0 + theta1_i*sigma + theta2*(j - J) + theta3*x_ij)` with
`x_ij` the poorly-defined-cause fraction; `theta2` is the time-trend term to
reuse for our time-varying adjustment (2022, being a single cross-section, drops
it). Minor source variants on anchor A's second parameter: 451.2 (Table S1),
451.54 (Appendix 2 prose), 451.15 (GitHub Stan); cite Table S1 = 451.2.

## Regression and random-effect priors (Chitwood 2021/2025)

| Param | Prior |
|-------|-------|
| regression coefficients (`phi`, `omega`) | Normal(0, 10) |
| random-effect scales | half-Cauchy(0, 2) |

## Reference implementation (retrieved 2026-06-04) — VERIFY against the PDFs

Source: `mel-hc/TB_saie`, file `SpatialModel/Spatial_model.stan` (Chitwood 2022
spatial, `chitwood2022spatial`). The repo has NO licence, so we use only the
published model structure and prior VALUES (facts), and write our own Stan; we do
not copy its code. **Scope note:** the 2022 spatial model is the municipality
BYM2 burden-mapping precedent, which is OUT OF SCOPE for this repo (we fit a
state-month series, no municipality model). It is recorded here because its
natural-history likelihood (the notification/death structure and the
death-reporting adjustment as a logit-linear function of the ill-defined-cause
fraction) carries over to the state-month model; the BYM2/ICAR spatial rows below
do not and are kept only as reference. The state-month base follows
`chitwood2025disruptions` (monthly) plus the 2021 death-adjustment structure;
those supplements are the source of truth and must be checked.

Likelihood (Poisson), per area (here state, originally municipality):
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
| `theta_in`, `theta_ft` | Normal(0,1) | BYM2 non-spatial part (OUT OF SCOPE) |
| `rho_in`, `rho_ft` | Beta(1.5, 1.5) | BYM2 spatial-variance fraction (OUT OF SCOPE) |
| `sigma_in`, `sigma_ft` | Cauchy(0, 2) | BYM2 scales (OUT OF SCOPE) |
| ICAR `phi` | pairwise-difference + mean(phi) ~ Normal(0, 0.001) | spatial; OUT OF SCOPE |

For the state-month model the BYM2/ICAR spatial rows are replaced by the temporal
structure: a smooth long-run trend (penalised spline or RW2 on coarse knots) on
log-incidence and logit-detection, an explicit COVID shock at April 2020, and a
seasonal component. No monthly AR-1 random walk.

### DISCREPANCY — RESOLVED (2026-06-04, against the 2021/2022 supplements)

The earlier GitHub-Stan value `p_surv_no_notif ~ Normal(0.3, 0.001)`
(implying untreated CFR ~0.70) is **REFUTED**: both the 2021 and 2022 supplements
use survival without treatment `mu ~ Beta(25.65, 33.32)` (mean ~0.45), i.e.
untreated CFR = 1 - mu ~ 0.55. Use the Beta. Likewise `delta ~ Beta(4.29, 81.47)`
is confirmed (the Beta(10,190) once carried here is 2025-only and unverified).
`lambda`/`eta` (`p_mort_mort`/`p_mort_abandon`) are CONFIRMED but are
record-linkage probabilities (a death/LTFU treatment outcome appears in SIM, from
Bartholomay 2014), not on-treatment death probabilities. The death adjustment is
the logit-linear `idc` function (CONFIRMED 2021), to be made time-varying. The
2025-only quantities (Pr(death|undiagnosed) Beta(113,87); static Beta(150,50);
the monthly delay distributions) still need the 2025 supplement.

### Required DATA inputs (beyond notifications/deaths/population)

The model needs these per **state-month** (2003-2023); flagged because our data
processing does not yet produce them:

- `idc` — fraction of all-cause deaths with ill-defined (garbage) causes
  (ICD-10 R00-R99 etc.), the covariate driving the time-varying death adjustment.
  Computable from SIM all-cause deaths. **New loader.**
- `pri_mort_t`, `pri_aban_t` — treatment death and loss-to-follow-up fractions
  for the mortality likelihood, from SINAN closure status (`SITUA_ENCE`).
  Computable from the notification export. **New loader.**
- GeneXpert share-among-notified — the detection covariate (state-month). A
  capacity proxy conditioned on being notified; interpret its coefficient
  cautiously. **New loader.**
- `p_cov` / external SIM coverage — vital-registration completeness, used to
  anchor the time-varying death adjustment where possible. EXTERNAL estimate
  (paper supplement / Brazilian VR-completeness studies). **Need a source.**

## Open decisions (need PI input + the supplement)

These are load-bearing and depend on values not yet available in this container.

1. **Time-varying death-reporting adjustment.** Generalise the 2025 static
   adjustment (Beta(150, 50)) to a linear time trend plus the IDC covariate
   (2021 structure), fed the actual IDC series for 2003-2023, anchored to
   external SIM coverage. Reconcile the 2021 logit-linear anchors (A/B,
   `theta0/2/3`) with the 2025 monthly parameterisation.
2. **GeneXpert covariate specification.** Proxy in use is share-among-notified
   (denominator is the modelled notified set), so it is a capacity proxy.
   Planned upgrade: an availability/rollout measure not conditioned on the
   notified set (lab/machine coverage, or share of municipalities with Xpert
   access). Resolution: state-month if available (rollout was uneven across
   states). No separate GeneXpert term on the mortality side.
3. **Pre-2008 data-quality fork.** SINAN/SIM quality before 2008 is weaker.
   Check 2003-2007 completeness directly, then choose: (a) model 2003-2023 with
   wide, sensitivity-bounded uncertainty in early years, or (b) start the
   incidence model in 2008 and handle 2003-2007 of the panel separately.
4. **External SIM coverage source.** A `p_cov`/completeness series to anchor the
   death adjustment is not derivable from SIM alone; needs an external source.

## Data definitions (PI decisions, 2026-06-03)

These define the observed numerators/denominators and so are part of the
estimand. Encoded in `code/02_data_processing/`; do not change silently.

**Resolution and period (2026-06-04 scope change).** The model is now
**state-month, 2003-2023** (252 time points). Records are attributed to a
municipality (residence, with occurrence fallback) and then aggregated up to the
state (UF) and month; the per-record definitions below are unchanged, only the
aggregation key (state x year-month) and window differ. The earlier
municipality-year assembly in `code/02_data_processing/` predates this change and
must be re-pointed to state-month (see the code-divergence note in the latest
`agent_reviews/` entry).

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
