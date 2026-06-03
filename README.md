# Estimating subnational TB incidence in Brazil using Bayesian evidence synthesis

Bayesian evidence synthesis to estimate **true tuberculosis incidence at the
municipality level in Brazil**, and the fraction of incident cases that are
detected and treated, from routinely collected SINAN notifications and SIM
mortality data, fit in [Stan](https://mc-stan.org/) via cmdstanr.

The estimand is true incidence, which is not directly observed. The method
follows Chitwood et al. (see `literature/references.bib`). 

The project also serves as a working example of how AI-assisted coding workflows
can support reproducible academic modeling. In particular, the repository uses
structured project specifications, targeted review prompts, automated tests, and
reproducibility checks.

## Goals

1. Estimate latent TB incidence by municipality.
2. Combine information from notification and mortality data.
3. Quantify uncertainty using Bayesian inference.
4. Evaluate model fit using posterior predictive checks.
5. Maintain a reproducible R/Stan workflow.
6. Document where AI coding agents were useful and where human review was required.

## The identifying idea

Incidence is approximated by the rate at which individuals exit untreated active
disease, by one of three routes: treatment initiation (observed in SINAN), death
before treatment (observed in SIM), or self-cure (unobserved, fixed by an
informative prior). Notifications and deaths identify incidence and the fraction
treated only because informative priors pin the natural-history parameters
(`delta`, `mu`, `pi`, `rho`). Those priors are load bearing; see `CLAUDE.md`.

## Status

Project scaffolding and reviewer tooling. Models, pipeline, and data loaders are
built phase by phase. Real-data sampling will run on the Notchpeak cluster.

## Layout

```
code/                R code by stage (config, functions, data, modeling,
                     diagnostics, analysis, visualization, tests, reports)
code/03_modeling/stan/   Stan models (annual base, spatial hierarchical,
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
- Spatial data via **geobr**; population from **IBGE**.

> **Note:** `renv.lock` is currently a placeholder. Run
> `Rscript code/00_config/setup_renv.R` on a machine with CRAN access (the
> committed lockfile cannot yet reproduce the environment) and commit the
> regenerated lockfile. CmdStan and CRAN are network-blocked in the web
> container.

See `CLAUDE.md` for the full conventions and the rules on the load-bearing
priors.

## Running the pipeline

All commands run from the repo root (where `_targets.R` lives). The pipeline is a
[targets](https://docs.ropensci.org/targets/) DAG: a networked **fetch** step
that caches the raw SINAN / SIM / IBGE pulls to `data/interim/`, then a
deterministic **assemble** step that writes the Stan data list to
`outputs/stan_data/tb_stan_data.rds` with a vintage-stamped report in
`outputs/logs/`.

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
targets::tar_make()             # run / refresh the whole pipeline
targets::tar_read(stan_data)    # inspect the assembled Stan data list
targets::tar_visnetwork()       # view the DAG
```

The first run hits DATASUS/IBGE (via `microdatasus` / `sidrar`), so run it where
those are reachable. Re-running only redoes what changed: after the one networked
fetch, assembly rebuilds offline from the `data/interim/` cache. Override the
analysis window with the `TB_YEAR_START` / `TB_YEAR_END` / `TB_UF` environment
variables (defaults in `code/00_config/config.R`). Stage details are in
`code/02_data_processing/README.md`.

## Reviewing

`/review` launches five reviewers in parallel (data integrity, Stan model,
epidemiology, testing, reproducibility), ranks findings
Critical > High > Medium > Low, and returns Ready / Needs attention / Needs
work. Their design specs live in `prompts/`.

## License

TBD.
