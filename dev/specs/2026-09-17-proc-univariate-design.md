# Porting SAS `PROC UNIVARIATE` to `proc_univariate()`

**Date:** 2026-09-17
**Status:** Approved design; SAS oracle results (2026-09-17) incorporated; pending implementation plan
**Package:** `hvtiRutilities`
**Predecessors:** `dev/specs/2026-08-14-proc-means-unistats-design.md`,
`dev/specs/2026-09-16-proc-freq-design.md`

## Context

`proc_means()` closed the descriptive half of the `unistats` vocabulary and
recorded that the rest, the inference statistics, belongs to a future
`proc_univariate()`. `proc_freq()` was the first of two follow-up ports; this
is the second.

A survey of the macro library (`~/Documents/macro.library`, 2026-09-17)
changes the emphasis:

- **No job calls `%unistats`.** The allocation manifest
  (`hvtiRtemplates/dev/specs/artifacts/2026-08-14-macro-allocation.json`)
  lists it as `corpus-only` with `needed_by: []`. It is a vocabulary
  reference, not a dependency.
- **27 files call `PROC UNIVARIATE` directly.** What they use:
  - `WEIGHT` (32 uses), with `VARDEF=WDF` in 8;
  - `OUTPUT PCTLPTS= PCTLPRE=` for arbitrary percentiles, often decimal
    (`2.5 16 50 84 97.5`, bootstrap intervals);
  - `NORMAL`/`PROBN` (14 uses);
  - plots (`PLOT`, `HISTOGRAM`, `QQPLOT`, 16 uses), out of scope here.

So the most common need is weighted and decimal percentiles, which
`proc_means()` cannot give: its `pNN` is integer-only and its quantiles are
unweighted, as in `PROC MEANS`.

## Scope

**In scope.** The `OUTPUT OUT=` statistics data set: every `proc_means()`
statistic; `STDMEAN`; `PCTLPTS=`/`PCTLPRE=` percentiles, including decimals;
weighted quantiles; `VARDEF=`; `MU0=`; the tests for location (`T`, `PROBT`,
`MSIGN`, `PROBM`, `SIGNRANK`, `PROBS`); the normality test (`NORMAL`,
`PROBN`).

**Out of scope.** The printed report tables; plots; `FREQ` statement; `ID`;
confidence limits (`CIBASIC`, `CIPCTLDF`, `CIPCTLNORMAL`); robust estimators
(`TRIMMED`, `WINSORIZED`, `ROBUSTSCALE`); `EXCLNPWGT`; `PCTLDEF=` other than
the default; the Kolmogorov D normality test used above n = 2000 (see below);
`WHERE=`/`BY=` (`subset()` and `class` at the call site).

## Interface

```r
proc_univariate(data, vars = NULL, class = NULL,
                stats = c("n", "median", "mean", "std", "cv", "min", "max"),
                weights = NULL, pctlpts = NULL, pctlpre = "p",
                mu0 = 0, vardef = c("df", "n", "wdf", "weight"))
```

| argument | meaning |
|---|---|
| `data`, `vars`, `class` | as `proc_means()`: `vars = NULL` analyses all numeric columns; `class` rows drop missing class values and follow `ORDER=INTERNAL` |
| `stats` | SAS keywords, output in the order given. Default is `unistats`' default |
| `weights` | `NULL` or one numeric column name, SAS `WEIGHT` |
| `pctlpts` | `NULL` or numeric percentile points in `[0, 100]`, decimals allowed, SAS `PCTLPTS=` |
| `pctlpre` | single string prefix for the `pctlpts` columns, SAS `PCTLPRE=` |
| `mu0` | single finite number, the null value for the location tests, SAS `MU0=` |
| `vardef` | variance divisor, SAS `VARDEF=` |

## Result

Same shape as `proc_means()`: leading `class` columns (when given), then
`variable` and `label`, then one column per `stats` keyword in order, then one
column per `pctlpts` point in order. One row per analysis variable, or per
analysis variable and class level.

**Keywords.** All `proc_means()` keywords, plus `stdmean` (equal to
`stderr`), `t`, `probt`, `msign`, `probm`, `signrank`, `probs`, `normal`,
`probn`. `proc_means()` does not gain the new keywords.

