# simulate.R
# Generative simulator for the annual evidence-synthesis process (Chitwood 2021),
# the same data-generating process the base Stan model (tb_incidence_base.stan)
# assumes. Backbone of the recovery test and of data/synthetic/.
#
# Side-effect free: no file I/O, no global RNG state (seeds are scoped with
# withr::with_seed). Scripts and _targets.R do the reading, writing, and calling.
#
# Likelihood, for municipality i and year j (population gamma = person-time,
# incidence rate alpha, fraction treated beta):
#
#   Notifications ~ Poisson( gamma * alpha * beta )
#   Deaths        ~ Poisson( gamma * alpha *
#       { beta * P(death|treated) + (1 - beta) * P(death|untreated) } * pi * rho )
#
# with
#   P(death|untreated) = 1 - mu                       (mu = survival untreated)
#   P(death|treated)   = p_death_tx + p_ltfu * delta  (SINAN treatment outcomes,
#                        deaths among the lost-to-follow-up governed by delta)
#   pi  = SIM mortality-system coverage
#   rho = adjustment for under-reporting of TB deaths
#
# These natural-history parameters (delta, mu, pi, rho) are load bearing; the
# defaults below sit at the Chitwood 2021 prior means and must not be weakened
# silently. See code/03_modeling/priors.R and literature/notes/priors.md.

# --- Natural-history parameters --------------------------------------------

#' Build and validate the natural-history parameter set.
#'
#' Defaults are the Chitwood 2021 prior means. `p_death_tx` (deaths on
#' treatment) and `p_ltfu` (fraction lost to follow-up) stand in for the
#' SINAN-informed treatment outcomes; in the real model these vary by area and
#' time.
#'
#' @return A list with the inputs plus derived case-fatality ratios
#'   `cfr_treated` and `cfr_untreated`.
tb_natural_history <- function(mu = 0.435,      # Beta(25.65, 33.32) mean
                               delta = 0.050,    # Beta(4.29, 81.47) mean
                               p_death_tx = 0.050,
                               p_ltfu = 0.100,
                               pi = 0.900,       # SIM coverage
                               rho = 0.850) {    # death under-reporting adj.
  probs <- c(mu = mu, delta = delta, p_death_tx = p_death_tx,
             p_ltfu = p_ltfu, pi = pi, rho = rho)
  if (any(!is.finite(probs)) || any(probs < 0) || any(probs > 1)) {
    stop("All natural-history parameters must be finite probabilities in [0, 1].")
  }
  cfr_treated   <- p_death_tx + p_ltfu * delta
  cfr_untreated <- 1 - mu
  if (cfr_treated > 1) {
    stop("Implied P(death | treated) exceeds 1; check p_death_tx, p_ltfu, delta.")
  }
  c(as.list(probs), list(cfr_treated = cfr_treated, cfr_untreated = cfr_untreated))
}

# --- Draw counts given rates (must match the Stan likelihood) ---------------

#' Draw notifications and deaths given known rates and natural history.
#'
#' This is the function that must stay identical to the Stan likelihood. Given
#' population (person-time), incidence rate alpha, and fraction treated beta, it
#' returns the expected means and one Poisson draw of each count.
#'
#' @param population Numeric vector, person-time denominator (gamma) > 0.
#' @param alpha Numeric vector, incidence rate per person-time, > 0.
#' @param beta Numeric vector, fraction treated, in [0, 1].
#' @param nat Natural-history list from `tb_natural_history()`.
#' @param seed Integer seed; RNG state is scoped, not set globally.
#' @return A data.table with rates, expected means, and the integer draws.
simulate_tb_counts <- function(population, alpha, beta,
                               nat = tb_natural_history(), seed = 1L) {
  n <- length(population)
  if (length(alpha) != n || length(beta) != n) {
    stop("population, alpha, and beta must have the same length.")
  }
  if (any(!is.finite(population)) || any(population <= 0)) {
    stop("population must be finite and positive.")
  }
  if (any(!is.finite(alpha)) || any(alpha <= 0)) {
    stop("alpha must be finite and positive.")
  }
  if (any(!is.finite(beta)) || any(beta < 0) || any(beta > 1)) {
    stop("beta must be in [0, 1].")
  }

  death_per_case <- beta * nat$cfr_treated + (1 - beta) * nat$cfr_untreated
  notif_mean <- population * alpha * beta
  death_mean <- population * alpha * death_per_case * nat$pi * nat$rho

  draws <- withr::with_seed(seed, {
    list(
      notifications = stats::rpois(n, notif_mean),
      deaths        = stats::rpois(n, death_mean)
    )
  })

  data.table::data.table(
    population     = population,
    alpha          = alpha,
    beta           = beta,
    death_per_case = death_per_case,
    notif_mean     = notif_mean,
    death_mean     = death_mean,
    notifications  = draws$notifications,
    deaths         = draws$deaths
  )
}

