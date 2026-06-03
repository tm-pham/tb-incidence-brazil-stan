# simulate.R: generative simulator for the evidence-synthesis process.
# Implemented in Phase 3. Draws municipality notifications and deaths from the
# same data-generating process the base Stan model assumes, given known
# incidence, fraction treated, and natural-history parameters (delta, mu, pi,
# rho). Backbone of the recovery test and of data/synthetic/. Side-effect free.
