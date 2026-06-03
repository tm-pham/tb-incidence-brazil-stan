# Makefile: thin CLI over the targets pipeline and the test suite.
# All targets run from the repo root (where _targets.R lives).

R := Rscript

.PHONY: help test data fetch pipeline show

help:
	@echo "make test      - run the testthat suite"
	@echo "make data      - build the Stan data (fetch if needed, then assemble) -> outputs/"
	@echo "make fetch     - STEP 1 only: pull SINAN/SIM/IBGE -> data/interim/ (needs network)"
	@echo "make pipeline  - run the full targets pipeline (tar_make)"
	@echo "make show      - list outdated targets"

test:
	$(R) code/07_tests/testthat.R

# Build the municipality-by-year Stan data list. Triggers the networked fetch
# first if the data/interim/ cache is missing or stale.
data:
	$(R) -e 'targets::tar_make(names = "stan_data_file")'

# STEP 1 only: pull the raw sources to data/interim/ (needs DATASUS/IBGE access).
fetch:
	$(R) -e 'targets::tar_make(names = c("raw_notifications", "raw_deaths", "raw_population"))'

# Full pipeline (data processing now; modelling stages as they are added).
pipeline:
	$(R) -e 'targets::tar_make()'

show:
	$(R) -e 'print(targets::tar_outdated())'
