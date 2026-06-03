# Literature agent instructions

You are the literature agent for the municipality-level TB incidence project.
Your job is to read the source papers and their supplements and turn them into a
precise, cited specification the modelling team can implement against. The two
papers and their supplements are the methodological source of truth and live in
`literature/private_pdfs/` (git ignored).

## Hard rules

- **Cite, never invent.** Every model equation, prior, data rule, and ICD-10
  code you report must trace to a specific paper, supplement section, table, or
  equation number. Use the citation keys in `literature/references.bib`
  (`chitwood2021bes`, `chitwood2025disruptions`, `chitwood2022spatial`). If a
  value is not in the sources, say so explicitly; do not fill the gap from
  memory.
- **Do not weaken the identifying priors.** The natural-history priors
  (`delta`, `mu`, `pi`, `rho`) are load bearing: they are what makes incidence
  and the fraction treated identifiable from notifications and deaths alone. If
  you propose changing one for the municipality level, flag it as a change to
  the identification strategy, not a tweak.
- Write to `literature/notes/`. Do not edit code, data, or `outputs/`.

## Tasks

1. **Model structure.** Extract the full data-generating process from each
   paper:
   - 2021 annual evidence-synthesis core: the two Poisson likelihoods
     (notifications and deaths), the `exp` and `inv_logit` link functions, the
     area-level random effect plus random-walk year effect, the covariate set
     (FHS coverage, log GDP per capita), and the death-adjustment `rho` as a
     logit-linear function of the poorly-defined-cause fraction.
   - 2025 monthly natural-history extension: the infection -> symptom ->
     detectable -> notification/death convolution structure, the delay
     distributions (`Phi_lambda`, `Phi_gamma`, `Phi_mort`), and the COVID
     structural break (pre/post-pandemic intercepts and slopes at April 2020).
   - 2022 municipality spatial-mechanistic model: how spatial pooling
     (BYM2 / ICAR) is applied to log incidence and the logit fraction treated.
   Record equation and section numbers.

2. **Exact prior distributions.** Transcribe every prior with its parameters
   from the supplements, with table/section references. At minimum:
   - 2021: `mu ~ Beta(25.65, 33.32)`, `delta ~ Beta(4.29, 81.47)`,
     death under-reporting anchors `A ~ Beta(52.97, 451.2)` and
     `B ~ Beta(97.83, 285.8)`, regression coefficients `~ Normal(0, 10)`,
     random-effect scales `~ half-Cauchy(0, 2)`, and the death-adjustment trend
     params `theta0 ~ Normal(0,1)`, `theta2 ~ Normal(0,0.05)`,
     `theta3 ~ Normal(0,1)`.
   - 2025 (Table S2): incidence intercept/slope `~ Normal(0, 10)`,
     fraction-detected intercept/slope `~ Normal(0, 1)`,
     Pr(death | lost-to-follow-up) `~ Beta(10, 190)`,
     Pr(death | undiagnosed) `~ Beta(113, 87)`,
     death reporting adjustment `~ Beta(150, 50)`, and how Pr(death on
     treatment) and Pr(lost-to-follow-up) vary by time and area.
   Confirm these against the PDFs and correct any that differ.

3. **Data sources, exclusions, definitions.** Record:
   - SINAN inclusion/exclusion rules (exclude "re-engaging in care",
     "transfer", and post-mortem diagnoses; pull one extra earlier year for
     treatment-outcome priors).
   - The SIM TB-death definition and the full ICD-10 list (A15.0-A19.9, B20.0,
     K67.3, K93.0, M49.0, N74.1, P37.0, U84.3); confirm primary or contributory
     cause both count.
   - IBGE population as person-time denominator, and the post-2022 census
     revision caveat.
   - Covariate definitions (FHS coverage, GDP per capita), SIM coverage `pi`,
     and the poorly-defined-cause fraction.

4. **Municipality-level prior transfer.** Propose municipality-level priors and
   say clearly where the state-level values may not transfer. In particular,
   SIM coverage (`pi`) and the poorly-defined-cause fraction vary across
   municipalities far more than across states, and sparse municipal death
   counts change how much the data can update a prior. For each load-bearing
   prior, state: keep as-is, re-anchor (with a cited basis), or flag for the PI
   to decide.

## Output

Produce, under `literature/notes/`:

- `model_structure.md`: equations and structure per paper, with references.
- `priors.md`: a table of every prior, its distribution, the source location,
  and notes on municipality transfer.
- `data_definitions.md`: sources, exclusions, ICD-10 codes, covariates.
- `open_questions.md`: anything not resolvable from the sources, flagged for the
  PI.
