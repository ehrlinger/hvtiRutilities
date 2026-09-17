# SAS check: a class level whose every weight is missing

Run on SAS 9.4 M8 (`lri-sas-p-02`, 2026-09-17) with inline synthetic data:
level `x` has weights, and every weight in level `y` is missing.

- `class_allmissing_weight_means.sas` (`PROC MEANS`, printed table via ODS
  and `OUTPUT OUT=`): level `y` is kept, with N = 0, NMISS = 0 and
  `_FREQ_` = 2. See `out/class_allmiss_means_printed.csv` and
  `out/class_allmiss_means_out.csv`.
- `class_allmissing_weight.sas` (`PROC UNIVARIATE`): level `y` is dropped.
  See `out/class_allmiss_univ.csv`. Its `PROC MEANS` step failed, because
  `PROC MEANS` has no `NOBS` keyword on the `OUTPUT` statement; the first
  script above replaces it.

`proc_means()` follows `PROC MEANS` and keeps the level, pinned in
`tests/testthat/test-proc_means_weights.R`.
