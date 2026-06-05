// tb_state_month.stan
// Monthly, single-state TB natural-history model (Chitwood 2025 structure +
// project extensions). Fit ONE state at a time (no joint hierarchy, no BYM2, no
// monthly AR-1 -- see CLAUDE.md). The data-generating process is mirrored exactly
// by code/01_functions/simulate.R; keep the two in sync.
//
// Latent series on an EXTENDED axis (N_pre pre-window months + N_obs observed):
//   lambda = exp(inc_intercept + B_trend b + S_season s + COVID)   // infections, per-capita
//   gamma  = conv(lambda, phi_lambda)                              // symptomatic ("incidence")
//   delta  = inv_logit(det_intercept + B_trend b + S_season s + COVID + genexpert)
//   detect = conv(gamma, phi_gamma)
//   Notified = delta .* detect ;  Missed = (1-delta) .* detect
//   DeadNotif = Notified .* (pri_mort + pri_aban * p_mort_aban)
//   AllDeaths = conv(DeadNotif, phi_mort) + conv(Missed * p_mort_nonotif, phi_mort)
//   DeathAdj  = inv_logit(theta0 + theta_time*year + theta_idc*idc)  // time-varying (our extension)
//   SINAN ~ Poisson(pop .* Notified_obs)
//   SIM   ~ Poisson(pop .* AllDeaths_obs .* DeathAdj)
//
// Trend is a penalised B-spline (RW1 prior on coefficients, non-centred);
// seasonal is a Fourier harmonic block; COVID is an explicit level+slope shock.
// Delay kernels and all prior hyperparameters are passed as data (single source:
// code/03_modeling/priors.R).

functions {
  // y[t] = sum_{j=1}^{min(K,t)} x[t-j+1] * kernel[j]  (kernel[1] = lag 0)
  vector causal_convolve(vector x, vector kernel) {
    int M = num_elements(x);
    int K = num_elements(kernel);
    vector[M] y = rep_vector(0, M);
    for (t in 1:M) {
      int kmax = min(K, t);
      for (j in 1:kmax) {
        y[t] += x[t - j + 1] * kernel[j];
      }
    }
    return y;
  }
}

data {
  int<lower=1> N_obs;
  int<lower=0> N_pre;
  int<lower=1> K_trend;          // B-spline columns
  int<lower=1> H2;               // seasonal columns (2 * n_harmonics)
  int<lower=1> L_lambda;
  int<lower=1> L_gamma;
  int<lower=1> L_mort;

  matrix[N_pre + N_obs, K_trend] B_trend;
  matrix[N_pre + N_obs, H2] S_season;
  vector[N_pre + N_obs] covid_level;
  vector[N_pre + N_obs] covid_slope;
  vector[N_pre + N_obs] genexpert_ext;   // pre-window = 0
  vector<lower=0, upper=1>[N_pre + N_obs] pri_mort_ext;
  vector<lower=0, upper=1>[N_pre + N_obs] pri_aban_ext;

  vector<lower=0, upper=1>[N_obs] idc;
  vector[N_obs] year_idx;                // years since start (for the death-adj trend)
  vector<lower=0>[N_obs] population;      // person-time offset
  array[N_obs] int<lower=0> sinan;        // notifications
  array[N_obs] int<lower=0> sim;          // TB deaths

  vector<lower=0>[L_lambda] phi_lambda;   // fixed delay kernels (sum to 1)
  vector<lower=0>[L_gamma] phi_gamma;
  vector<lower=0>[L_mort] phi_mort;

  // Prior hyperparameters (from priors.R).
  real<lower=0> inc_intercept_sd;
  real<lower=0> inc_coef_sd;
  real<lower=0> det_intercept_sd;
  real<lower=0> det_coef_sd;
  real<lower=0> trend_sd_inc;
  real<lower=0> trend_sd_det;
  real<lower=0> season_sd_inc;
  real<lower=0> season_sd_det;
  real<lower=0> genexpert_coef_sd;
  real<lower=0> theta0_sd;
  real<lower=0> theta_time_sd;
  real<lower=0> theta_idc_sd;
  real<lower=0> pmort_nonotif_a;
  real<lower=0> pmort_nonotif_b;
  real<lower=0> pmort_aban_a;
  real<lower=0> pmort_aban_b;
  real inc_intercept_mean;                // per-capita log-rate location (e.g. -9)
  real det_intercept_mean;                // logit-detection location (0 = 50% prior)

  int<lower=0, upper=1> prior_only;
}

transformed data {
  int N_total = N_pre + N_obs;
}

