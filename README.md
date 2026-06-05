# Monthly state-level TB incidence and case detection in Brazil, 2003-2023

> **Status: work in progress.** The data pipeline is built, tested, and
> validated; the Stan model is implemented and its math is checked against the
> simulator, but it has **not yet been validated on real data** (the recovery
> test and the per-state fits run on a machine with cmdstan). Several
> data-definition decisions are still pending confirmation (see
> `literature/notes/priors.md`, "Open decisions"), and no incidence/detection
> results are available yet.

A **state-month mechanistic model** of tuberculosis **incidence** and
**case-detection probability** for Brazil over **2003-2023 (252 monthly time
points)**, from routinely collected SINAN notifications and SIM mortality data,
fit in [Stan](https://mc-stan.org/) via cmdstanr one state at a time.

The estimands are true incidence and the case-detection probability, neither
directly observed. The base model extends Chitwood et al. 2025 (IJE), the monthly
natural-history model (see `literature/references.bib`). These estimates feed a
separate municipality-month panel study of air pollution and TB, so effects can
be reported on the incidence scale rather than the notification scale. We do
**not** build a municipality-month incidence model (see `CLAUDE.md`, Scope
decision).

The project also serves as a working example of how AI-assisted coding workflows
can support reproducible academic modeling. In particular, the repository uses
structured project specifications, targeted review prompts, automated tests, and
reproducibility checks.

## Goals

1. Estimate latent monthly TB incidence by state, 2003-2023.
2. Estimate the monthly case-detection probability by state.
3. Combine information from notification and mortality data.
4. Quantify uncertainty using Bayesian inference.
5. Evaluate model fit using per-state posterior predictive checks.
6. Maintain a reproducible R/Stan workflow.
7. Document where AI coding agents were useful and where human review was required.

## The identifying idea

Notifications (SINAN) and deaths (SIM) are observations generated from incidence
through the monthly natural-history process: infection to symptom onset to
detectable to notification or death, via fixed-delay convolutions. They identify
incidence and the case-detection probability only because informative priors pin
the natural-history parameters. The death channel identifies detection, so the
**death-reporting adjustment is time-varying** across the full window. Those
priors are load bearing; see `CLAUDE.md`.

## Status

Project scaffolding, data loaders, and reviewer tooling. The state-month model,
pipeline, and estimates are built phase by phase. Real-data sampling will run on
the Notchpeak cluster.

## Layout

```
code/                R code by stage (config, functions, data, modeling,
                     diagnostics, analysis, visualization, tests, reports)
code/03_modeling/stan/   Stan models (state-month base, components,
                         sensitivity)
data/                raw/interim/processed (git ignored), synthetic (tracked)
literature/          references.bib, extraction notes, private PDFs (ignored)
prompts/             Design docs for the five reviewer subagents
.claude/agents/      Operational reviewer subagents; /review runs them all
agent_reviews/       Log of AI-assisted steps and review findings
outputs/             Regenerable artefacts (only structure tracked)
_targets.R           Pipeline (targets)
Makefile             Thin CLI over targets and tests
```

## Tooling

- **R** with **data.table** and the base pipe `|>`.
- **Stan** via **cmdstanr**; dependencies pinned with **renv**.
- **targets** for the pipeline; **testthat** for tests.
- State population from **IBGE** (intercensal estimates spanning the 2000, 2010,
  and 2022 censuses).

> **Note:** `renv.lock` is currently a placeholder. Run
> `Rscript code/00_config/setup_renv.R` on a machine with CRAN access (the
> committed lockfile cannot yet reproduce the environment) and commit the
> regenerated lockfile. CmdStan and CRAN are network-blocked in the web
> container.

See `CLAUDE.md` for the full conventions and the rules on the load-bearing
priors.

## Running the pipeline

All commands run from the repo root (where `_targets.R` lives). The pipeline is a
[targets](https://docs.ropensci.org/targets/) DAG: a **prepare** step (read the
local SINAN-TB notification export, fetch SIM and IBGE) that caches the raw
records to `data/interim/`, then a deterministic **assemble** step that writes the
state-month panel to `outputs/stan_data/tb_state_month_panel.rds` with a
diagnostics report in `outputs/logs/`, and finally a per-state **fit** step
(needs cmdstan) writing `outputs/estimates/tb_incidence_estimates.rds`.

**Sources** (aggregated to **state x year-month**, 2003-2023). SINAN-TB
notifications are read from a local export placed in `data/raw/TB_notifications/`
(`.dbc`/`.dbf`/`.csv`/`.rds`) -- SINAN-TB is not served by `microdatasus`. SIM
mortality is pulled from DATASUS and IBGE population from SIDRA, so the prepare
step needs both the notification file and network access. The model also uses
treatment-outcome fractions (death, loss-to-follow-up) for the mortality
likelihood, the ill-defined-cause-of-death covariate for the time-varying death
adjustment, and the GeneXpert share-among-notified covariate for the detection
sub-model.

```bash
make data       # build the Stan data (fetch if needed, then assemble)
make fetch      # STEP 1 only: pull from DATASUS/IBGE -> data/interim/ (needs network)
make test       # run the testthat suite
make pipeline   # run the full targets pipeline
make show       # list outdated targets
```

Or drive `targets` directly in an R session (working directory = repo root;
opening the `.Rproj` in RStudio sets it for you):

```r
targets::tar_make()                 # run / refresh the whole pipeline
targets::tar_read(assembled)        # inspect the assembled state-month panel
targets::tar_read(state_estimate)   # per-state incidence/detection estimates (after fitting)
targets::tar_visnetwork()           # view the DAG
```

The first run hits DATASUS/IBGE (via `microdatasus` / `sidrar`), so run it where
those are reachable. Re-running only redoes what changed: after the one networked
fetch, assembly rebuilds offline from the `data/interim/` cache. Override the
analysis window with the `TB_YEAR_START` / `TB_YEAR_END` / `TB_UF` environment
variables (defaults in `code/00_config/config.R`). Stage details are in
`code/02_data_processing/README.md`; the model is described in
`code/03_modeling/README.md` and `code/08_reports/methods.qmd`.

### Operational notes (hard-won)

- **Do not `tar_destroy()` casually.** The SIM pull from DATASUS can take hours;
  destroying the store forces a full re-fetch. To pick up code changes just
  `git pull` and `tar_make()` (changed functions invalidate only their downstream
  targets). The SIM fetch is self-healing: it re-fetches only missing state-years
  and asserts state-month completeness, so a DATASUS FTP timeout cannot silently
  become "zero deaths".
- **Validate the model before real fits:** `RUN_RECOVERY_TEST=1 Rscript
  code/07_tests/testthat.R` compiles the Stan model and checks it recovers known
  incidence/detection from simulated data (needs cmdstan).
- **SIDRA table IDs are configurable** in `code/00_config/config.R`; a failed
  population fetch prints the returned column names so the IDs can be repointed.

## Reviewing

`/review` launches five reviewers in parallel (data integrity, Stan model,
epidemiology, testing, reproducibility), ranks findings
Critical > High > Medium > Low, and returns Ready / Needs attention / Needs
work. Their design specs live in `prompts/`.

## License

TBD.