# --- Generate a full hierarchical synthetic dataset -------------------------

#' Simulate a municipality-by-year TB dataset from the evidence-synthesis model.
#'
#' Builds the area-time structure the base model assumes:
#'   log alpha = phi0  + u_i + w_j + X %*% phi   (incidence rate)
#'   logit beta = omega0 + v_i + s_j + X %*% omega (fraction treated)
#' with demeaned area effects (u_i, v_i) and demeaned random-walk year effects
#' (w_j, s_j), and area-level covariates X (standardised FHS coverage and log
#' GDP per capita). Then draws counts via `simulate_tb_counts()`.
#'
#' Returns both the observable `data` and the `truth` (true alpha, beta, and the
#' parameters) so the recovery test can check interval coverage.
#'
#' @param n_areas Number of municipalities.
#' @param n_years Number of years.
#' @param phi0,omega0 Intercepts for log incidence and logit fraction treated.
#' @param phi,omega Length-2 covariate coefficient vectors (FHS, log GDP).
#' @param sigma_area_alpha,sigma_area_beta Area random-effect SDs.
#' @param sigma_rw_alpha,sigma_rw_beta Year random-walk step SDs.
#' @param nat Natural-history list from `tb_natural_history()`.
#' @param pop_meanlog,pop_sdlog Lognormal parameters for area population.
#' @param seed Integer seed (scoped).
simulate_tb_dataset <- function(n_areas = 100L, n_years = 5L,
                                phi0 = -7.8, omega0 = 1.7,
                                phi = c(-0.10, -0.15),
                                omega = c(0.20, 0.10),
                                sigma_area_alpha = 0.30,
                                sigma_area_beta = 0.25,
                                sigma_rw_alpha = 0.05,
                                sigma_rw_beta = 0.05,
                                nat = tb_natural_history(),
                                pop_meanlog = 10.0, pop_sdlog = 1.0,
                                seed = 1L) {
  if (n_areas < 1L || n_years < 1L) stop("n_areas and n_years must be >= 1.")
  if (length(phi) != 2L || length(omega) != 2L) {
    stop("phi and omega must each be length 2 (FHS coverage, log GDP).")
  }

  built <- withr::with_seed(seed, {
    # Area-level covariates (standardised) and population.
    X <- cbind(fhs = stats::rnorm(n_areas), log_gdp = stats::rnorm(n_areas))
    population_area <- stats::rlnorm(n_areas, meanlog = pop_meanlog,
                                     sdlog = pop_sdlog)

    # Demeaned area random effects.
    u <- stats::rnorm(n_areas, sd = sigma_area_alpha); u <- u - mean(u)
    v <- stats::rnorm(n_areas, sd = sigma_area_beta);  v <- v - mean(v)

    # Random-walk year effects, demeaned.
    rw <- function(sd) {
      e <- cumsum(c(0, stats::rnorm(n_years - 1L, sd = sd)))
      e - mean(e)
    }
    w <- rw(sigma_rw_alpha)
    s <- rw(sigma_rw_beta)
    list(X = X, population_area = population_area, u = u, v = v, w = w, s = s)
  })

  grid <- data.table::CJ(area = seq_len(n_areas), year = seq_len(n_years))
  data.table::set(grid, j = "fhs",     value = built$X[grid$area, "fhs"])
  data.table::set(grid, j = "log_gdp", value = built$X[grid$area, "log_gdp"])
  data.table::set(grid, j = "population",
                  value = built$population_area[grid$area])

  lin_alpha <- phi0 + built$u[grid$area] + built$w[grid$year] +
    built$X[grid$area, "fhs"] * phi[1] + built$X[grid$area, "log_gdp"] * phi[2]
  lin_beta <- omega0 + built$v[grid$area] + built$s[grid$year] +
    built$X[grid$area, "fhs"] * omega[1] + built$X[grid$area, "log_gdp"] * omega[2]

  alpha <- exp(lin_alpha)
  beta  <- stats::plogis(lin_beta)

  # Use a derived seed so the count draws are reproducible but distinct from the
  # structure draws.
  counts <- simulate_tb_counts(grid$population, alpha, beta, nat = nat,
                               seed = seed + 1L)

  data <- data.table::data.table(
    area          = grid$area,
    year          = grid$year,
    population    = grid$population,
    fhs           = grid$fhs,
    log_gdp       = grid$log_gdp,
    notifications = counts$notifications,
    deaths        = counts$deaths
  )

  truth <- list(
    alpha = alpha, beta = beta,
    phi0 = phi0, omega0 = omega0, phi = phi, omega = omega,
    sigma_area_alpha = sigma_area_alpha, sigma_area_beta = sigma_area_beta,
    sigma_rw_alpha = sigma_rw_alpha, sigma_rw_beta = sigma_rw_beta,
    nat = nat,
    notif_mean = counts$notif_mean, death_mean = counts$death_mean
  )

  list(data = data, truth = truth)
}
