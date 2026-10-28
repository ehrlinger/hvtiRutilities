#' Targeted prints of matching rows, in the style of SAS PROC PRINT with WHERE
#'
#' @description
#' Counts the rows that match each of a set of named conditions, and prints
#' the matching rows to the console. It is the checking step a programmer
#' runs after a build: write the build, cross-tab, spot a discrepancy, print
#' the rows that look wrong. One call takes several conditions, as several
#' SAS \code{PROC PRINT; WHERE} steps would.
#'
#' @details
#' \strong{Matching rows go to the console, and only counts reach a report.}
#' A targeted print shows patient rows, and a rendered report gets shared. So
#' the rows are written to \code{stderr()}, which knitr and Quarto do not
#' capture: an interactive session shows them, and a render leaves them out
#' of the HTML whatever the chunk's \code{message} or \code{warning} options
#' say. What the function returns, and what a report prints, is one count per
#' condition. This is where it differs from SAS, whose \code{PROC PRINT}
#' output is the listing.
#'
#' Each condition is written \code{condition ~ "Label"}, the shape of a
#' \code{bd} job's \code{EXCLUDE} rules, and is evaluated with the columns of
#' \code{data} in scope, then the formula's environment. A condition that
#' evaluates to \code{NA} for a row does not match it; those rows are counted
#' in \code{n_missing}, so a check that cannot be decided for some patients
#' says so instead of reading as clean. A condition that fails is an error
#' naming its label. The error does not repeat R's own message, which can
#' quote a data value. Warnings and messages raised while a condition is
#' evaluated (a date parser listing the value it could not read, say) go to
#' \code{stderr()} with the rows, for the same reason.
#'
#' @param data A data frame.
#' @param where A list of conditions, each \code{condition ~ "Label"} with a
#'   single non-empty quoted label, or one such formula. Labels must be
#'   unique.
#' @param var Character or \code{NULL}. Columns to print for the matching
#'   rows, SAS \code{VAR}. \code{NULL} prints every column.
#' @param max_rows A single positive whole number. At most this many matching
#'   rows are printed per condition; the count is always the full count.
#'
#' @return A data frame with one row per condition and the columns
#'   \code{label}, \code{n} (rows matching) and \code{n_missing} (rows for
#'   which the condition was \code{NA}). Both counts are integer. The matching
#'   rows are written to \code{stderr()} as a side effect and are not part of
#'   the result.
#'
#' @seealso \code{\link{proc_freq}}, \code{\link{followup_check}}
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#'
#' # proc print; where age > 80; var age dead;
#' proc_print(dta,
#'   where = list(age > 80 ~ "Older than 80",
#'                dead == 1 & iv_dead < 1 ~ "Death in the first year"),
#'   var = c("age", "dead", "iv_dead"))
proc_print <- function(data, where, var = NULL, max_rows = 25L) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  where <- .print_conditions(where)
  if (!is.null(var)) {
    if (!is.character(var) || length(var) == 0L || anyNA(var)) {
      stop("'var' must be NULL or a non-empty character vector of column names.",
           call. = FALSE)
    }
    .check_columns(var, data)
  }
  bad_rows <- !is.numeric(max_rows) || length(max_rows) != 1L || is.na(max_rows)
  if (bad_rows || max_rows < 1 || max_rows != round(max_rows)) {
    stop("'max_rows' must be a single positive whole number.", call. = FALSE)
  }
  shown <- if (is.null(var)) names(data) else var

  labels <- vapply(where, function(f) f[[3L]], character(1))
  n <- integer(length(where))
  n_missing <- integer(length(where))
  for (i in seq_along(where)) {
    hit <- .eval_print_condition(where[[i]], data, labels[[i]])
    n[[i]] <- sum(hit %in% TRUE)
    n_missing[[i]] <- sum(is.na(hit))
    .print_matches(data[hit %in% TRUE, shown, drop = FALSE], labels[[i]],
                   n[[i]], n_missing[[i]], max_rows)
  }
  data.frame(label = labels, n = n, n_missing = n_missing,
             stringsAsFactors = FALSE)
}

## Internal: validate `where` and return it as a list of formulas
.print_conditions <- function(where) {
  if (inherits(where, "formula")) where <- list(where)
  if (!is.list(where) || length(where) == 0L) {
    stop("'where' must be one condition or a non-empty list of conditions, ",
         "each written condition ~ \"Label\".", call. = FALSE)
  }
  for (i in seq_along(where)) {
    f <- where[[i]]
    ok <- inherits(f, "formula") && length(f) == 3L
    label <- if (ok) f[[3L]] else NULL
    ok <- ok && is.character(label) && length(label) == 1L
    if (!ok || is.na(label) || !nzchar(label)) {
      stop("'where' condition ", i, " is not written condition ~ \"Label\". ",
           "Give every condition a quoted label.", call. = FALSE)
    }
  }
  labels <- vapply(where, function(f) f[[3L]], character(1))
  if (anyDuplicated(labels) > 0L) {
    stop("'where' repeats a label: ",
         paste(unique(labels[duplicated(labels)]), collapse = ", "),
         call. = FALSE)
  }
  where
}

## Internal: evaluate one condition to a logical vector, one value per row.
## R's error message is withheld: it can quote a data value. Warnings and
## messages raised while evaluating can quote one too (a parse failure lists
## the value it could not read), so they go to stderr() with the rows and
## never reach a knitted report.
.eval_print_condition <- function(f, data, label) {
  to_console <- function(cnd, restart) {
    cat("proc_print(): condition \"", label, "\": ", conditionMessage(cnd),
        if (inherits(cnd, "message")) "" else "\n", sep = "", file = stderr())
    invokeRestart(restart)
  }
  hit <- tryCatch(
    withCallingHandlers(
      eval(f[[2L]], data, environment(f)),
      warning = function(w) to_console(w, "muffleWarning"),
      message = function(m) to_console(m, "muffleMessage")
    ),
    error = function(e) structure(list(), class = "print_failed")
  )
  if (inherits(hit, "print_failed")) {
    stop("proc_print(): condition \"", label, "\" could not be evaluated. ",
         "Check the column names it uses.", call. = FALSE)
  }
  if (!is.logical(hit) || length(hit) != nrow(data)) {
    stop("proc_print(): condition \"", label, "\" must give one TRUE, FALSE ",
         "or NA per row.", call. = FALSE)
  }
  hit
}

## Internal: write one condition's matching rows to stderr(), never stdout,
## so a knitr or Quarto render does not put them in the report.
.print_matches <- function(rows, label, n, n_missing, max_rows) {
  con <- stderr()
  cat("\n", label, ": ", n, " row(s) match", sep = "", file = con)
  if (n_missing > 0L) {
    cat(", ", n_missing, " undecided (NA)", sep = "", file = con)
  }
  cat("\n", file = con)
  if (n == 0L) return(invisible(NULL))
  listing <- utils::capture.output(print(utils::head(rows, max_rows),
                                         row.names = FALSE))
  cat(listing, sep = "\n", file = con)
  if (n > max_rows) {
    cat("... ", n - max_rows, " more not shown (max_rows = ", max_rows, ")\n",
        sep = "", file = con)
  }
  invisible(NULL)
}
