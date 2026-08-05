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

  rows <- lapply(vars, function(v) {
    .means_row(data[[v]], v, unname(labels[v]), stats)
  })

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

## Internal: reject unknown statistic keywords
.validate_stats <- function(stats) {
  known <- c("n", "nmiss", "mean", "std", "min", "max", "sum", "range",
             "stderr", "cv", "median", "q1", "q3")
  ok <- stats %in% known | grepl("^p([1-9]|[1-9][0-9])$", stats)
  if (!all(ok)) {
    stop("Unrecognised statistic keyword(s): ",
         paste(stats[!ok], collapse = ", "),
         ". Valid keywords are: ", paste(known, collapse = ", "),
         ", and pNN for NN from 1 to 99.", call. = FALSE)
  }
  invisible(TRUE)
}

## Internal: one statistic from one vector, SAS semantics
.compute_stat <- function(x, stat) {
  x <- as.numeric(x)
  v <- x[!is.na(x)]
  n <- length(v)

  switch(stat,
    n      = n,
    nmiss  = sum(is.na(x)),
    mean   = if (n == 0L) NA_real_ else mean(v),
    std    = if (n < 2L) NA_real_ else stats::sd(v),
    min    = if (n == 0L) NA_real_ else min(v),
    max    = if (n == 0L) NA_real_ else max(v),
    sum    = if (n == 0L) NA_real_ else sum(v),
    range  = if (n == 0L) NA_real_ else max(v) - min(v),
    stderr = if (n < 2L) NA_real_ else stats::sd(v) / sqrt(n),
    cv     = if (n < 2L) NA_real_ else 100 * stats::sd(v) / mean(v),
    .quantile_stat(v, stat)
  )
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
    out[[s]] <- if (s %in% c("n", "nmiss")) integer() else numeric()
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