**Percentile column names** follow SAS: `pctlpre` followed by the point, with
`.` replaced by `_` and no trailing zeros (`2.5` gives `p2_5`, `50` gives
`p50`). A generated name that duplicates a `stats` column, or a duplicate
point, is an error.

**Weighting.** As `proc_means()`, except that quantiles are weighted:
`median`, `q1`, `q3`, `qrange`, `pNN` and `pctlpts` use the weighted
percentile definition below when `weights` is given. Non-positive weights are
an error and a missing weight drops the observation, as in `proc_means()` and
`proc_freq()`. SAS instead converts negative weights to zero and still counts
the observation; this is a deliberate, documented difference.

**Statistics SAS does not compute are `NA`**, as SAS writes missing to
`OUT=`. Every rule below was observed in the SAS oracle run:

- `msign`, `probm`, `signrank`, `probs`, `normal`, `probn` when `weights` is
  given (SAS computes only the t test under `WEIGHT`);
- `t`, `probt` and `stdmean` when `vardef` is not `"df"`;
- `skewness`, `kurtosis` when `vardef` is `"wdf"` or `"weight"`;
- `normal`, `probn` when n > 2000, with one warning per call stating that SAS
  switches to a Kolmogorov D test there and that it is not ported;
- `std`, `var`, `cv`, `stdmean`, `t`, `probt` at n = 1; `skewness` at n < 3;
  `kurtosis` at n < 4;
- `t`, `probt`, `skewness`, `kurtosis`, `normal`, `probn` when every value is
  equal (standard deviation 0). `cv` is `0` there, not `NA`, because the mean
  is not zero;
