#' Summarise and test numeric variables, in the style of SAS PROC UNIVARIATE
#'
#' @description
#' Produces the statistics data set SAS `PROC UNIVARIATE` writes with
#' `OUTPUT OUT=`: one row per analysis variable (per class level), one
#' column per requested statistic in the order requested, then one column per
#' `PCTLPTS=` percentile. Beyond [proc_means()] it adds weighted
#' and decimal percentiles, `VARDEF=`, and the tests for location and
#' normality.
#'
#' @details
#' **Weighting.** Weights apply as in [proc_means()], except
#' that the quantiles are weighted: `median`, `q1`, `q3`,
#' `qrange`, `pNN` and the `pctlpts` columns. The weighted
#' percentile sorts the values with their cumulative weights \eqn{S_i}; the
#' 0th percentile is the minimum and the 100th the maximum; otherwise, when
#' \eqn{S_i = pW} the result is the mean of \eqn{x_i} and \eqn{x_{i+1}},
#' else the first \eqn{x_i} with \eqn{S_i > pW}. Unweighted quantiles use
#' `stats::quantile(type = 2)`, SAS's default `PCTLDEF=5`.
#' `mode` stays unweighted, as in SAS. `stderr` and `stdmean`
#' divide the standard deviation by the square root of the sum of the weights.
#' A zero or negative weight is an error; SAS instead treats a negative weight
#' as zero and still counts the observation.
#'
#' **VARDEF.** The variance divisor is \eqn{n - 1} (`"df"`),
#' \eqn{n} (`"n"`), \eqn{W - 1} (`"wdf"`) or \eqn{W}
#' (`"weight"`), where \eqn{W} is the sum of the weights (\eqn{n}
#' without weights). It changes `var`, `std` and `cv`. Under
#' `"n"`, `skewness` and `kurtosis` are the moment forms rather
#' than the adjusted ones.
#'
#' **Statistics SAS does not compute are NA**, as SAS writes missing:
#' \itemize{
#'   \item `msign`, `probm`, `signrank`, `probs`,
#'     `normal`, `probn` when `weights` is given;
#'   \item `t`, `probt`, `stderr` and `stdmean` when
#'     `vardef` is not `"df"`;
#'   \item `skewness` and `kurtosis` when `vardef` is
#'     `"wdf"` or `"weight"`;
#'   \item `normal` and `probn` above 2000 observations, with one
#'     warning per call: SAS switches to a Kolmogorov D test there, which is
#'     not ported;
#'   \item `std`, `var`, `cv`, `stderr`, `stdmean`,
#'     `t`, `probt` at one observation, `skewness` below three
#'     and `kurtosis` below four;
#'   \item `t`, `probt`, `skewness`, `kurtosis`,
#'     `normal`, `probn` when every value is equal (`cv` is
#'     then `0` unless the mean is zero, where it is `NA`);
#'   \item `msign`, `probm`, `signrank`, `probs` when no
#'     value differs from `mu0`;
#'   \item `mode` when no value repeats among two or more values.
#' }
#'
#' **Tests.** `t` is Student's t for the mean against `mu0`;
#' `msign` the sign statistic; `signrank` the Wilcoxon signed rank
#' statistic, with an exact p-value for 20 or fewer non-zero differences and
#' SAS's t approximation above that. `normal` is the Shapiro-Wilk
#' \eqn{W}, from `stats::shapiro.test()`, which implements Royston's 1995
#' algorithm; SAS implements Royston's 1992 one, so `normal` and
#' `probn` agree with SAS to about \eqn{10^{-8}}, not to machine
#' precision. At two observations both are `1`, as SAS reports.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param vars Character vector of columns to analyse. `NULL` (default)
#'   selects every numeric column not named in `class` or
#'   `weights`.
#' @param class Character vector of grouping columns, prepended to the result
#'   as leading columns. Rows with a missing value in any class variable are
#'   dropped, and levels follow `ORDER=INTERNAL`, as in
#'   [proc_means()]. Unlike `proc_means()`, a level whose
#'   every weight is missing has no row, as in SAS.
#' @param stats Character vector of SAS statistic keywords: every keyword
#'   [proc_means()] accepts, plus `"stdmean"`, `"t"`,
#'   `"probt"`, `"msign"`, `"probm"`, `"signrank"`,
#'   `"probs"`, `"normal"` and `"probn"`.
#' @param weights Character or `NULL`. Name of a single numeric column of
#'   `data` to use as an observation weight, SAS `WEIGHT`.
#'   Observations whose weight is missing are excluded from every statistic
#'   except `nobs`, which counts them.
#' @param pctlpts Numeric vector of percentile points in `[0, 100]`,
#'   decimals allowed, or `NULL`. SAS `PCTLPTS=`.
#' @param pctlpre Single string prefixed to the `pctlpts` column names.
#'   SAS `PCTLPRE=`. The point follows with `.` replaced by
#'   `_`, so `2.5` gives `p2_5`.
#' @param mu0 Single finite number, the null value for `t`,
#'   `msign` and `signrank`. SAS `MU0=`.
#' @param vardef The variance divisor: `"df"` (default), `"n"`,
#'   `"wdf"` or `"weight"`. SAS `VARDEF=`.
#'
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the `class` variables (when supplied), then
#'   `variable`, `label`, then one column per `stats` keyword in
#'   the order given, then one column per `pctlpts` point in the order
#'   given. `n`, `nmiss` and `nobs` are integer; all others are
#'   numeric.
#'
#' @seealso [proc_means()] for the descriptive statistics alone.
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # SAS unistats default statistics over every numeric variable
#' head(proc_univariate(dta))
#'
#' # Decimal percentiles, as for a bootstrap interval
#' proc_univariate(dta, vars = "age", stats = "n",
#'                 pctlpts = c(2.5, 50, 97.5))
#'
#' # Tests for location and normality
#' proc_univariate(dta, vars = "bmi",
#'                 stats = c("mean", "t", "probt", "normal", "probn"),
#'                 mu0 = 25)
proc_univariate <- function(data, vars = NULL, class = NULL,
                            stats = c("n", "median", "mean", "std", "cv",
                                      "min", "max"),
                            weights = NULL, pctlpts = NULL, pctlpre = "p",
                            mu0 = 0,
                            vardef = c("df", "n", "wdf", "weight")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats, "univariate")
  vardef <- match.arg(vardef)
  if (!is.numeric(mu0) || length(mu0) != 1L || !is.finite(mu0)) {
    stop("'mu0' must be a single finite number.", call. = FALSE)
  }
  pctl_names <- .pctl_names(pctlpts, pctlpre, c(stats, class))

  ctx <- .stat_ctx("univariate", vardef = vardef, mu0 = mu0)
  keywords <- c(stats, sprintf(".pctl:%.17g", pctlpts))
  out <- .summary_table(data, vars, class, keywords, weights, ctx,
                        col_names = c(stats, pctl_names))
  if (isTRUE(ctx$flags$normal_n2000)) {
    warning("'normal' and 'probn' are NA for analyses with more than 2000 ",
            "observations: SAS uses a Kolmogorov D test above 2000 ",
            "observations, which is not ported.", call. = FALSE)
  }
  out
}

