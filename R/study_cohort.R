# The cohort gate. A build that changes the analysable cohort must fail every
# job rather than quietly producing different numbers, so a rendered page is
# itself evidence that this gate passed.

#' Count the analysable cohort
#'
#' @description
#' Counts rows for which both explicitly supplied event and time columns are
#' present, and the events among them.
#'
#' The event column must be logical or numeric binary coding: `FALSE`/`TRUE`
#' or `0`/`1`. Rows missing either column are excluded from the
#' analysable cohort.
#'
#' A zero or negative time is still counted, so the gate's numbers do not
#' move, but it warns: [followup_check()] flags the same rows for
#' review, and the two should not disagree in silence.
#'
#' @param data A data frame. Was `d` before 2026-11; `d =` still
#'   works for one release, with a warning.
#' @param time_col Character scalar naming the time column. Was `time`
#'   before 2026-11; `time =` still works for one release, with a warning.
#' @param event_col Character scalar naming the binary event column. Was
#'   `event` before 2026-11; `event =` still works for one release,
#'   with a warning.
#'
#' @section Argument order:
#' `time_col, event_col`, as in `survival::Surv()`. Until 2026-11 the
#' order was `event, time`, so a call passing both unnamed means opposite
#' things in the two orders and is an error, whether or not `data` is
#' named. Name them, `time_col =` and `event_col =`. One of the two
#' unnamed reads the same in either order.
#'
#' @return A list with integer elements `n`, `n_events` and
#'   `n_censored`.
#'
#' @seealso [assert_cohort()]
#'
#' @export
#'
#' @examples
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' cohort_counts(d, time_col = "iv_dead", event_col = "dead")
cohort_counts <- function(data, time_col, event_col) {
  cl <- sys.call()
  env <- parent.frame()
  .hvti_refuse_ambiguous_order(cl, env, cohort_counts, "cohort_counts", "(data, time_col, event_col)")
  # The old names `d`, `time` and `event` partially match the new ones, so R
  # binds them itself; only the notice is needed.
  if (.hvti_old_call(cl, env, renamed = c("d", "time", "event"))) {
    .hvti_deprecate("cohort_counts_args",
                    "cohort_counts(): the arguments are now (data, time_col, event_col), as in survival::Surv(). ",
                    "`d =`, `time =` and `event =` are now `data =`, `time_col =` and `event_col =`.")
  }
  d <- data
  if (!is.character(event_col)) {
    stop("cohort_counts(): event_col must be a non-missing, non-empty character scalar",
         call. = FALSE)
  }
  if (!is.character(time_col)) {
    stop("cohort_counts(): time_col must be a non-missing, non-empty character scalar",
         call. = FALSE)
  }
  event <- .study_scalar(event_col, "event_col", required = TRUE, caller = "cohort_counts")
  time <- .study_scalar(time_col, "time_col", required = TRUE, caller = "cohort_counts")
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
#' Compares [cohort_counts()] against explicitly supplied expected
#' counts and errors on any disagreement. Call it before any analysis that
#' would otherwise run happily on an unreconciled cohort.
#'
#' @param data A data frame. Was `d` before 2026-11; `d =` still
#'   works for one release, with a warning.
#' @param expected List containing nonnegative integer `n`,
#'   `n_events` and `n_censored`.
#' @param time_col Character scalar naming the time column. Was `time`
#'   before 2026-11; `time =` still works for one release, with a warning.
#' @param event_col Character scalar naming the binary event column. Was
#'   `event` before 2026-11; `event =` still works for one release,
#'   with a warning.
#'
#' @section Argument order:
#' `time_col, event_col`, as in `survival::Surv()`; it was
#' `event, time` until 2026-11. A call passing both unnamed is an error,
#' since the two orders read it oppositely; name `time_col =` and
#' `event_col =`.
#'
#' @return `invisible(TRUE)` on success; otherwise an error.
#'
#' @seealso [cohort_counts()]
#'
#' @export
#'
#' @examples
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' expected <- list(n = 5L, n_events = 2L, n_censored = 3L)
#' assert_cohort(d, expected, time_col = "iv_dead", event_col = "dead")
assert_cohort <- function(data, expected, time_col, event_col) {
  cl <- sys.call()
  env <- parent.frame()
  .hvti_refuse_ambiguous_order(cl, env, assert_cohort, "assert_cohort", "(data, expected, time_col, event_col)")
  # As in cohort_counts(), the old names partially match the new ones.
  if (.hvti_old_call(cl, env, renamed = c("d", "time", "event"))) {
    .hvti_deprecate("assert_cohort_args",
                    "assert_cohort(): the arguments are now (data, expected, time_col, event_col), as in ",
                    "survival::Surv(). `d =`, `time =` and `event =` are now `data =`, `time_col =` and `event_col =`.")
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
  observed <- cohort_counts(d, time_col = time_col, event_col = event_col)
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
