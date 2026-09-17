# SAS check for two `proc_means()` fixes

`means_stderr.sas` ran on SAS 9.4 M8 (`lri-sas-p-02`, 2026-09-17) against two
fixtures from the `proc_univariate()` oracle kit (`wt_frac`, `n1`; see
`dev/oracle/proc_univariate/fixtures/` on the `spec/proc-univariate` branch).
Its output is in `out/`:

- `means_wt_frac.csv`: weighted `PROC MEANS` `STDERR` is 1.54482859156832,
  which is `std / sqrt(sum(w))`. `proc_means()` gave `std / sqrt(n)`,
  1.811472.
- `means_n1.csv`: `PROC MEANS` reports `MODE = 3` for a single observation.
  `proc_means()` gave `NA`.

The values are frozen as literals in `tests/testthat/test-proc_means_weighted_values.R`
and `tests/testthat/test-proc_means_stats.R`.
