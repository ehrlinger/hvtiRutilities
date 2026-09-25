#' Check recorded follow-up before a time-related analysis
#'
#' @description
#' Summarises an event indicator and its follow-up intervals the way the
#' \code{dc-gfup} template reports them: counts for the whole cohort and its
#' event and censored subsets, the missing, negative and zero intervals, a
#' \code{\link{proc_means}} table for each subset, and the rows worth a second
#' look. It checks recorded follow-up; it does not establish completeness
#' against a close date.
#'
#' @details
#' Every argument is checked before anything is computed, and every column
#' that is not in \code{data} is named in one error, so a job with three
#' misspellings says so once.
#'
#' A row with a missing event is counted in \code{missing_event} and belongs
#' to neither the event nor the censored subset. A row is \emph{suspicious}
#' when its event is missing or any of its intervals is missing, negative or
#' zero.
#'
#' The quartiles in \code{intervals} use R's default interpolated quantiles
#' (\code{type = 7}), while \code{\link{proc_means}} uses the SAS
#' \code{QNTLDEF=5} estimator, so the two tables can disagree on a small
#' subset. The difference is deliberate: \code{intervals} is a quick
#' screen, and \code{means} is the table to compare against SAS.
#'
#' Identifiers are never included unless named in \code{identifier}. Check the
#' result before sharing a report that shows \code{review} with one.
#'
#' @param data A data frame, one row per patient.
#' @param event Name of the event indicator: 1 or \code{TRUE} for an event, 0
#'   or \code{FALSE} for censored. Missing values are allowed and counted.
#' @param followup Names of one or more follow-up interval columns, in years.
#' @param identifier \code{NULL} (the default), or the name of one column to
#'   show in \code{review}.
#' @param max_rows The most suspicious rows to return in \code{review}, in data
#'   order. Default 25.
#'
#' @return An object of class \code{followup_check}, a list of four
#'   components, three data frames and a list of three:
#' \describe{
#'   \item{\code{cohort}}{One row: \code{full}, \code{event}, \code{censored}
#'     and \code{missing_event} counts.}
#'   \item{\code{intervals}}{One row per interval: \code{missing},
#'     \code{negative} and \code{zero} counts, then \code{min}, \code{q1},
#'     \code{median}, \code{q3}, \code{mean}, \code{sd} and \code{max} of the
#'     observed values.}
#'   \item{\code{means}}{A named list, \code{full}, \code{event} and
#'     \code{censored}, of \code{\link{proc_means}} tables over the
#'     intervals.}
#'   \item{\code{review}}{Up to \code{max_rows} suspicious rows, with the
#'     event, the intervals and any \code{identifier}.}
#' }
#'
#' @seealso \code{\link{proc_means}}, \code{\link{cohort_counts}}, which counts
#'   the analysable cohort rather than checking follow-up.
#'
#' @examples
#' d <- data.frame(dead = c(1, 0, 0, NA, 1), iv_dead = c(2.5, 4, 0, 1.2, NA))
#' fc <- followup_check(d, event = "dead", followup = "iv_dead")
#' fc
#' fc$cohort
#' fc$review
#' @export
followup_check <- function(data, event, followup, identifier = NULL, max_rows = 25L) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  field_names <- function(x) is.character(x) && length(x) > 0L && !anyNA(x) && all(nzchar(x)) && !anyDuplicated(x)
  if (!field_names(event) || length(event) != 1L) stop("`event` must name one column.", call. = FALSE)
  if (!field_names(followup)) stop("`followup` must name one or more distinct columns.", call. = FALSE)
  if (!is.null(identifier) && (!field_names(identifier) || length(identifier) != 1L)) {
    stop("`identifier` must be NULL or one column name.", call. = FALSE)
  }
  if (!is.numeric(max_rows) || length(max_rows) != 1L || is.na(max_rows) ||
        !is.finite(max_rows) || max_rows < 1 || max_rows != floor(max_rows)) {
    stop("`max_rows` must be one positive integer.", call. = FALSE)
  }
  needed <- unique(c(event, followup, identifier))
  unknown <- setdiff(needed, names(data))
  if (length(unknown)) {
    stop("Unknown column(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  ev <- data[[event]]
  if ((!is.numeric(ev) && !is.logical(ev)) || any(!is.na(ev) & !ev %in% c(0, 1))) {
    stop("`event` must be binary (0 = censored, 1 = event; missing is allowed).", call. = FALSE)
  }
  not_numeric <- followup[!vapply(data[followup], is.numeric, logical(1L))]
  if (length(not_numeric)) {
    stop("`followup` columns must be numeric: ", paste(not_numeric, collapse = ", "), call. = FALSE)
  }

  cohort <- data.frame(full = nrow(data), event = sum(ev == 1, na.rm = TRUE),
                       censored = sum(ev == 0, na.rm = TRUE), missing_event = sum(is.na(ev)))
  intervals <- do.call(rbind, lapply(followup, function(variable) {
    x <- data[[variable]]
    observed <- x[!is.na(x)]
    q <- if (length(observed)) stats::quantile(observed, c(0, .25, .5, .75, 1), names = FALSE) else rep(NA_real_, 5L)
    data.frame(interval = variable, missing = sum(is.na(x)), negative = sum(x < 0, na.rm = TRUE),
               zero = sum(x == 0, na.rm = TRUE), min = q[[1L]], q1 = q[[2L]], median = q[[3L]], q3 = q[[4L]],
               mean = if (length(observed)) mean(observed) else NA_real_, sd = stats::sd(observed), max = q[[5L]])
  }))
  subsets <- list(full = data, event = data[!is.na(ev) & ev == 1, , drop = FALSE],
                  censored = data[!is.na(ev) & ev == 0, , drop = FALSE])
  st <- c("n", "nmiss", "mean", "std", "min", "p25", "median", "p75", "max")
  means <- lapply(subsets, function(s) proc_means(s, vars = followup, stats = st))
  suspicious <- is.na(ev) | Reduce(`|`, lapply(data[followup], function(x) is.na(x) | x <= 0))
  review <- data[utils::head(which(suspicious), max_rows), needed, drop = FALSE]
  rownames(review) <- NULL

  structure(list(cohort = cohort, intervals = intervals, means = means, review = review),
            event = event, followup = followup, n_suspicious = sum(suspicious),
            class = "followup_check")
}

#' @export
print.followup_check <- function(x, ...) {
  co <- x$cohort
  cat("<followup_check> event `", attr(x, "event"), "`, interval(s) ",
      paste0("`", attr(x, "followup"), "`", collapse = ", "), "\n", sep = "")
  cat("  Cohort     : ", co$full, " (", co$event, " event, ", co$censored, " censored, ",
      co$missing_event, " missing event)\n", sep = "")
  cat("  Suspicious : ", attr(x, "n_suspicious"), " row(s), ", nrow(x$review), " shown in $review\n", sep = "")
  invisible(x)
}
