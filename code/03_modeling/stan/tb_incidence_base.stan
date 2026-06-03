// tb_incidence_base.stan
// Annual evidence-synthesis core (Chitwood 2021). Implemented in Phase 4.
//
// Two Poisson likelihoods for municipality i, year j with population gamma,
// incidence rate alpha, fraction treated beta:
//   Notifications[i,j] ~ Poisson( gamma * alpha * beta )
//   Deaths[i,j]        ~ Poisson( gamma * alpha *
//       { beta * P(death|treated) + (1-beta) * P(death|untreated) } * pi * rho )
// with alpha = exp(phi0 + state_time_effect + phi . X),
//      beta  = inv_logit(omega0 + state_time_effect + omega . X),
// informative priors on delta, mu, pi, rho (load bearing), a prior_only switch,
// and generated quantities for posterior predictive checks plus alpha and beta.