## Internal: validate pctlpts and pctlpre and return the percentile column
## names. Each point is formatted on its own, so one decimal point does not
## give every name a decimal. `taken` lists the other output column names
## (stats and class) a generated name must not clash with.
.pctl_names <- function(pctlpts, pctlpre, taken) {
  if (!is.character(pctlpre) || length(pctlpre) != 1L || is.na(pctlpre) ||
        !nzchar(pctlpre)) {
    stop("'pctlpre' must be a single non-empty string.", call. = FALSE)
  }
  if (length(pctlpts) == 0L) {
    return(character())
  }
  if (!is.numeric(pctlpts)) {
    stop("'pctlpts' must be numeric.", call. = FALSE)
  }
  if (anyNA(pctlpts)) {
    stop("'pctlpts' must not contain NA.", call. = FALSE)
  }
  if (any(pctlpts < 0 | pctlpts > 100)) {
    stop("'pctlpts' must lie in [0, 100]; got: ",
         paste(pctlpts[pctlpts < 0 | pctlpts > 100], collapse = ", "),
         call. = FALSE)
  }
  if (anyDuplicated(pctlpts)) {
    stop("'pctlpts' has duplicated point(s): ",
         paste(unique(pctlpts[duplicated(pctlpts)]), collapse = ", "),
         call. = FALSE)
  }
  pts <- vapply(pctlpts, function(p) {
    format(p, digits = 15, scientific = FALSE, drop0trailing = TRUE,
           trim = TRUE)
  }, character(1))
  nms <- paste0(pctlpre, gsub(".", "_", pts, fixed = TRUE))
  clash <- nms[nms %in% taken | duplicated(nms)]
  if (length(clash) > 0L) {
    stop("Percentile column name(s) duplicate another output column: ",
         paste(unique(clash), collapse = ", "), call. = FALSE)
  }
  nms
}
