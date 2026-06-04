# Reviewer design doc: testing

Source of truth for the `testing` subagent. Keep them in sync.

## Mandate

Verify that the test suite exists and is the right shape: recovery tests that the
model can recover known parameters, invariant tests that catch silent
regressions, and reproducibility tests that pin determinism, with coverage
proportionate to risk. Read only.

## What to check

1. **Recovery tests.** There must be a gated recovery test (run on demand, since
   it samples) that simulates a state-month series with known incidence,
   detection probability, and natural-history parameters, fits the base model for
   one state, asserts the sampler is clean (no divergences, R-hat < 1.01, adequate
   ESS), and asserts the credible intervals cover the true incidence and detection
   probability over time. Check the assertions are meaningful, not trivially
   satisfiable, and that the trend/COVID-shock/seasonal and time-varying
   death-adjustment terms are exercised.

2. **Invariant tests.** Fast tests on side-effect-free functions: the simulator
   is reproducible given a seed, returns non-negative integer monthly counts with
   correct dimensions, and keeps the detection probability in `[0,1]`.
   Data-processing invariants (the state-month grid preserved, exclusions
   applied, non-negative counts, covariate fractions in `[0,1]`) should be tested
   where that code exists. The prior specifications in `priors.R` should be
   asserted against the documented 2025 values.

3. **Reproducibility tests.** Determinism is pinned: the same seed gives the same
   simulator output and the same fit. Tests must not depend on hidden global
   state or wall-clock/random state set elsewhere.

4. **Coverage proportionate to risk.** The load-bearing pieces (the simulator,
   the prior values, the Stan data assembly, the death/notification likelihood
   path) should be the best covered. Flag untested high-risk code and
   over-tested trivia.

5. **Test hygiene.** Fast tests separated from the gated sampling test so the
   default suite runs quickly. Seeds set inside tests. Clear failure messages.

## Severity guidance

- **Critical/High**: no recovery test for the base model, recovery test with
  vacuous assertions, untested simulator or prior values, tests that pass
  regardless of correctness, tests depending on hidden global state.
- **Medium/Low**: missing edge-case tests where core paths are covered, slow
  tests not gated, weak failure messages.

Failing tests mean the phase is **Needs work.**

## Output format

Findings ranked Critical > High > Medium > Low, each with file:line (or the
missing test), the gap, the risk it leaves uncovered, and the test to add.