parameters {
  real inc_intercept;
  vector[K_trend] z_trend_inc;
  real<lower=0> sigma_trend_inc;
  vector[H2] z_season_inc;
  real<lower=0> sigma_season_inc;
  real covid_inc_level;
  real covid_inc_slope;

  real det_intercept;
  vector[K_trend] z_trend_det;
  real<lower=0> sigma_trend_det;
  vector[H2] z_season_det;
  real<lower=0> sigma_season_det;
  real covid_det_level;
  real covid_det_slope;
  real genexpert_coef;

  real theta0;
  real theta_time;
  real theta_idc;

  real<lower=0, upper=1> p_mort_aban;
  real<lower=0, upper=1> p_mort_nonotif;
}

transformed parameters {
  // Non-centred RW1 spline coefficients and seasonal coefficients.
  vector[K_trend] beta_trend_inc = cumulative_sum(z_trend_inc) * sigma_trend_inc;
  vector[K_trend] beta_trend_det = cumulative_sum(z_trend_det) * sigma_trend_det;
  vector[H2] beta_season_inc = z_season_inc * sigma_season_inc;
  vector[H2] beta_season_det = z_season_det * sigma_season_det;

  vector[N_total] lambda = exp(inc_intercept
      + B_trend * beta_trend_inc + S_season * beta_season_inc
      + covid_inc_level * covid_level + covid_inc_slope * covid_slope);
  vector[N_total] gamma = causal_convolve(lambda, phi_lambda);

  vector[N_total] delta = inv_logit(det_intercept
      + B_trend * beta_trend_det + S_season * beta_season_det
      + covid_det_level * covid_level + covid_det_slope * covid_slope
      + genexpert_coef * genexpert_ext);

  vector[N_total] detect = causal_convolve(gamma, phi_gamma);
  vector[N_total] notified = delta .* detect;
  vector[N_total] missed = (1 - delta) .* detect;
  vector[N_total] dead_notif = notified .* (pri_mort_ext + pri_aban_ext * p_mort_aban);
  vector[N_total] alldeaths = causal_convolve(dead_notif, phi_mort)
      + causal_convolve(missed * p_mort_nonotif, phi_mort);

  vector[N_obs] death_adj = inv_logit(theta0 + theta_time * year_idx + theta_idc * idc);
  vector[N_obs] exp_notif = population .* notified[(N_pre + 1):N_total];
  vector[N_obs] exp_deaths = population .* alldeaths[(N_pre + 1):N_total] .* death_adj;
}

model {
  // Priors.
  inc_intercept ~ normal(inc_intercept_mean, inc_intercept_sd);
  z_trend_inc ~ std_normal();
  sigma_trend_inc ~ normal(0, trend_sd_inc);
  z_season_inc ~ std_normal();
  sigma_season_inc ~ normal(0, season_sd_inc);
  covid_inc_level ~ normal(0, inc_coef_sd);
  covid_inc_slope ~ normal(0, inc_coef_sd);

  det_intercept ~ normal(det_intercept_mean, det_intercept_sd);
  z_trend_det ~ std_normal();
  sigma_trend_det ~ normal(0, trend_sd_det);
  z_season_det ~ std_normal();
  sigma_season_det ~ normal(0, season_sd_det);
  covid_det_level ~ normal(0, det_coef_sd);
  covid_det_slope ~ normal(0, det_coef_sd);
  genexpert_coef ~ normal(0, genexpert_coef_sd);

  theta0 ~ normal(0, theta0_sd);
  theta_time ~ normal(0, theta_time_sd);
  theta_idc ~ normal(0, theta_idc_sd);

  p_mort_aban ~ beta(pmort_aban_a, pmort_aban_b);
  p_mort_nonotif ~ beta(pmort_nonotif_a, pmort_nonotif_b);

  // Likelihood (Poisson; skip when doing a prior-predictive check).
  if (prior_only == 0) {
    sinan ~ poisson(exp_notif);
    sim ~ poisson(exp_deaths);
  }
}

generated quantities {
  // Estimands on the observed months: symptomatic incidence rate (per-capita)
  // and case-detection probability, plus posterior-predictive counts and the
  // pointwise log-likelihood.
  vector[N_obs] incidence_rate = gamma[(N_pre + 1):N_total];
  vector[N_obs] detection = delta[(N_pre + 1):N_total];
  array[N_obs] int sinan_rep = poisson_rng(exp_notif);
  array[N_obs] int sim_rep = poisson_rng(exp_deaths);
  vector[N_obs] log_lik;
  for (t in 1:N_obs) {
    log_lik[t] = poisson_lpmf(sinan[t] | exp_notif[t])
               + poisson_lpmf(sim[t] | exp_deaths[t]);
  }
}
