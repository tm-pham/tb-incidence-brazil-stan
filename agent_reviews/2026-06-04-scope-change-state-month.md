# Scope change: municipality-annual -> state-month (2003-2023)

Date: 2026-06-04
Trigger: PI scope document "State-Level TB Incidence & Detection Estimates for an
Air-Pollution Panel Study". This is a documentation-consistency pass over the
Markdown files; no code was changed (see the code-divergence note below).

## The pivot

| Aspect | Was | Now |
|---|---|---|
| Estimand | municipality annual incidence + fraction treated | state-month incidence + case-detection probability |
| Period | ~2015-2019 / 2016-2018 | 2003-2023, 252 monthly time points |
| Base paper | Chitwood 2021 annual / 2022 spatial | Chitwood 2025 monthly (`chitwood2025disruptions`) |
| Pooling | BYM2/ICAR across municipalities | fit each state separately; no spatial; no monthly AR-1 |
| Trend | single log-linear + one COVID break | smooth spline/RW2 trend + explicit COVID shock (Apr 2020) + seasonal |
| Death adjustment | static | time-varying (time trend + ill-defined-cause series; anchor to SIM coverage) |
| Detection covariate | FHS coverage, log GDP | GeneXpert share-among-notified (state-month) |
| Output | municipality-year Stan list | tidy state x year-month posterior draws of incidence and detection, feeding a municipality-month air-pollution panel |
| Municipality model | the project | explicitly OUT OF SCOPE (BYM2 downscaling reserved for burden mapping) |

## Markdown files updated and why

- `CLAUDE.md` - what-this-project-is, identifying idea, conventions, domain
  shorthand, what-not-to-do: rewritten to the state-month 2025 base, per-state
  fitting, temporal structure, time-varying death adjustment, GeneXpert, and the
  scope decision (no municipality model, no monthly AR-1).
- `README.md` - title, intro, goals, identifying idea, status, stan-models line,
  tooling (dropped geobr/spatial), and the pipeline Sources block (state-month,
  new covariates).
- `literature/notes/priors.md` - reframed around the 2025 monthly base; load-
  bearing table updated to 2025 priors; death adjustment marked time-varying;
  BYM2 rows marked out of scope; required DATA inputs updated (IDC, treatment
  outcomes, GeneXpert, external SIM coverage); open decisions replaced (time-
  varying death adjustment, GeneXpert spec, pre-2008 fork); data-definitions
  resolution/period note added.
- `prompts/stan_model_review.md` + `.claude/agents/stan_model_review.md` -
  fidelity now checks the monthly natural-history process, smooth trend + COVID
  shock + seasonal, time-varying death adjustment, GeneXpert, per-state, no
  BYM2/AR-1; identifiability against the 2025 priors.
- `prompts/epidemiology_review.md` + `.claude/agents/epidemiology_review.md` -
  estimands (incidence + detection); state person-time over the 2000/2010/2022
  censuses; time-varying death adjustment as first-order; GeneXpert + panel
  maintained assumption; pre-2008 robustness.
- `prompts/data_integrity.md` + `.claude/agents/data_integrity.md` - target is
  the 27 x 252 state-month grid; SINAN exclusions + treatment-outcome + GeneXpert
  covariates; IDC covariate; state denominators across the three censuses.
- `prompts/testing.md` + `.claude/agents/testing.md` - recovery test over a
  state-month series recovering incidence + detection; detection in [0,1];
  covariate fractions; 2025 prior values.
- `literature/agent_literature_instructions.md` - 2025 as the base; 2022 spatial
  out of scope; tasks updated for the generalised trend, time-varying death
  adjustment, GeneXpert, new data inputs, pre-2008 fork.
- `literature/private_pdfs/README.md` - paper roles reordered (2025 base, 2021
  death-adjustment source, 2022 out of scope).
- `data/README.md`, `data/raw/README.md` - state-month sources, new covariates,
  census handling, pre-2008 caveat.
- `code/02_data_processing/README.md` - scope note that the target is now
  state-month and the current loaders predate it.

## Files deliberately NOT changed

- `prompts/reproducibility.md`, `.claude/agents/reproducibility.md`,
  `.claude/commands/review.md`, `data/interim/README.md`,
  `data/processed/README.md`: generic; no scope references.
- `agent_reviews/2026-06-03-*.md`: dated historical logs; left as records.

## CODE DIVERGENCE (follow-up, not done here)

The documentation now describes the state-month 2025 model, but the CODE still
implements the old scope and must be re-pointed in a separate implementation
pass:

- `code/02_data_processing/` aggregates to municipality-year; needs state-month
  aggregation plus new loaders for the IDC fraction, treatment-outcome fractions,
  and the GeneXpert share. `config.R` defaults (`YEAR_START/END` 2015-2019,
  `TB_UF`) and `_targets.R`/`prepare_stan_data()` keying are municipality-year.
- `code/01_functions/simulate.R` simulates the annual municipality DGP; needs the
  monthly natural-history DGP (delay convolutions, trend + COVID + seasonal,
  time-varying death adjustment, detection + GeneXpert).
- `code/03_modeling/stan/*` stubs describe the 2021/2022 structure; the base
  model must be the 2025 monthly per-state model.
- The load-bearing prior values still need verification against the 2025 (and
  2021 death-adjustment) supplements (PDFs not in the container).

Until that pass, tests and the current pipeline reflect the old scope.
