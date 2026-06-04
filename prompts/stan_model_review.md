# Reviewer design doc: stan_model_review

Source of truth for the `stan_model_review` subagent. Keep them in sync.

## Mandate

Verify that the Stan models faithfully implement the **Chitwood 2025 monthly
natural-history structure** (state-month, fit one state at a time), that the model
is identified by its informative priors, that the trend/seasonal/COVID and
time-varying death-adjustment structure is sound, and that the R simulator and the
Stan model agree. Read only: inspect and report.

## What to check

1. **Fidelity to the monthly natural-history structure.** The base model must
   encode the 2025 monthly process: infection -> symptom onset -> detectable ->
   notification/death via fixed-delay convolutions, with monthly Poisson
   likelihoods for notifications and deaths per state. Check:
   - log-incidence and logit-detection each carry a **smooth long-run trend**
     (penalised spline or RW2 on coarse, ~annual-to-biannual knots), an
     **explicit COVID shock** (level and slope change at April 2020 with a
     recovery), and a **seasonal component** (cyclic monthly effect or a few
     harmonics). Flag a single log-linear-plus-one-break trend, and flag any
     **monthly AR-1 random walk** (explicitly excluded: it overfit / failed to
     converge).
   - the **death channel** carries a **time-varying death-reporting adjustment**
     (linear time trend + the ill-defined-cause-of-death covariate, fed the
     actual series), not a static scalar. A static adjustment is a Critical
     finding: it confounds improving death registration with incidence/detection
     trends.
   - the **detection sub-model** includes the **GeneXpert** (Xpert MTB/RIF)
     time-varying covariate (state-month share-among-notified), and there is **no
     GeneXpert term on the mortality side**.
   - the model is fit **per state** (no joint hierarchical pooling across states,
     which did not converge) and there is **no municipality/BYM2 spatial
     structure** (out of scope). Flag any of these as deviations; the papers are
     the source of truth, not invented alternatives.

2. **Identifiability via the informative priors.** Confirm the load-bearing
   natural-history priors from the 2025 supplement (Table S2) are present at the
   stated values (survival without treatment `mu`; Pr(death | undiagnosed)
   `~ Beta(113, 87)`; Pr(death | lost to follow-up) `~ Beta(10, 190)`; incidence
   intercept/slope `~ Normal(0, 10)`; detection intercept/slope `~ Normal(0, 1)`;
   the death-reporting adjustment, generalised to time-varying), checked against
   `literature/notes/priors.md`. These priors are what makes incidence and the
   detection probability identifiable from notifications and deaths alone. Flag
   any prior that is weakened, widened, or removed as a change to the
   identification strategy, and check whether the model is still identified.

3. **Non-centred temporal parameterisation.** The smooth-trend knot values
   (RW2/spline), seasonal terms, and the death-adjustment effects must use
   non-centred parameterisations. There is NO BYM2/ICAR spatial structure here
   (that is the out-of-scope municipality burden-mapping model). Flag a naive
   centred RW2/spline that will struggle on a 252-month series.

4. **Constraints and types.** Check declared bounds and types: probabilities in
   `[0,1]`, scales positive, counts as integer data, rates positive. Confirm the
   `inv_logit`/`exp` links keep the detection probability in `[0,1]` and the
   incidence rate positive.

5. **Generated quantities match the data-generating process.** Posterior
   predictive draws must be generated from the same likelihood as the model
   block (same person-time offset, incidence, detection, and time-varying death
   structure). The generated incidence rate and detection probability must be the
   same quantities the simulator uses and that are written to the output object.

6. **R simulator <-> Stan model agreement.** The simulator in
   `code/01_functions/simulate.R` must draw from the same monthly process the base
   Stan model assumes (same delay-convolution structure, same time-varying
   death-reporting adjustment, same role for detection and the GeneXpert
   covariate). Disagreement here invalidates the recovery test; flag it.

7. **prior_only switch.** The base model must support a `prior_only` mode for
   prior predictive checks that disables the likelihood without changing the
   priors.

## Severity guidance

- **Critical/High**: likelihood does not match the spec, a load-bearing prior
  weakened or missing, centred parameterisation on a term known to fail, simulator
  and Stan model disagree, generated quantities not matching the likelihood.
- **Medium/Low**: missing prior_only switch where checks are not yet wired,
  unclear constraints that are nonetheless correct, style.

Convergence problems (divergences, R-hat > 1.01, low ESS) and any Critical/High
finding from this reviewer mean the phase is **Needs work.**

## Output format

Findings ranked Critical > High > Medium > Low, each with file:line, the issue,
why it matters for fidelity or identifiability, and a concrete fix.
