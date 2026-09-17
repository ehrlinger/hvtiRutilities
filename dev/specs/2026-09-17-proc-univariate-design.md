# Porting SAS `PROC UNIVARIATE` to `proc_univariate()`

**Date:** 2026-09-17
**Status:** Approved design, pending SAS oracle run and implementation plan
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
`OUT=`:

- `msign`, `probm`, `signrank`, `probs`, `normal`, `probn` when `weights` is
  given (SAS computes only the t test under `WEIGHT`);
- `t`, `probt` when `vardef` is not `"df"` (SAS requires `VARDEF=DF`);
- `normal`, `probn` when n > 2000, with one warning per call stating that SAS
  switches to a Kolmogorov D test there and that it is not ported;
- any statistic whose own minimum n is not met (as in `proc_means()`).

## Statistic definitions

Confidence tags: **documented** means confirmed in the SAS documentation;
**oracle** means the SAS run settles it before the implementation plan is
written.

| keyword | definition | confidence |
|---|---|---|
| unweighted quantiles | `stats::quantile(type = 2)`, SAS `PCTLDEF=5`, as `proc_means()` | documented behaviour; digits by oracle |
| weighted quantiles | Sort `x` ascending with weights `w`; `S_i` = cumulative weight, `W` = total. For fraction `p`: if `S_i = pW` for some `i`, the result is `(x_i + x_{i+1}) / 2`; otherwise `x_{i+1}` where `S_i < pW < S_{i+1}`. Endpoints: `p = 0` gives the minimum and `p = 1` the maximum (the equality branch at `i = n` has no `x_{n+1}`). Equal weights reduce to `type = 2`. `PCTLDEF=` does not apply. | rule documented, formula text not retrieved: **oracle** (endpoints: `pp_0`, `pp_100` in every weighted scenario) |
| `var`, `std`, `stderr`, `stdmean`, `cv` | CSS divided by `n - 1` (`df`), `n` (`n`), `sum(w) - 1` (`wdf`), `sum(w)` (`weight`); `stderr = std / sqrt(n)` under `df`, using the same divisor otherwise | divisors documented; `stderr`/`cv` under non-DF: **oracle** |
| `skewness`, `kurtosis` | as `proc_means()` (DF forms) regardless of `vardef` until the oracle shows otherwise | **oracle** |
| `t`, `probt` | `(xbar - mu0) / (s / sqrt(n))`; two-sided p from t with `n - 1` df. Weighted: weighted mean and weighted `s` | documented |
| `msign`, `probm` | drop `x == mu0`; `M = (n_plus - n_minus) / 2`; two-sided exact binomial p with `p = 0.5` on `n_plus + n_minus` trials, capped at 1 | documented; two-sided convention: **oracle** |
| `signrank`, `probs` | `d = x - mu0`, drop `d == 0`; ranks of `abs(d)` with average ranks for ties; `S = sum(sign(d) * rank) / 2`. n <= 20: exact two-sided p by enumerating all `2^n` sign assignments of the observed ranks. n > 20: t approximation with `n - 1` df using SAS's tie-corrected variance | rule documented; tie variance and exact-tail convention: **oracle** |
| `normal`, `probn` | Shapiro-Wilk W and p for 3 <= n <= 2000 via `stats::shapiro.test()` | documented; R implements Royston (1995), SAS cites Royston (1992): digits by **oracle** |
| `mode` | as `proc_means()`, unweighted | weighted behaviour: **oracle** |
| `nobs` under `weights` | SAS counts every observation read: `N + NMISS` plus those excluded for a missing or non-positive weight. `proc_means()` currently drops missing-weight rows before counting, so it reports fewer; `proc_univariate()` follows SAS, and the same fix to `proc_means()` is a follow-up | documented |

The exact signed-rank p-value is computed by enumeration, not
`stats::wilcox.test()`, which reports V rather than S and falls back to a
normal approximation with ties.

If the oracle contradicts a row, this table is corrected before the
implementation plan is written, not patched during implementation.

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
  value with `expect_equal(tolerance = 1e-10)`. A looser tolerance for a
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
