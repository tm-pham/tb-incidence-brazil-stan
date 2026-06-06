# Real-data convergence: trend<->intercept ridge, fixed by centering the basis

Date: 2026-06-05. The first real-data fit (SP, uf 35, FAST settings) compiled and
sampled but did NOT converge: max R-hat 1.2, min ESS ~17, 0 divergences. A 0-
divergence + very-low-ESS + high-R-hat pattern points to a flat ridge, not short
warmup.

## Diagnosis (from the saved fit, no re-run)
fit$summary() ranked by R-hat showed the worst mixing on the spline trend
coefficients and the intercepts:
  theta_time 1.20; beta_trend_inc[6..11] 1.09-1.16; covid_det_level 1.15;
  sigma_season_det 1.12; det_intercept 1.09; beta_trend_det[*] 1.05-1.08;
  theta0 1.07; inc_intercept 1.05.
The later beta_trend coefficients being worst is the tell: the B-spline trend has
no level constraint, so the overall level is shared between the intercept and the
(RW cumulative-sum) spline coefficients -- a flat direction HMC cannot traverse.

## Fix
Mean-center the trend and seasonal basis columns (code/01_functions/basis.R) so
the fitted B %*% beta has mean ~0: the intercept carries the level, the spline
carries only deviations. This is a reparameterisation -- the representable fit
space is unchanged -- so it preserves the model's meaning and the recovery test
should still pass. Shared by the simulator and Stan via build_design(), so the
two stay in agreement (forward test).

## To confirm (needs cmdstan, on the user's machine)
1. Re-run the recovery test (RUN_RECOVERY_TEST=1) -- centering must not break
   recovery.
2. Re-run the SP fit (full settings) -- check R-hat < 1.01 and ESS climb.
If theta_time / covid_det_level still mix poorly after centering, the next levers
are: fewer spline knots (less flexibility competing with the COVID and death-adj
terms), or QR-orthogonalising the trend+seasonal design.

## Update: centering alone insufficient -> orthonormalise (QR)

A full real fit (SP, 4000 warmup, 2.4 h) showed the same R-hat 1.2 / ESS 17 AND
100% of transitions hitting max treedepth. Two findings:
- A footgun: the if(!exists()) source guards I had added meant an interactive
  session that already had the functions loaded did NOT reload the updated
  basis.R, so that run silently used the OLD uncentered basis. Guards removed
  (source unconditionally; the files are side-effect free).
- 100% treedepth saturation indicates strongly correlated geometry beyond the
  intercept ridge -- the spline columns are correlated with each other.

Fix: trend_basis() now also ORTHONORMALISES the centred basis (qr.Q(qr(.))), and
the Stan trend coefficients become iid-normal (the coarse knots give the
smoothness; this replaces the RW penalty -- a deliberate trade for convergence,
still "a smooth trend on coarse knots" per CLAUDE.md). Orthonormal columns ->
decorrelated coefficients -> the treedepth/ESS pathology should clear. Shared by
simulator and Stan via build_design(); forward-agreement test still passes.

Validate (clean R session): recovery test (recompiles Stan, must still recover),
then SP FAST. If treedepth/ESS are healthy, proceed to the full fit / cluster.
