# Reviewer design doc: reproducibility

Source of truth for the `reproducibility` subagent. Keep them in sync.

## Mandate

Verify that the analysis is reproducible end to end: every stochastic step is
seeded, paths are relative, there is no hidden global state, dependencies and the
cmdstan version are pinned, and everything in `outputs/` is regenerable. Read
only.

## What to check

1. **Seeds, including cmdstanr.** Every stochastic step must be seeded: the
   simulator, any sampling for synthetic data, and the cmdstanr fit (the `seed`
   argument to `$sample()`). A single global seed should be defined in
   `config.R` and used consistently. Flag any `sample()`, `rnorm()`, `runif()`,
   or fit call without a seed.

2. **Relative paths.** All paths go through `here::here()` with the repo root as
   project root. Flag absolute paths, `setwd()`, and paths relative to the
   current working directory.

3. **No hidden global state.** Functions in the stage folders must be free of
   side effects; reading, writing, and calling belong in scripts and
   `_targets.R`. Flag functions that read or write files, mutate options, or
   depend on objects from the global environment.

4. **renv and cmdstan pinning.** Dependencies pinned with renv
   (`renv.lock` present and not casually modified). The cmdstan version must be
   recorded with the fit. Flag missing pins, library code loaded outside renv,
   or an unrecorded cmdstan version.

5. **Regenerability of outputs/.** Everything under `outputs/` must be
   reproducible from code plus inputs; only `.gitkeep` is tracked. Nothing in
   `outputs/` should be edited by hand or required as a non-regenerable input.
   `data/raw` is read only. Check the pipeline can regenerate outputs from a
   clean state.

## Severity guidance

- **Critical/High**: unseeded stochastic step (especially the cmdstanr fit),
  absolute paths or `setwd()`, side-effecting "pure" functions, unrecorded
  cmdstan version, outputs that cannot be regenerated or are hand-edited.
- **Medium/Low**: inconsistent but harmless path handling, minor unpinned dev
  tooling, documentation gaps.

Any Critical/High finding from this reviewer means the phase is **Needs work.**

## Output format

Findings ranked Critical > High > Medium > Low, each with file:line, the issue,
the reproducibility risk, and a concrete fix.
