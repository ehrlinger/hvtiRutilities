#' Summarise numeric variables, in the style of SAS PROC MEANS
#'
#' @description
#' Produces the table SAS \code{PROC MEANS} prints: one row per analysis
#' variable, one column per requested statistic, in the order requested.
#'
#' @details
#' Quantiles use \code{stats::quantile(type = 2)}, which is the R equivalent of
#' SAS's default \code{QNTLDEF=5}. This matters: R's own default is
#' \code{type = 7}, a different estimator that disagrees with SAS on the small
#' and even-numbered samples clinical subgroups produce. For
#' \code{c(1, 2, 3, 4)}, the first quartile is \code{1.5} in SAS and
#' \code{1.75} under R's default. The median agrees, which is why the
#' discrepancy hides.
#'
#' With \code{vars = NULL} all numeric columns are analysed, matching SAS's
#' behaviour when the \code{VAR} statement is omitted. Logical columns are not
#' \code{is.numeric()} in R and so are excluded from that default set; naming
#' one in \code{vars} coerces it to 0/1, making \code{mean} a proportion as
#' \code{PROC MEANS} would give.
#'
#' Rows are ordered by analysis variable first, then by class level. A factor
#' class variable orders by its declared level order rather than
#' alphabetically, matching SAS's default \code{ORDER=INTERNAL}; this keeps
#' ordered clinical scales such as NYHA class in their clinical sequence.
#'
#' @param data A data frame, tibble, or similar tabular object.
#' @param vars Character vector of columns to analyse. \code{NULL} (default)
#'   selects every numeric column not named in \code{class}.
#' @param class Character vector of grouping columns, prepended to the result
#'   as leading columns. Rows with a missing value in any class variable are
#'   dropped, matching SAS's default.
#' @param stats Character vector of SAS statistic keywords: \code{"n"},
#'   \code{"nmiss"}, \code{"mean"}, \code{"std"}, \code{"min"}, \code{"max"},
#'   \code{"sum"}, \code{"range"}, \code{"stderr"}, \code{"cv"},
#'   \code{"median"}, \code{"q1"}, \code{"q3"}, or any \code{"pNN"} for
#'   \code{NN} between 1 and 99. Defaults to SAS's own default five.
#'
#' @return A data frame with one row per analysis variable per class
#'   combination. Columns are the \code{class} variables (when supplied), then
#'   \code{variable}, \code{label}, then one column per requested statistic in
#'   the order given by \code{stats}. Count statistics (\code{n},
#'   \code{nmiss}) are integer; all others are numeric.
#'
#' @seealso \code{\link{proc_contents}} for variable metadata.
#'
#' @importFrom stats quantile sd complete.cases
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # SAS default statistics over every numeric variable
#' head(proc_means(dta))
#'
#' # Named variables and an explicit statistic list
#' proc_means(dta, vars = c("age", "bmi"),
#'            stats = c("n", "mean", "median", "p15"))
proc_means <- function(data, vars = NULL, class = NULL,
                       stats = c("n", "mean", "std", "min", "max")) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  .validate_stats(stats)

  if (!is.null(class)) {
    .check_columns(class, data)
  }

  if (is.null(vars)) {
    numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
    vars <- setdiff(numeric_cols, class)
  } else {
    .check_columns(vars, data)
    usable <- vapply(data[vars], function(x) is.numeric(x) || is.logical(x),
                     logical(1))
    if (!all(usable)) {
      stop("Non-numeric column(s) named in 'vars': ",
           paste(vars[!usable], collapse = ", "), call. = FALSE)
    }
  }

  if (length(vars) == 0L) {
    warning("No numeric columns to analyse; returning a zero-row result.",
            call. = FALSE)
    return(.empty_means(class, stats))
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  groups <- NULL
  grp_idx <- NULL
  if (!is.null(class) && length(class) > 0L) {
    keep <- stats::complete.cases(data[, class, drop = FALSE])
    data <- data[keep, , drop = FALSE]
    groups <- unique(data[, class, drop = FALSE])
    groups <- groups[do.call(base::order,
                             c(unname(as.list(groups)),
                               list(method = "radix"))), ,
                     drop = FALSE]
    rownames(groups) <- NULL

    grp_idx <- lapply(seq_len(nrow(groups)), function(i) {
      ok <- rep(TRUE, nrow(data))
      for (k in class) {
        ok <- ok & (data[[k]] == groups[[k]][i])
      }
      which(ok)
    })
  }

  rows <- list()
  for (v in vars) {
    if (is.null(groups)) {
      rows[[length(rows) + 1L]] <-
        .means_row(data[[v]], v, unname(labels[v]), stats)
    } else {
      for (i in seq_len(nrow(groups))) {
        rows[[length(rows) + 1L]] <- cbind(
          groups[i, , drop = FALSE],
          .means_row(data[[v]][grp_idx[[i]]], v, unname(labels[v]), stats),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(rows) == 0L) {
    warning("All rows dropped: every value of the class variable(s) is missing; ",
            "returning a zero-row result.", call. = FALSE)
    return(.empty_means(class, stats))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

## Internal: stop if any named column is absent from the data
.check_columns <- function(cols, data) {
  absent <- setdiff(cols, names(data))
  if (length(absent) > 0L) {
    stop("Column(s) not found in 'data': ",
         paste(absent, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: weighted mean, or the plain mean when w is NULL
.wmean <- function(v, w) {
  if (is.null(w)) mean(v) else sum(w * v) / sum(w)
}

## Internal: weighted variance at SAS VARDEF=DF -- the divisor is the count of
## non-missing observations minus one, not the sum of the weights.
.wvar <- function(v, w) {
  n <- length(v)
  if (n < 2L) {
    return(NA_real_)
  }
  m <- .wmean(v, w)
  css <- if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
  css / (n - 1)
}

## =============================================================================
## Internal: the statistic registry.
##
## Each entry carries its compute function plus two flags. `weighted` is the
## contract from the design: .compute_stat() passes weights to a statistic only
## when its flag is TRUE, so a statistic cannot become weighted by someone
## editing its body. `integer` types the zero-row result.
##
## fun(x, v, w): x is the raw vector including NA, v is x with NA removed, and w
## is a numeric vector aligned to v, or NULL.
.STATS <- list(
  n = list(
    fun = function(x, v, w) length(v),
    weighted = FALSE, integer = TRUE
  ),
  nmiss = list(
    fun = function(x, v, w) sum(is.na(x)),
    weighted = FALSE, integer = TRUE
  ),
  nobs = list(
    fun = function(x, v, w) length(x),
    weighted = FALSE, integer = TRUE
  ),
  mean = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else .wmean(v, w),
    weighted = TRUE, integer = FALSE
  ),
  std = list(
    fun = function(x, v, w) sqrt(.wvar(v, w)),
    weighted = TRUE, integer = FALSE
  ),
  min = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else min(v),
    weighted = FALSE, integer = FALSE
  ),
  max = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v),
    weighted = FALSE, integer = FALSE
  ),
  sum = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v) else sum(w * v)
    },
    weighted = TRUE, integer = FALSE
  ),
  range = list(
    fun = function(x, v, w) if (length(v) == 0L) NA_real_ else max(v) - min(v),
    weighted = FALSE, integer = FALSE
  ),
  stderr = list(
    fun = function(x, v, w) sqrt(.wvar(v, w) / length(v)),
    weighted = TRUE, integer = FALSE
  ),
  cv = list(
    fun = function(x, v, w) {
      s <- sqrt(.wvar(v, w))
      m <- .wmean(v, w)
      # SAS emits missing when the mean is zero; R would give Inf.
      if (is.na(s) || m == 0) NA_real_ else 100 * s / m
    },
    weighted = TRUE, integer = FALSE
  ),
  var = list(
    fun = function(x, v, w) .wvar(v, w),
    weighted = TRUE, integer = FALSE
  ),
  uss = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) NA_real_ else if (is.null(w)) sum(v^2) else sum(w * v^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  css = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      m <- .wmean(v, w)
      if (is.null(w)) sum((v - m)^2) else sum(w * (v - m)^2)
    },
    weighted = TRUE, integer = FALSE
  ),
  qrange = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      .quantile_stat(v, "q3") - .quantile_stat(v, "q1")
    },
    weighted = FALSE, integer = FALSE
  ),
  mode = list(
    fun = function(x, v, w) {
      if (length(v) == 0L) {
        return(NA_real_)
      }
      tab <- table(v)
      top <- max(tab)
      if (top == 1L) {
        return(NA_real_)          # SAS: no mode when nothing repeats
      }
      # SAS reports the smallest value among tied modes.
      min(as.numeric(names(tab)[tab == top]))
    },
    weighted = FALSE, integer = FALSE
  ),
  median = list(
    fun = function(x, v, w) .quantile_stat(v, "median"),
    weighted = FALSE, integer = FALSE
  ),
  q1 = list(
    fun = function(x, v, w) .quantile_stat(v, "q1"),
    weighted = FALSE, integer = FALSE
  ),
  q3 = list(
    fun = function(x, v, w) .quantile_stat(v, "q3"),
    weighted = FALSE, integer = FALSE
  )
)

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats) {
  known <- names(.STATS)
  ok <- stats %in% known | grepl("^p([1-9]|[1-9][0-9])$", stats)
  if (!all(ok)) {
    stop("Unrecognised statistic keyword(s): ",
         paste(stats[!ok], collapse = ", "),
         ". Valid keywords are: ", paste(known, collapse = ", "),
         ", and pNN for NN from 1 to 99.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: one statistic from one vector, SAS semantics.
## `w` is a weight vector aligned to `x`, or NULL. Statistics whose registry
## entry is not marked `weighted` never see it.
.compute_stat <- function(x, stat, w = NULL) {
  x <- as.numeric(x)
  keep <- !is.na(x)
  v <- x[keep]

  entry <- .STATS[[stat]]
  if (is.null(entry)) {
    return(.quantile_stat(v, stat))
  }
  wv <- if (isTRUE(entry$weighted) && !is.null(w)) w[keep] else NULL
  entry$fun(x, v, wv)
}

## Internal: quantile statistics at SAS QNTLDEF=5 (R type 2)
.quantile_stat <- function(v, stat) {
  if (length(v) == 0L) {
    return(NA_real_)
  }
  p <- switch(stat,
    median = 0.5,
    q1     = 0.25,
    q3     = 0.75,
    as.numeric(sub("^p", "", stat)) / 100
  )
  stats::quantile(v, probs = p, type = 2, names = FALSE)
}

## Internal: one output row for one variable
.means_row <- function(x, variable, label, stats) {
  vals <- lapply(stats, function(s) .compute_stat(x, s))
  names(vals) <- stats
  cbind(
    data.frame(variable = variable, label = label, stringsAsFactors = FALSE),
    as.data.frame(vals, stringsAsFactors = FALSE)
  )
}

## Internal: zero-row result with the correct columns
.empty_means <- function(class, stats) {
  out <- data.frame(variable = character(), label = character(),
                    stringsAsFactors = FALSE)
  for (s in stats) {
    entry <- .STATS[[s]]
    out[[s]] <- if (isTRUE(entry$integer)) integer() else numeric()
  }
  if (!is.null(class) && length(class) > 0L) {
    pre <- as.data.frame(
      stats::setNames(replicate(length(class), character(), simplify = FALSE),
                      class),
      stringsAsFactors = FALSE
    )
    out <- cbind(pre, out)
  }
  out
}
