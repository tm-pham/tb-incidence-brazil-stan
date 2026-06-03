# tb-incidence-brazil-stan

Bayesian evidence synthesis to estimate **true tuberculosis incidence at the
municipality level in Brazil**, and the fraction of incident cases that are
detected and treated, from routinely collected SINAN notifications and SIM
mortality data, fit in [Stan](https://mc-stan.org/) via cmdstanr.

The estimand is true incidence, which is not directly observed. The method
follows Chitwood et al. (see `literature/references.bib`). The papers and their
supplements in `literature/private_pdfs/` are the methodological source of truth.

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

See `CLAUDE.md` for the full conventions and the rules on the load-bearing
priors.

## Reviewing

`/review` launches five reviewers in parallel (data integrity, Stan model,
epidemiology, testing, reproducibility), ranks findings
Critical > High > Medium > Low, and returns Ready / Needs attention / Needs
work. Their design specs live in `prompts/`.

## License

TBD.
