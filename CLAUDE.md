# CLAUDE.md

Guidance for working in this repository. Read this before making changes.

## What this project is

We estimate true tuberculosis incidence at the municipality level in Brazil, and
the fraction of incident cases that are detected and treated, from routinely
collected SINAN notifications and SIM mortality data. The estimand is **true
incidence**, which is not directly observed.

The method follows Chitwood et al. The two papers and their supplements in
`literature/private_pdfs/` are the methodological source of truth. Cite them; do
not invent alternative model structure. Key references (see
`literature/references.bib`): `chitwood2021bes` (annual state-level core),
`chitwood2025disruptions` (monthly extension with COVID break), and
`chitwood2022spatial` (municipality spatial-mechanistic precedent, closest to
our project).

## The identifying idea (do not break this)

Incidence is approximated by the rate at which individuals exit untreated active
disease, by one of three routes: treatment initiation (observed in SINAN), death
before treatment (observed in SIM), or self-cure (unobserved, fixed by an
informative prior). Notifications and deaths identify incidence and the fraction
treated **only because informative priors pin the natural-history parameters.**

Those priors (`delta`, `mu`, `pi`, `rho`) are **load bearing.** Treat any change
to them as a change to the identification strategy: flag it explicitly and
re-check identifiability. Never weaken them silently.

## Conventions

- **R** for all data work and orchestration. Use **data.table**, not dplyr. Use
  the base pipe `|>`.
- **Inference in Stan**, fit with **cmdstanr** (not rstan). Record the cmdstan
  version.
- Spatial data via **geobr**; municipality population from **IBGE** as a
  person-time offset (`gamma`), not a covariate.
- All paths relative via `here::here()`; the project root is the repo root.
- **Seed every stochastic step**, including the cmdstanr seed.
- **Non-centred parameterisations** for hierarchical and spatial terms.
- **Prior predictive check before** fitting to real data; **posterior predictive
  check after.** Divergences, R-hat above 1.01, and low bulk or tail ESS are
  failures to report, not nuisances to suppress.
- Default to **spatial pooling** (BYM2 / ICAR) for municipalities. Expect
  convergence to be the hard part: reparameterise rather than just raising
  `adapt_delta`.
- Outputs only to `outputs/`; never edit `outputs/` by hand. `data/raw` is read
  only.
- Keep functions in the stage folders (`code/0X_*`) free of side effects so they
  are testable; scripts and `_targets.R` do the reading, writing, and calling.
- Writing: direct, concise prose. No em-dashes. No AI-sounding filler.

## Domain shorthand

SINAN (notifications), SIM (mortality), IBGE (population), FHS (Family Health
Strategy), CHPC / Notchpeak (the cluster).

## What not to do

- Do not commit anything under `data/raw`, `data/interim`, `data/processed`, or
  `literature/private_pdfs`. Do not commit large model fits.
- Do not auto-commit or push without asking.
- Do not modify `renv.lock` casually.
- Do not invent citations. Use only entries in `literature/references.bib` or
  papers provided by the PI. Do not copy code from the reference GitHub repo
  (https://github.com/mel-hc/TB_saie) without checking its licence and citing
  it.
- Do not weaken the identifying priors (`delta`, `mu`, `pi`, `rho`) silently.

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
