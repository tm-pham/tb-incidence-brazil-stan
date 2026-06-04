# Migration plan: code -> state-month (2003-2023)

Companion to `2026-06-04-scope-change-state-month.md` (which updated the docs).
This plans the CODE migration. Estimands: monthly state-level incidence rate and
case-detection probability, 2003-2023 (252 months x 27 states), Chitwood 2025
monthly base, fit per state. Output: tidy state x year-month posterior draws.

## Principles

- Reuse raw acquisition (SINAN local read, SIM fetch, IBGE); only the aggregation
  key and the model change.
- Separate the expensive raw fetch (cache RAW records to data/interim) from cheap
  aggregation, so SIM is downloaded once and serves TB deaths, the ill-defined-
  cause (IDC) fraction, and re-aggregation.
- Functions stay side-effect free; `_targets.R`/scripts orchestrate.
- Every change paired with tests; `/review` before declaring done.
- Exact 2025 priors / delay distributions and several data definitions need the
  supplement + PI sign-off (listed under Decisions); build structure first,
  recover-test the machinery with provisional values.

## Reusability of the in-progress run (important)

The current `make data` caches `data/interim/raw_deaths.rds` as **aggregated
municipality-year TB counts**, not raw SIM records. That cannot be re-aggregated
to state-month and lacks all-cause deaths (needed for IDC). So the current run's
cache is NOT reusable; the SIM download will happen once more under the new
raw-caching fetch. Recommendation: stop the current run; do not wait for it.

## Phase A - Data layer (state-month assembly). Do first; unblocks everything.

1. `code/00_config/config.R`
   - `YEAR_START_DEFAULT <- 2003L`, `YEAR_END_DEFAULT <- 2023L`.
   - Add `UF_CODES` (27 state codes) for the canonical grid; add
     `COVID_BREAK <- "2020-04"`; add `INCIDENCE_START` (2003 or 2008, per the
     pre-2008 fork decision).
2. `code/02_data_processing/geo_utils.R`
   - Add `uf_from_muni()` (UF = leading 2 digits of the IBGE code). Keep
     `normalise_muni6`/`coalesce_muni_code` (attribute to residence muni, then
     roll up to UF). Add `year_month()` date -> "YYYY-MM".
3. Raw fetch with RAW caching (new structure)
   - SIM: fetch ALL-cause SIM-DO once, cache raw (state, month, CAUSABAS) records
     to data/interim. Derive (a) TB deaths by state-month and (b) the IDC
     fraction by state-month from the one cache.
   - SINAN: read the local export once; derive notifications, treatment-outcome
     fractions, and the GeneXpert share from it.
4. `code/02_data_processing/load_sim.R`
   - `filter_tb_deaths()` -> aggregate to (uf, year_month) using `sim_year`/month.
   - New `idc_fraction()` (pure): garbage-code deaths / all-cause deaths per
     state-month. Confirm the garbage-code set.
5. `code/02_data_processing/load_notifications.R`
   - `summarise_notifications()` -> aggregate to (uf, year_month) by DT_DIAG.
   - New `treatment_outcomes()` (pure): pri_mort_t (death) and pri_aban_t / LTFU
     fractions per state-month from `SITUA_ENCE` (confirm cohort timing: by
     notification month vs closure month).
   - New `genexpert_share()` (pure): share of notifications diagnosed via
     GeneXpert per state-month. CONFIRM the SINAN diagnostic-method variable from
     the dictionary (which column encodes Xpert/TRM).
6. `code/02_data_processing/load_population.R`
   - State population by year-month: IBGE state SIDRA table; intercensal annual
     estimates (2000/2010/2022) expanded to monthly (interpolation method TBD).
     Drop geobr (no spatial).
7. `code/02_data_processing/prepare_stan_data.R`
   - Universe = full 27 x 252 grid (built from a template, not from population).
   - Left-join counts (zero-fill), join covariates (idc, genexpert_share,
     pri_mort_t, pri_aban_t), population offset. Add time index, COVID indicator
     (month >= 2020-04), seasonal basis (month-of-year), and the trend basis
     (spline/RW2 knots). Provide per-state slices (we fit each state separately).

## Phase B - Simulator (monthly DGP). Must match the Stan model.

8. `code/01_functions/simulate.R` - rewrite to the 2025 monthly process per
   state: infection -> onset -> detectable -> notification/death via fixed-delay
   convolutions; incidence(t) = exp(smooth trend + COVID shock + seasonal);
   detection(t) = inv_logit(smooth trend + COVID shock + seasonal + GeneXpert);
   time-varying death adjustment = f(time, idc(t)); monthly Poisson draws. This
   is the recovery-test backbone.

## Phase C - Stan model.

9. `code/03_modeling/priors.R` - centralise the 2025 priors (single source of
   truth), pending supplement verification.
10. `code/03_modeling/stan/tb_incidence_base.stan` - one state's 252-month model:
    convolutions; RW2/spline trend + COVID shock + seasonal on log-incidence and
    logit-detection; time-varying death adjustment; GeneXpert covariate; Poisson
    likelihoods; `prior_only` switch; generated quantities (incidence rate,
    detection probability). Non-centred. No BYM2, no monthly AR-1.
11. `code/03_modeling/fit_models.R` - cmdstanr compile + sample per state, seed
    from `GLOBAL_SEED`, record cmdstan version. Remove/retire the BYM2
    `tb_incidence_hierarchical.stan` (out of scope).

## Phase D - Pipeline, tests, outputs.

12. `_targets.R` - raw-cache fetch targets; covariate-derivation targets;
    state-month panel target; per-state fit targets (dynamic branching over 27
    states); combine -> tidy state x year-month draws.
13. Tests - rewrite simulate tests (monthly), prepare_stan_data tests (27 x 252
    grid), new covariate-loader tests, the gated per-state recovery test.
14. Outputs - tidy draws keyed by state x year-month (incidence, detection), the
    one-line-merge object for the panel.
15. `/review`; resolve Critical/High.

## Decisions needed (PI + 2025 supplement)

1. 2025 model equations, delay distributions, and exact priors (supplement).
2. Pre-2008 fork: model 2003-2023 with wide early uncertainty, or start incidence
   in 2008 and handle 2003-2007 of the panel separately.
3. SINAN GeneXpert/diagnostic-method variable (dictionary) and the
   share-among-notified definition.
4. Treatment-outcome cohort timing (notification month vs closure month).
5. External SIM-coverage series to anchor the time-varying death adjustment.
6. Monthly population interpolation method across the censuses.

## Suggested order

Phase A (re-points the pipeline to state-month) -> B + C together (they must
agree; build with provisional priors, recovery-test the machinery) -> D ->
/review. Phases B/C's exact numbers wait on the supplement; the structure does
not.
