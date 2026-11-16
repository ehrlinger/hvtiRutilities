#' Summarise and test numeric variables, in the style of SAS PROC UNIVARIATE
#'
#' @description
#' Produces the statistics data set SAS \code{PROC UNIVARIATE} writes with
#' \code{OUTPUT OUT=}: one row per analysis variable (per class level), one
#' column per requested statistic in the order requested, then one column per
#' \code{PCTLPTS=} percentile. Beyond \code{\link{proc_means}} it adds weighted
#' and decimal percentiles, \code{VARDEF=}, and the tests for location and
#' normality.
#'
#' @details
#' \strong{Weighting.} Weights apply as in \code{\link{proc_means}}, except
#' that the quantiles are weighted: \code{median}, \code{q1}, \code{q3},
#' \code{qrange}, \code{pNN} and the \code{pctlpts} columns. The weighted
#' percentile sorts the values with their cumulative weights \eqn{S_i}; the
#' 0th percentile is the minimum and the 100th the maximum; otherwise, when
#' \eqn{S_i = pW} the result is the mean of \eqn{x_i} and \eqn{x_{i+1}},
#' else the first \eqn{x_i} with \eqn{S_i > pW}. Unweighted quantiles use
#' \code{stats::quantile(type = 2)}, SAS's default \code{PCTLDEF=5}.
#' \code{mode} stays unweighted, as in SAS. \code{stderr} and \code{stdmean}
#' divide the standard deviation by the square root of the sum of the weights.
#' A zero or negative weight is an error; SAS instead treats a negative weight
#' as zero and still counts the observation.
#'
#' \strong{VARDEF.} The variance divisor is \eqn{n - 1} (\code{"df"}),
#' \eqn{n} (\code{"n"}), \eqn{W - 1} (\code{"wdf"}) or \eqn{W}
#' (\code{"weight"}), where \eqn{W} is the sum of the weights (\eqn{n}
#' without weights). It changes \code{var}, \code{std} and \code{cv}. Under
#' \code{"n"}, \code{skewness} and \code{kurtosis} are the moment forms rather
#' than the adjusted ones.
#'
#' \strong{Statistics SAS does not compute are NA}, as SAS writes missing:
#' \itemize{
#'   \item \code{msign}, \code{probm}, \code{signrank}, \code{probs},
#'     \code{normal}, \code{probn} when \code{weight_col} is given;
#'   \item \code{t}, \code{probt}, \code{stderr} and \code{stdmean} when
#'     \code{vardef} is not \code{"df"};
#'   \item \code{skewness} and \code{kurtosis} when \code{vardef} is
#'     \code{"wdf"} or \code{"weight"};
#'   \item \code{normal} and \code{probn} above 2000 observations, with one
#'     warning per call: SAS switches to a Kolmogorov D test there, which is
#'     not ported;
#'   \item \code{std}, \code{var}, \code{cv}, \code{stderr}, \code{stdmean},
#'     \code{t}, \code{probt} at one observation, \code{skewness} below three
#'     and \code{kurtosis} below four;
#'   \item \code{t}, \code{probt}, \code{skewness}, \code{kurtosis},
#'     \code{normal}, \code{probn} when every value is equal (\code{cv} is
#'     then \code{0} unless the mean is zero, where it is \code{NA});
#'   \item \code{msign}, \code{probm}, \code{signrank}, \code{probs} when no
#'     value differs from \code{mu0};
#'   \item \code{mode} when no value repeats among two or more values.
#' }
#'
#' \strong{Tests.} \code{t} is Student's t for the mean against \code{mu0};
#' \code{msign} the sign statistic; \code{signrank} the Wilcoxon signed rank
#' statistic, with an exact p-value for 20 or fewer non-zero differences and
#' SAS's t approximation above that. \code{normal} is the Shapiro-Wilk
#' \eqn{W}, from \code{stats::shapiro.test()}, which implements Royston's 1995
#' algorithm; SAS implements Royston's 1992 one, so \code{normal} and
#' \code{probn} agree with SAS to about \eqn{10^{-8}}, not to machine
#' precision. At two observations both are \code{1}, as SAS reports.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param var_cols Character vector of columns to analyse, was \code{vars} before
#'   2026-11 (\code{vars =} still works for one release, with a warning).
#'   \code{NULL} (default) selects every numeric column not named in
#'   \code{class_cols} or
#'   \code{weight_col}.
#' @param class_cols Character vector of grouping columns, prepended to the
#'   result as leading columns. Was \code{class} before 2026-11; \code{class =} still
#'   works for one release, with a warning. Rows with a missing value in any
#'   class variable are
#'   dropped, and levels follow \code{ORDER=INTERNAL}, as in
#'   \code{\link{proc_means}}. Unlike \code{proc_means()}, a level whose
#'   every weight is missing has no row, as in SAS.
#' @param stats Character vector of SAS statistic keywords: every keyword
#'   \code{\link{proc_means}} accepts, plus \code{"stdmean"}, \code{"t"},
#'   \code{"probt"}, \code{"msign"}, \code{"probm"}, \code{"signrank"},
#'   \code{"probs"}, \code{"normal"} and \code{"probn"}.
#' @param weight_col Character or \code{NULL}. Name of a single numeric column of
#'   \code{data} to use as an observation weight, SAS \code{WEIGHT}.
#'   Observations whose weight is missing are excluded from every statistic
#'   except \code{nobs}, which counts them.
#' @param pctlpts Numeric vector of percentile points in \code{[0, 100]},
#'   decimals allowed, or \code{NULL}. SAS \code{PCTLPTS=}.
#' @param pctlpre Single string prefixed to the \code{pctlpts} column names.
#'   SAS \code{PCTLPRE=}. The point follows with \code{.} replaced by
#'   \code{_}, so \code{2.5} gives \code{p2_5}.
#' @param mu0 Single finite number, the null value for \code{t},
#'   \code{msign} and \code{signrank}. SAS \code{MU0=}.
#' @param vardef The variance divisor: \code{"df"} (default), \code{"n"},
#'   \code{"wdf"} or \code{"weight"}. SAS \code{VARDEF=}.
#'
#' @param weights Deprecated: the old name of \code{weight_col}, kept for one release.
#' @param vars Deprecated: the old name of \code{var_cols}, kept for one release.
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the \code{class_cols} variables (when supplied), then
#'   \code{variable}, \code{label}, then one column per \code{stats} keyword in
#'   the order given, then one column per \code{pctlpts} point in the order
#'   given. \code{n}, \code{nmiss} and \code{nobs} are integer; all others are
#'   numeric.
#'
#' @seealso \code{\link{proc_means}} for the descriptive statistics alone.
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
#' proc_univariate(dta, var_cols = "age", stats = "n",
#'                 pctlpts = c(2.5, 50, 97.5))
#'
#' # Tests for location and normality
#' proc_univariate(dta, var_cols = "bmi",
#'                 stats = c("mean", "t", "probt", "normal", "probn"),
#'                 mu0 = 25)
proc_univariate <- function(data, var_cols = NULL, class_cols = NULL,
                            stats = c("n", "median", "mean", "std", "cv",
                                      "min", "max"),
                            weight_col = NULL, pctlpts = NULL, pctlpre = "p",
                            mu0 = 0,
                            vardef = c("df", "n", "wdf", "weight"), weights, vars) {
  if (!missing(weights)) {
    if (!missing(weight_col)) .hvti_refuse_both("proc_univariate", "weights", "weight_col")
    .hvti_deprecate("proc_univariate_weights", "proc_univariate(): `weights =` is now `weight_col =`, per the family rule that an ",
                    "argument naming one column ends in _col. The old name works for one more release.")
    weight_col <- weights
  }
  weights <- weight_col
  # `class` partially matches `class_cols`, so R binds it; `vars` does not
  # match `var_cols` and is a trailing formal.
  if (!missing(vars) && !missing(var_cols)) .hvti_refuse_both("proc_univariate", "vars", "var_cols")
  if (!missing(vars) || .hvti_old_call(sys.call(), parent.frame(), renamed = "class")) {
    .hvti_deprecate("proc_univariate_cols", "proc_univariate(): `vars =` and `class =` are now `var_cols =` and `class_cols =`, ",
                    "per the family rule that an argument naming columns ends in _cols. The old names work for one more release.")
  }
  if (!missing(vars)) var_cols <- vars
  vars <- var_cols
  class <- class_cols
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
