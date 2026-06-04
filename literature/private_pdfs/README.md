# literature/private_pdfs/

Place the source PDFs here. This directory is git ignored (copyright); only this
README and `.gitkeep` are tracked.

Expected files (the methodological source of truth):

- Chitwood et al. 2025, International Journal of Epidemiology. Quantifying
  disruptions to tuberculosis case detection in Brazilian states during the
  COVID-19 pandemic. (`chitwood2025disruptions`) - the **monthly state-level base
  model** we extend to 2003-2023.
- Chitwood et al. 2021, Epidemics. Bayesian evidence synthesis to estimate
  subnational TB incidence: an application in Brazil. (`chitwood2021bes`) - source
  of the death-reporting-adjustment structure (the logit-linear, now made
  time-varying, ill-defined-cause adjustment) and some priors.

The 2022 PLOS Global Public Health municipality paper (`chitwood2022spatial`) is
the BYM2 burden-mapping precedent and is **out of scope** here (we build no
municipality model); add it for reference only.

See `literature/references.bib` for citation keys and
`literature/agent_literature_instructions.md` for what to extract from the
supplements.
