# Real-data convergence: dense_e rejected, ship diag_e, launch 27

Date: 2026-06-10. Continues 2026-06-05-real-data-convergence-basis-centering.md.
After the orthonormalised trend basis fixed the worst of the geometry, the
São Paulo (uf 35) fit on the full 252-month series still saturated max treedepth.
This log records the investigation, the decision to ship the diagonal metric, and
the 27-state launch setup.

## The problem

SP, diag_e, 4000 warmup + 1000 sampling, adapt_delta 0.95:
- max R-hat 1.01, min bulk ESS ~360-440 (usable), 14 divergences (0.4%)
- **3984/4000 (100%) transitions hit max treedepth 12** -> ~73 min/chain, every
  trajectory maxed at 2^12 leapfrog steps.

## What we tried

1. **Reparameterise trend <-> COVID.** Decorrelated the spline trend from the
   COVID step/ramp in build_design (orthogonalise the TREND against the clean,
   mean-centred COVID columns -- the reverse direction makes covid_level a ringing
   artefact and destroys COVID-window recovery; the recovery test caught that).
   Result on SP: divergences 82->14, but **treedepth stayed 100%.** So
   trend<->COVID was a real correlation but not the dominant one. Recovery test
   still 16/16, so the reparam is safe and stays.

2. **Dense mass matrix (dense_e), 6000 warmup.** Rejected:
   - treedepth fell to 46%, BUT max R-hat 1.08, **min bulk ESS 35**, 47 divergences.
   - i.e. it wrecked mixing. A dense metric assumes a roughly Gaussian posterior
     and rescales it once, globally; it fails here because the residual ridge is
     CURVED (exp + inv_logit + convolution make the incidence/detection tradeoff
     nonlinear). No global metric fixes a curved degeneracy.

| metric | warmup | divergences | treedepth | max R-hat | min bulk ESS |
|--------|--------|-------------|-----------|-----------|--------------|
| diag_e | 4000   | 14          | 100%      | 1.01      | ~360         |
| dense_e| 6000   | 47          | 46%       | **1.08**  | **35**       |

## Diagnosis

The remaining ridge is the **incidence <-> detection LEVEL / death-channel
degeneracy**, not a sampler-metric issue. Notifications pin only the PRODUCT
(detection x convolved incidence); the split is identified only by the sparse
deaths plus the informative priors -- the project's founding premise. The
detection trend prior is already tightened (trend_sd_det = half-N(0, 0.15)), so
the obvious prior lever is spent; the wide inc_intercept ~ N(0,10) level rides
against the detection level and the death-adjustment params along a curved ridge.

A reparameterisation can only make the sampler traverse an intrinsic degeneracy
more efficiently; it cannot add information. dense_e showed the metric is not the
lever.

## Decision (PI choice 2026-06-10): ship diag_e, launch 27

diag_e produces VALID draws (estimand R-hat ~1.01). The 100% treedepth is the
sampler taking long-but-legitimate paths along the intrinsic ridge -- slow, not
wrong. So:

- **Production config:** diag_e, 4000 warmup + 2000 sampling (2x to lift ESS off
  the ridge), adapt_delta 0.95, max_treedepth 12, 4 chains. Per state ~1-2 h.
- **Pass/fail on the ESTIMANDS, not the nuisance scalars.** fit_base_model now
  reports max_rhat_estimand / min_ess_bulk_estimand over incidence_rate /
  detection. A state is OK if estimand R-hat <= 1.01 and estimand bulk ESS >= 400;
  slow inc_intercept / death-channel scalars and treedepth saturation are
  expected and tolerated.
- **Runners:** code/03_modeling/02_fit_all_states.R (sequential, canonical config
  + convergence_summary.csv) and code/00_chpc_scripts/fit_all_states.slurm (SLURM
  array, one state/task; submit 00_precompile_model.R first so tasks don't race on
  compilation).

## Caveat / what would change this

If any state's ESTIMANDS (not just nuisance scalars) come back with R-hat > 1.01
or low ESS in the convergence summary, that state needs the model-level reparam of
the level/death-channel ridge (deferred: open-ended, touches estimands and the
load-bearing death-channel priors). The summary surfaces WARN states first for
exactly this triage. The reduced-amplitude treedepth (FAST/td) is not pursued; it
is slower without adding validity.

## Tests
- test-convergence-summary.R: convergence_row OK/WARN logic + collation ordering.
- recovery test remains 16/16 with the trend<->COVID reparam in place.
