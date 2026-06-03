---
description: Run all five reviewer subagents in parallel, rank findings, and return an overall verdict.
---

Run a full review of the current state of the project (or the current diff, if
there is one). Launch all five reviewer subagents in parallel, in a single
message with multiple Agent tool calls, so they run concurrently:

- `data_integrity`
- `stan_model_review`
- `epidemiology_review`
- `testing`
- `reproducibility`

Each reviewer's design spec is in `prompts/` and its operational definition in
`.claude/agents/`. Give each the same scope: review the whole repo, or if a diff
or specific change is in play, focus there and say so.

When all five return, consolidate:

1. **Collect every finding** and rank across all reviewers by severity:
   Critical > High > Medium > Low. De-duplicate findings that more than one
   reviewer raised, noting which reviewers agreed.

2. **Run the fast tests** if they exist (e.g. via `make test` or the testthat
   entry point) and record pass/fail. Note any divergences, R-hat > 1.01, or low
   ESS reported by the recovery/diagnostic steps if they were run.

3. **Decide the overall verdict:**
   - **Needs work** if there are any failing tests, divergences,
     non-convergence (R-hat > 1.01 or inadequate ESS), or any Critical or High
     finding from the `stan_model_review`, `epidemiology_review`, or
     `reproducibility` reviewers.
   - **Needs attention** if there are Critical/High findings only from
     `data_integrity` or `testing`, or a cluster of Medium findings worth
     resolving before moving on.
   - **Ready** if nothing above Low is outstanding and tests pass.

4. **Report**: lead with the verdict, then the ranked findings grouped by
   severity, each with reviewer, file:line, the issue, and the recommended fix.
   End with the shortlist of Critical/High items that must be resolved before the
   current phase can be declared done.

5. **Log** a dated summary of this review (reviewers run, findings by severity,
   verdict, resolutions) to `agent_reviews/`.

Do not fix anything as part of the review itself; report and let the user decide,
unless they explicitly asked the review to also fix.
