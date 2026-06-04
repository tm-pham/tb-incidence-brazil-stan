# Literature agent instructions

You are the literature agent for the **state-month TB incidence and detection**
project (Brazil, 2003-2023, extending Chitwood 2025). Your job is to read the
source papers and their supplements and turn them into a precise, cited
specification the modelling team can implement against. The papers and their
supplements are the methodological source of truth and live in
`literature/private_pdfs/` (git ignored). Note the scope: we build a state-month
model only; the 2022 municipality spatial model is out of scope (burden mapping).

## Hard rules

- **Cite, never invent.** Every model equation, prior, data rule, and ICD-10
  code you report must trace to a specific paper, supplement section, table, or
  equation number. Use the citation keys in `literature/references.bib`
  (`chitwood2021bes`, `chitwood2025disruptions`, `chitwood2022spatial`). If a
  value is not in the sources, say so explicitly; do not fill the gap from
  memory.
- **Do not weaken the identifying priors.** The 2025 natural-history priors
  (survival without treatment `mu`, Pr(death | undiagnosed), Pr(death | lost to
  follow-up), and the time-varying death-reporting adjustment) are load bearing:
  they are what makes incidence and the detection probability identifiable from
  notifications and deaths alone. If you propose changing one, flag it as a change
  to the identification strategy, not a tweak.
- Write to `literature/notes/`. Do not edit code, data, or `outputs/`.

## Tasks

1. **Model structure.** Extract the full data-generating process, with the **2025
   monthly model as the base**:
   - 2025 monthly natural-history model (the base): the infection -> symptom ->
     detectable -> notification/death convolution structure, the delay
     distributions (`Phi_lambda`, `Phi_gamma`, `Phi_mort`), the incidence and
     detection sub-models, and the COVID structural break at April 2020. Record
     how it must be generalised for 2003-2023: a smooth long-run trend (penalised
     spline or RW2 on coarse knots) for incidence and detection, an explicit COVID
     shock (level + slope change + recovery), and a seasonal component; NO monthly
     AR-1; fit per state.
   - 2021 annual evidence-synthesis: the death-reporting adjustment as a
     logit-linear function of the ill-defined-cause fraction (anchors, trend
     params). This is the structure to make the death adjustment TIME-VARYING.
   - The GeneXpert detection covariate: how a time-varying detection covariate
     enters the detection sub-model (analogous to the FHS-coverage covariate).
   - 2022 municipality spatial model: OUT OF SCOPE; note only that its
     natural-history likelihood matches, and skip the BYM2/ICAR spatial part.
   Record equation and section numbers.

2. **Exact prior distributions.** Transcribe every prior with its parameters
   from the supplements, with table/section references. The **2025 supplement
   (Table S2) is primary**:
   - 2025: incidence intercept/slope `~ Normal(0, 10)`,
     detection intercept/slope `~ Normal(0, 1)`,
     Pr(death | lost-to-follow-up) `~ Beta(10, 190)`,
     Pr(death | undiagnosed) `~ Beta(113, 87)`,
     the death reporting adjustment (`~ Beta(150, 50)` static in 2025, to be made
     time-varying here), survival without treatment `mu`, and the delay
     distributions. Note how Pr(death on treatment) and Pr(lost-to-follow-up)
     vary by time and area.
   - 2021 (for the death adjustment): the under-reporting anchors
     `A ~ Beta(52.97, 451.2)`, `B ~ Beta(97.83, 285.8)`, and the logit-linear
     trend params `theta0 ~ Normal(0,1)`, `theta2 ~ Normal(0,0.05)`,
     `theta3 ~ Normal(0,1)`, used to generalise the adjustment to time-varying.
   Confirm these against the PDFs and correct any that differ. State which
   parameters the 2025 model split pre/post-COVID, and which should be kept
   biologically constant over 2003-2023 with sensitivity.

3. **Data sources, exclusions, definitions** (state-month, 2003-2023). Record:
   - SINAN inclusion/exclusion rules (exclude "re-engaging in care", "transfer",
     and post-mortem diagnoses), and the treatment-outcome fractions (death,
     loss-to-follow-up) from closure status, for the mortality likelihood.
   - The SIM TB-death definition and ICD-10 list (confirm against the documented
     decision), plus the ill-defined-cause-of-death covariate (garbage-code set
     over all-cause deaths) for the time-varying death adjustment.
   - IBGE state population as person-time denominator: intercensal estimates
     spanning the 2000, 2010, and 2022 censuses, with the 2022 revision.
   - The GeneXpert detection covariate (share-among-notified, state-month) and
     any external SIM-coverage series to anchor the death adjustment.
   - The pre-2008 SINAN/SIM data-quality situation, to inform the fork (model
     2003-2023 with wide early uncertainty vs start the incidence model in 2008).

4. **State-month and period considerations.** State clearly where the published
   (often shorter-window) priors may need care over 2003-2023: the death
   adjustment must be time-varying (improving SIM coverage), the GeneXpert effect
   is identified only from ~2014, and early years are data-sparse. For each
   load-bearing prior, state: keep as-is, generalise (with a cited basis), or flag
   for the PI to decide.

## Output

Produce, under `literature/notes/`:

- `model_structure.md`: equations and structure per paper, with references.
- `priors.md`: a table of every prior, its distribution, the source location,
  and notes on the 2003-2023 generalisation (time-varying death adjustment).
- `data_definitions.md`: sources, exclusions, ICD-10 codes, covariates.
- `open_questions.md`: anything not resolvable from the sources, flagged for the
  PI.
