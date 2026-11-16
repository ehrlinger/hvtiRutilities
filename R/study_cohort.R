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
#' A zero or negative time is still counted, so the gate's numbers do not
#' move, but it warns: \code{\link{followup_check}} flags the same rows for
#' review, and the two should not disagree in silence.
#'
#' @param data A data frame. Was \code{d} before 2026-11; \code{d =} still
#'   works for one release, with a warning.
#' @param time Character scalar naming the time column.
#' @param event Character scalar naming the binary event column.
#'
#' @section Argument order:
#' \code{time, event}, as in \code{survival::Surv()}. Until 2026-11 the order
#' was \code{event, time}. For one release a call passing both unnamed is read
#' in the old order, with a warning; name them, \code{time =} and
#' \code{event =}, and the call means the same before and after.
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
#' cohort_counts(d, time = "iv_dead", event = "dead")
cohort_counts <- function(data, time, event) {
  cl <- sys.call()
  env <- parent.frame()
  if (.hvti_old_call(cl, env, renamed = "d", positional = 3L)) {
    .hvti_deprecate("cohort_counts_args",
                    "cohort_counts(): the arguments are now (data, time, event), as in survival::Surv(). ",
                    "`d =` is now `data =`, and two unnamed arguments after the data are read in the ",
                    "old order, event then time, for one more release. Name them: time =, event =.")
    return(.hvti_recall(cl, env, function(d, event, time) NULL, cohort_counts, c(d = "data")))
  }
  d <- data
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

  # followup_check() flags a zero or negative interval for review; the gate
  # counts what it is given, but says so rather than passing such rows as
  # ordinary analysable time.
  t_ok <- d[[time]][ok]
  if (is.numeric(t_ok) && any(t_ok <= 0)) {
    warning(
      "cohort_counts(): ", sum(t_ok < 0), " negative and ", sum(t_ok == 0),
      " zero value(s) of `", time, "` are counted as analysable. Review them ",
      "with followup_check().",
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
#' @param data A data frame. Was \code{d} before 2026-11; \code{d =} still
#'   works for one release, with a warning.
#' @param expected List containing nonnegative integer \code{n},
#'   \code{n_events} and \code{n_censored}.
#' @param time Character scalar naming the time column.
#' @param event Character scalar naming the binary event column.
#'
#' @section Argument order:
#' \code{time, event}, as in \code{survival::Surv()}; it was \code{event,
#' time} until 2026-11. For one release a call passing all four arguments
#' unnamed is read in the old order, with a warning.
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
#' assert_cohort(d, expected, time = "iv_dead", event = "dead")
assert_cohort <- function(data, expected, time, event) {
  cl <- sys.call()
  env <- parent.frame()
  if (.hvti_old_call(cl, env, renamed = "d", positional = 4L)) {
    .hvti_deprecate("assert_cohort_args",
                    "assert_cohort(): the arguments are now (data, expected, time, event), as in ",
                    "survival::Surv(). `d =` is now `data =`, and four unnamed arguments are read in the ",
                    "old order, event then time, for one more release. Name them: time =, event =.")
    return(.hvti_recall(cl, env, function(d, expected, event, time) NULL, assert_cohort,
                        c(d = "data")))
  }
  d <- data
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
  observed <- cohort_counts(d, time = time, event = event)
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
