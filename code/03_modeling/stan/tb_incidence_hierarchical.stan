// tb_incidence_hierarchical.stan
// Spatial-pooling extension (Chitwood 2022 precedent). Implemented in Phase 5+.
//
// BYM2 / ICAR structure on log incidence and on the logit fraction treated, with
// non-centred parameterisations throughout. Default for municipalities, where
// counts are sparse and a naive unstructured hierarchy fails to converge. Treat
// convergence trouble as a modelling signal: reparameterise, do not just raise
// adapt_delta.
