# Reviewer design doc: stan_model_review

Source of truth for the `stan_model_review` subagent. Keep them in sync.

## Mandate

Verify that the Stan models faithfully implement the Chitwood evidence-synthesis
structure, that the model is identified by its informative priors, that
parameterisations are sound, and that the R simulator and the Stan model agree.
Read only: inspect and report.

## What to check

1. **Fidelity to the evidence-synthesis structure.** The base model must encode
   the two Poisson likelihoods exactly:
   - `Notifications[i,j] ~ Poisson( gamma * alpha * beta )`
   - `Deaths[i,j] ~ Poisson( gamma * alpha * { beta * P(death|treated)
     + (1-beta) * P(death|untreated) } * pi * rho )`
   with `alpha = exp(phi0 + state_time_effect + phi . X)`,
   `beta = inv_logit(omega0 + state_time_effect + omega . X)`, the area-level
   random effect plus random-walk year effect (demeaned area and year effects),
   `P(death|untreated) = 1 - mu`, `P(death|treated)` informed by SINAN
   treatment outcomes (deaths on treatment, and deaths among lost-to-follow-up
   governed by `delta`), and `rho` as a logit-linear function of the
   poorly-defined-cause fraction. Flag any deviation from this structure: the
   papers are the source of truth, not invented alternatives.

2. **Identifiability via the informative priors.** Confirm the load-bearing
   priors are present and at the stated values:
   `mu ~ Beta(25.65, 33.32)`, `delta ~ Beta(4.29, 81.47)`, death
   under-reporting anchors `A ~ Beta(52.97, 451.2)`, `B ~ Beta(97.83, 285.8)`,
   regression coefficients `~ Normal(0, 10)`, random-effect scales
   `~ half-Cauchy(0, 2)`, `theta0 ~ Normal(0,1)`, `theta2 ~ Normal(0,0.05)`,
   `theta3 ~ Normal(0,1)`. These priors are what makes incidence and the
   fraction treated identifiable from notifications and deaths alone. Flag any
   prior that is weakened, widened, or removed as a change to the identification
   strategy, and check whether the model is still identified without it.

3. **Non-centred and spatial parameterisation.** Hierarchical and spatial terms
   must use non-centred parameterisations. The municipality model should use a
   BYM2 / ICAR spatial structure on log incidence and the logit fraction
   treated, not a naive unstructured hierarchy (which fails to converge).

4. **Constraints and types.** Check declared bounds and types: probabilities in
   `[0,1]`, scales positive, counts as integer data, rates positive. Confirm
   `inv_logit`/`exp` links keep `beta` in `[0,1]` and `alpha` positive.

5. **Generated quantities match the data-generating process.** Posterior
   predictive draws must be generated from the same likelihood as the model
   block (same `gamma`, `alpha`, `beta`, death structure). Generated incidence
   rate and fraction treated must be the same quantities the simulator uses.

6. **R simulator <-> Stan model agreement.** The simulator in
   `code/01_functions/simulate.R` must draw from the same process the base Stan
   model assumes (same parameterisation of the death probability, same role for
   `pi` and `rho`). Disagreement here invalidates the recovery test; flag it.

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
