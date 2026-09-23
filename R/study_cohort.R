# The cohort gate. A build that changes the analysable cohort must fail every
# job rather than quietly producing different numbers, so a rendered page is
# itself evidence that this gate passed.

#' Count the analysable cohort
#'
#' @description
#' Counts rows for which both explicitly supplied event and time columns are
#' present, and the events among them.
#'
#' The event column must be logical or numeric binary coding: \code{FALSE}/\code{TRUE}
#' or \code{0}/\code{1}. Rows missing either column are excluded from the
#' analysable cohort.
#'
#' @param d A data frame.
#' @param event Character scalar naming the binary event column.
#' @param time Character scalar naming the time column.
#'
#' @return A list with integer elements \code{n}, \code{n_events} and
#'   \code{n_censored}.
#'
#' @seealso \code{\link{assert_cohort}}
#'
#' @export
#'
#' @examples
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' cohort_counts(d, event = "dead", time = "iv_dead")
cohort_counts <- function(d, event, time) {
  if (!is.character(event)) {
    stop("cohort_counts(): event must be a non-missing, non-empty character scalar",
         call. = FALSE)
  }
  if (!is.character(time)) {
    stop("cohort_counts(): time must be a non-missing, non-empty character scalar",
         call. = FALSE)
  }
  event <- .study_scalar(event, "event", required = TRUE, caller = "cohort_counts")
  time <- .study_scalar(time, "time", required = TRUE, caller = "cohort_counts")
  missing_cols <- setdiff(c(event, time), names(d))
  if (length(missing_cols)) {
    stop(
      "cohort_counts(): data has no column",
      if (length(missing_cols) > 1L) "s" else "",
      " named ", paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  ok <- !is.na(d[[time]]) & !is.na(d[[event]])
  observed <- d[[event]][ok]
  binary <- !length(observed) || is.logical(observed) ||
    (is.numeric(observed) && all(observed %in% c(0, 1)))
  if (!binary) {
    stop(
      "cohort_counts(): event column must be binary 0/1 or FALSE/TRUE",
      call. = FALSE
    )
  }

  n <- sum(ok)
  n_events <- sum(observed == 1)
  list(
    n = as.integer(n),
    n_events = as.integer(n_events),
    n_censored = as.integer(n - n_events)
  )
}

#' Assert the cohort matches a job-level expectation
#'
#' @description
#' Compares \code{\link{cohort_counts}} against explicitly supplied expected
#' counts and errors on any disagreement. Call it before any analysis that
#' would otherwise run happily on an unreconciled cohort.
#'
#' @param d A data frame.
#' @param expected List containing nonnegative integer \code{n},
#'   \code{n_events} and \code{n_censored}.
#' @param event Character scalar naming the binary event column.
#' @param time Character scalar naming the time column.
#'
#' @return \code{invisible(TRUE)} on success; otherwise an error.
#'
#' @seealso \code{\link{cohort_counts}}
#'
#' @export
#'
#' @examples
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' expected <- list(n = 5L, n_events = 2L, n_censored = 3L)
#' assert_cohort(d, expected, event = "dead", time = "iv_dead")
assert_cohort <- function(d, expected, event, time) {
  keys <- c("n", "n_events", "n_censored")
  valid <- is.list(expected) && all(keys %in% names(expected)) &&
    all(vapply(expected[keys], function(x) {
      is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
        x >= 0 && x <= .Machine$integer.max && x == floor(x)
    }, logical(1)))
  if (!valid) {
    stop(
      "assert_cohort(): expected must contain nonnegative integer n, ",
      "n_events and n_censored",
      call. = FALSE
    )
  }

  if (as.double(expected$n) !=
        as.double(expected$n_events) + as.double(expected$n_censored)) {
    stop("assert_cohort(): expected counts are inconsistent", call. = FALSE)
  }
  want <- lapply(expected[keys], as.integer)
  observed <- cohort_counts(d, event, time)
  if (!identical(observed, want)) {
    stop(
      "cohort gate: expected N=", want$n,
      " / events=", want$n_events,
      " / censored=", want$n_censored,
      ", got N=", observed$n,
      " / events=", observed$n_events,
      " / censored=", observed$n_censored,
      ". Analysis must not run on an unreconciled cohort.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