- `mode` when no value repeats (a constant column's mode is its value).

## Statistic definitions

Every row was checked against the SAS oracle run (SAS 9.4 M8,
`lri-sas-p-02`, 2026-09-17; outputs in `dev/oracle/proc_univariate/out/`).
`n` is the count of non-missing values, `W = sum(w)` (equal to `n` without
weights), `xbar` the weighted mean, `CSS = sum(w * (x - xbar)^2)`.

| keyword | definition | oracle |
|---|---|---|
| unweighted quantiles | `stats::quantile(type = 2)`, SAS `PCTLDEF=5`, as `proc_means()` | exact match |
| weighted quantiles | Sort `x` ascending with weights `w`; `S_i` = cumulative weight. For fraction `p`: `p = 0` gives the minimum, `p = 1` the maximum; otherwise, if `S_i = pW` for some `i`, the result is `(x_i + x_{i+1}) / 2`, else `x_i` for the first `i` with `S_i > pW`. `PCTLDEF=` does not apply | exact match, all 48 weighted values including `pp_0`, `pp_100` |
| `var`, `std`, `cv` | `var = CSS / d` with `d` = `n - 1` (`df`), `n` (`n`), `W - 1` (`wdf`), `W` (`weight`); `std = sqrt(var)`; `cv = 100 * std / xbar` | exact match, all four `vardef` |
| `stderr`, `stdmean` | `std / sqrt(W)` under `df`; `NA` otherwise | exact match; **`sqrt(W)`, not `sqrt(n)`** |
| `skewness`, `kurtosis` under `df` | `proc_means()`'s adjusted forms (weights raised to 3/2 and 2) | exact match, weighted and unweighted |
| `skewness`, `kurtosis` under `n` | moment forms with `s_n^2 = CSS / n` and `z = (x - xbar) / s_n`: `skewness = sum(w^1.5 * z^3) / n`, `kurtosis = sum(w^2 * z^4) / n - 3` | exact match, weighted and unweighted |
| `skewness`, `kurtosis` under `wdf`, `weight` | `NA` | observed |
| `t`, `probt` | `(xbar - mu0) / (std / sqrt(W))`; two-sided p from t with `n - 1` df | exact match, weighted and unweighted, `mu0` 0 and non-zero |
| `msign`, `probm` | drop `x == mu0`; `M = (n_plus - n_minus) / 2`; `p = min(1, 2 * pbinom(min(n_plus, n_minus), n_plus + n_minus, 0.5))` | exact match |
| `signrank`, `probs` | `d = x - mu0`, drop `d == 0`, `n` = count of non-zero `d`; average ranks `r` of `abs(d)`; `S = sum(sign(d) * r) / 2`. n <= 20: exact two-sided p, the probability that the absolute sign-rank sum is at least `abs(S)` over all `2^n` equally likely sign assignments of `r`. n > 20: `V = n(n+1)(2n+1)/24 - sum(t^3 - t)/48` over tie groups of size `t`; `T = S * sqrt((n - 1) / (n * V - S^2))`; two-sided p from t with `n - 1` df | exact match; the n <= 20 cutoff counts non-zero differences only (`n21_mu0`) |
| `normal`, `probn` | Shapiro-Wilk via `stats::shapiro.test()` for 3 <= n <= 2000; **`W = 1`, `p = 1` at n = 2**; `NA` at n = 1 | agrees to about 1e-8 (R Royston 1995, SAS Royston 1992); n = 2 observed |
| `mode` | as `proc_means()`, **unweighted even under `weights`** | observed (`wt_frac`: 2, not the weighted 0) |
| `nobs` under `weights` | `N + NMISS` plus rows excluded for a missing or non-positive weight; `proc_means()` does the same from #119 | documented |

Implementation note: enumerating `2^20` sign assignments as a matrix needs
about 160 MB. Compute the exact null distribution of `2 * S` instead, by
dynamic programming over doubled (integer) ranks.

### Findings for `proc_means()`

- **Weighted `skewness` and `kurtosis` are confirmed.** Its formulas, awaiting
  a SAS oracle since 2026-08-14, match SAS exactly.
- **Weighted `stderr` divides by `sqrt(n)`, SAS by `sqrt(W)`.** Fixed in
  `proc_means()` on its own branch, after confirming `PROC MEANS` documents
  the same formula.

## Architecture: a shared statistic engine

`proc_means()`'s registry was designed to be extracted "when
`proc_univariate()` gives it a second consumer" (2026-08-14 design). This is
that consumer.

- `R/stat_engine.R` receives `.STATS`, `.compute_stat()`,
  `.quantile_stat()` and the weighted helpers (`.wmean`, `.wvar`, `.wskew`,
  `.wkurt`), moved without behavioural change.
- An entry's `weighted` flag becomes per procedure:
  `weighted = c(means = FALSE, univariate = TRUE)` for the quantiles; other
  entries keep a single logical that applies to both.
- Each entry gains `procedures`, the procedures that accept the keyword. The
  new inference keywords and `stdmean` are `"univariate"` only, so
  `proc_means(stats = "t")` still errors.
- `.compute_stat(x, stat, w = NULL, procedure = "means", vardef = "df",
  mu0 = 0)`: the defaults keep `proc_means()` and `data_dictionary()`'s
  positional calls (`R/data_dictionary.R:88-90`) byte-identical.
- Percentile points are handled by a parameterised quantile path rather than
  one registry entry per point.

**The move lands as its own commit, before any new statistic**, and must pass
every existing `proc_means` test file unchanged. That is the evidence the
refactor changed nothing.

## Errors

All errors use `call. = FALSE` and name the offending input.

- Everything `proc_means()` rejects (non-data-frame, unknown or absent
  columns, non-numeric `vars`, bad `weights`, weight column also in `vars` or
  `class`, unknown keyword).
- `pctlpts` not numeric, containing `NA`, outside `[0, 100]`, or duplicated.
- `pctlpre` not a single non-empty string, or a generated percentile column
  name that duplicates a `stats` column.
- `mu0` not a single finite number.
- `vardef` not one of the four values (`match.arg`).

## SAS oracle

`dev/oracle/proc_univariate/` (under `dev/`, so excluded from the build):

- `make_fixtures.R` writes `fixtures/*.csv` (small synthetic CSVs, no PHI) and
  `scenarios.csv`, the manifest: one row per SAS run, giving `WEIGHT`,
  `VARDEF=`, `MU0=`, `CLASS`, and which tests are requested. The fixtures:
  `basic` (ties and values equal to `mu0`), `basic_w2` (equal weights),
  `wt_frac` (fractional weights), `wt_exact` (cumulative weights that hit
  `S_i = pW` exactly), `n1`, `n2` (minimum n), `n3`, `n4` (minimum n for
  skewness and kurtosis), `n20`, `n21` (either side of the exact
  signed-rank limit), `const` (a constant column), `allmiss` (an
  all-missing column), `skewed50`, `n2000`, `n2001` (bracket the
  Shapiro-Wilk limit), `class3` (three class levels plus a missing class
  value).
- `oracle.sas` reads `scenarios.csv` and generates one `PROC UNIVARIATE`
  run per row with `CALL EXECUTE`, requesting every keyword SAS is
  expected to compute for that scenario (`NORMAL` and the rank tests off
  under `WEIGHT`; `T` off under `VARDEF=` other than `DF`) in its `OUTPUT
  OUT=` statement, with `PCTLPTS= PCTLPRE=`. Two scenarios are
  optional: they deliberately request statistics the design expects SAS to
  refuse. It writes one CSV per scenario with numeric values formatted
  `BEST32.` so no precision is lost in transit.
- `check_oracle.R` gates the output: every required scenario present with
  the expected columns and row count, `sas_version.txt` present and
  non-empty, and a missing optional scenario or column reported as a note,
  not a failure.
- The maintainer runs `oracle.sas` on SAS 9.4, runs `check_oracle.R`, and
  commits `out/` (per-scenario CSVs, `sas_version.txt` with the SAS version
  and run date, `oracle.log`) to `dev/oracle/proc_univariate/out/`, on
  `spec/proc-univariate` if PR A is still open, otherwise on a follow-up
  branch. PR B copies the outputs and fixtures into
  `tests/testthat/fixtures/proc_univariate/`.

## Testing

Files by theme: `test-proc_univariate_shape.R`, `_quantiles.R`,
`_location.R`, `_normality.R`, `_vardef.R`, `_errors.R`, `_parity.R`.

- **Parity.** `_parity.R` reads each committed SAS output CSV (wherever it
  sits at PR B time, `tests/testthat/fixtures/proc_univariate/`), runs the
  matching `proc_univariate()` call on the same fixture, and compares every
  value with `expect_equal(tolerance = 1e-10)`, except `normal` and `probn`
  at `1e-7` (see the definitions table). A looser tolerance for a
  statistic is allowed only with a written reason in the test (the
  Shapiro-Wilk p-value is the expected candidate).
- **Hand-computed literals** pin each formula independently of SAS: weighted
  percentile at and between `S_i = pW`; sign test with values equal to `mu0`;
  signed rank with ties at n <= 20; each `vardef` divisor.
- **Refactor guard.** All existing `test-proc_means*.R` files pass unchanged
  after the engine move.
- **`NA` contracts.** Each "SAS does not compute" case above, and the n > 2000
  warning.

## Delivery

1. **PR A: this spec and the oracle kit.** Ships nothing (`dev/` only), so no
   NEWS entry. The maintainer runs `oracle.sas` from the branch, gates the
   output with `check_oracle.R`, and commits `out/` on `spec/proc-univariate`
   if PR A is still open, otherwise on a follow-up branch.
2. **Oracle review.** Contradictions with the definitions table are corrected
   in this spec, and only then is PR B's implementation plan written.
3. **PR B: implementation.** Engine move as its first commit; then
   `proc_univariate()`; parity tests with the committed SAS outputs; roxygen
   in Rd markup; `_pkgdown.yml`; a vignette section in
   `vignettes/sas-procedures.qmd`; NEWS under `# hvtiRutilities (unreleased)`.
   Done means `devtools::test()`, docs current, and `R CMD check` with the
   manual at 0/0/0 apart from the environmental "New submission" NOTE.

## Follow-up

- Extend the oracle kit to `proc_means()`'s weighted `skewness`/`kurtosis`
  (awaiting a SAS oracle since 2026-08-14) and to `proc_freq()`'s fixtures.
- `PCTLDEF=` 1 to 4, `CIBASIC`, robust estimators, and the Kolmogorov D test
  above n = 2000, if a job needs them.
