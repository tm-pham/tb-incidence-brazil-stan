# CLAUDE.md

Guidance for working in this repository. Read this before making changes.

## What this project is

We estimate **monthly, state-level** tuberculosis incidence and case-detection
probability for Brazil over **2003-2023 (252 monthly time points)**, from
routinely collected SINAN notifications and SIM mortality data. The estimands are
**true incidence** and the **case-detection probability**, neither directly
observed. These estimates feed a separate municipality-month panel study of air
pollution and TB, letting effects be reported on the incidence scale rather than
the notification scale.

The base model is the **Chitwood et al. 2025 (IJE) monthly natural-history
model** (`chitwood2025disruptions`): infection -> symptom onset -> detectable ->
notification/death via fixed-delay convolutions, fit one state at a time. The
papers and their supplements in `literature/private_pdfs/` are the methodological
source of truth. Cite them; do not invent alternative model structure. Key
references (see `literature/references.bib`): `chitwood2025disruptions` (the
monthly base we extend), `chitwood2021bes` (annual evidence-synthesis precedent;
source of the death-reporting-adjustment structure and some priors), and
`chitwood2022spatial` (municipality BYM2 burden mapping, **out of scope here** -
see below).

## Scope decision (do not break this)

- **Build:** a single state-month mechanistic model (the only new estimation in
  this repo), 2003-2023.
- **Do NOT build:** a municipality-month incidence model. At municipality-month
  resolution TB deaths are too sparse to identify incidence versus detection, and
  a downscaled outcome would strip the municipality-month variation the panel
  relies on and inject artificial spatial autocorrelation. Municipality BYM2
  downscaling (Chitwood 2022) is reserved for burden mapping, which is out of
  scope here.

## The identifying idea (do not break this)

Notifications (SINAN) and deaths (SIM) are observations generated from incidence
through the monthly natural-history process. They identify incidence and the
case-detection probability **only because informative priors pin the
natural-history parameters.** The death channel is what identifies detection, so
the **death-reporting adjustment is first-order and must be time-varying**: over
2003-2023 SIM death-registration coverage and the ill-defined-cause fraction
improved substantially, and a static adjustment would confound improving death
registration with falling incidence and rising detection.

The natural-history priors from the 2025 supplement (survival without treatment
`mu`, Pr(death | undiagnosed), Pr(death | lost to follow-up), and the
time-varying death-reporting adjustment) are **load bearing.** Treat any change
to them as a change to the identification strategy: flag it explicitly and
re-check identifiability. Never weaken them silently.

## Conventions

- **R** for all data work and orchestration. Use **data.table**, not dplyr. Use
  the base pipe `|>`.
- **Inference in Stan**, fit with **cmdstanr** (not rstan). Record the cmdstan
  version.
- **State** population from **IBGE** as the person-time offset (`gamma`), not a
  covariate. Denominators span the 2000, 2010, and 2022 censuses: use IBGE
  intercensal estimates and note the 2022 census revision.
- All paths relative via `here::here()`; the project root is the repo root.
- **Seed every stochastic step**, including the cmdstanr seed.
- **Non-centred parameterisations** for hierarchical and time-varying terms.
- **Fit each state separately** (27 states). A joint hierarchical fit across all
  states did not converge; do not re-introduce it. Each state is one 252-month
  series.
- **Temporal structure over 2003-2023**, not a single log-linear trend with one
  COVID break: a smooth long-run trend (penalised spline or RW2 on coarse,
  roughly annual-to-biannual knots) for both incidence and detection, an explicit
  COVID shock (level and slope change at April 2020 with a recovery) layered on
  it, and a seasonal component (cyclic monthly effect or a few harmonics). **Do
  not add a monthly AR-1 random walk** (it overfit and failed to converge in the
  original).
- **Prior predictive check before** fitting to real data; **posterior predictive
  check after**, per state, against observed notifications and deaths.
  Divergences, R-hat above 1.01, and low bulk or tail ESS are failures to report,
  not nuisances to suppress. Expect convergence on the 252-month series to be the
  hard part: reparameterise rather than just raising `adapt_delta`.
- Outputs only to `outputs/`; never edit `outputs/` by hand. `data/raw` is read
  only.
- Keep functions in the stage folders (`code/0X_*`) free of side effects so they
  are testable; scripts and `_targets.R` do the reading, writing, and calling.
- Writing: direct, concise prose. No em-dashes. No AI-sounding filler.

## Domain shorthand

SINAN (notifications), SIM (mortality), IBGE (population), Xpert / GeneXpert
(Xpert MTB/RIF rapid diagnostic, the detection covariate), IDC (ill-defined
causes of death, the death-adjustment covariate), CHPC / Notchpeak (the cluster).

## What not to do

- Do not commit anything under `data/raw`, `data/interim`, `data/processed`, or
  `literature/private_pdfs`. Do not commit large model fits.
- Do not auto-commit or push without asking.
- Do not modify `renv.lock` casually.
- Do not invent citations. Use only entries in `literature/references.bib` or
  papers provided by the PI. Do not copy code from the reference GitHub repo
  (https://github.com/mel-hc/TB_saie) without checking its licence and citing
  it.
- Do not weaken the load-bearing natural-history priors (survival without
  treatment `mu`, the death-given-undiagnosed / death-given-LTFU probabilities,
  and the time-varying death-reporting adjustment) silently.
- Do not build a municipality-month incidence model, and do not add a monthly
  AR-1 random walk to the trend (see Scope decision and Conventions).

## Repository layout

```
code/00_chpc_scripts/    Cluster (Notchpeak) sbatch templates
code/00_config/          config.R: paths, global seed, mc.cores
code/01_functions/       Side-effect-free functions (e.g. simulate.R)
code/02_data_processing/ prepare_stan_data() and loaders
code/03_modeling/        priors.R, fit_models.R, stan/ (.stan models)
code/04_diagnostics/     Convergence, sampler diagnostics, PPCs
code/05_analysis/        Downstream analysis
code/06_visualization/   Figures
code/07_tests/           testthat suite
code/08_reports/         Reports
data/                    raw/interim/processed (git ignored), synthetic (tracked)
literature/              references.bib, notes/, private_pdfs/ (git ignored)
prompts/                 Source-of-truth design docs for the reviewer subagents
.claude/agents/          Operational reviewer subagents
agent_reviews/           Log of AI-assisted steps and review findings
outputs/                 Regenerable artefacts (only .gitkeep tracked)
```

## Before declaring a phase done

Run the tests and `/review`, and resolve all Critical or High findings. Failing
tests, divergences, non-convergence, or any Critical/High finding from the
stan, epidemiology, or reproducibility reviewers means **Needs work.**
