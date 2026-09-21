# Task 2 report: explicit cohort helpers

## RED

Command:

```text
Rscript -e 'devtools::test(filter = "study_cohort")'
```

Result before implementation: expected failure. The new tests reached the old
functions and failed with `unused arguments (event = ..., time = ...)` (and an
unused positional argument for `assert_cohort()`), confirming the tests covered
the signature change.

## GREEN

Command:

```text
Rscript -e 'devtools::test(filter = "study_cohort")'
```

Result after implementation:

```text
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]
```

The helpers now validate scalar event/time names, reject non-binary observed
event codes, count complete rows with integer results (including all-missing
zero counts), and compare against explicit job-level expectations.

Documentation was regenerated with:

```text
Rscript -e 'devtools::document()'
```

## Full suite

Command:

```text
Rscript -e 'devtools::test()'
```

Result: failed outside this task. The first unrelated failure was
`test-cache_fit.R:247` because the worktree's in-progress endpoint-neutral
contract changes leave the study cohort contract unavailable. The
`test-data_updates.R` tests also fail during fixture setup because the
worktree's in-progress `register_data()` changes reject the current helper
arguments. The focused cohort tests remained green.

## Files

- `R/study_cohort.R`
- `tests/testthat/test-study_cohort.R`
- `man/cohort_counts.Rd`
- `man/assert_cohort.Rd`

## Self-review

- The public signatures are exactly `cohort_counts(d, event, time)` and
  `assert_cohort(d, expected, event, time)`.
- Event coding is checked only after missing event/time rows are excluded;
  observed codes must be logical or numeric 0/1.
- Expected counts are validated as finite, nonnegative integer-valued scalars,
  and their total is checked for consistency before comparing observed counts.
- Error paths use `call. = FALSE` and retain the expected/observed mismatch
  message needed by callers.

## Concerns

The full suite cannot be green until the parallel endpoint-neutral contract
work updates its remaining internal callers and fixture helpers. Those changes
are outside this task's scope.
