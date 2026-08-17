# The cohort gate. A build that changes the analysable cohort must fail every
# job rather than quietly producing different numbers, so a rendered page is
# itself evidence that this gate passed.

#' Count the analysable cohort
#'
#' @description
#' Counts rows for which both the event and the time column declared in
#' \code{_study.yml} are present, and the events among them.
#'
#' \strong{The missingness filter may be vacuous on a given study.} Where the
#' upstream build has already filtered the cohort, both columns have no missing
#' values and this reduces to \code{nrow(d)} and the event total. The filter is
#' kept because it is the correct definition of analysable and it stops a
#' future dataset with genuine missingness from being miscounted - but a
#' passing cohort gate is not evidence that the filtering works.
#'
#' The event column may arrive logical or numeric depending on the read path,
#' so the comparison is against \code{1}, which is correct for both. Do not
#' simplify it to \code{sum(d[[event]])}.
#'
#' @param d A data frame, typically from \code{\link{read_built}}.
#' @param cfg List. A study manifest from \code{\link{study_config}}; supplies
#'   \code{cohort$event} and \code{cohort$time}.
#'
#' @return A list with integer elements \code{n}, \code{n_events} and
#'   \code{n_censored}.
#'
#' @seealso \code{\link{assert_cohort}}
#'
#' @export
#'
#' @examples
#' cfg <- list(cohort = list(event = "dead", time = "iv_dead"))
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' cohort_counts(d, cfg)
cohort_counts <- function(d, cfg = study_config()) {
  event <- cfg$cohort$event
  time  <- cfg$cohort$time

  missing_cols <- setdiff(c(event, time), names(d))
  if (length(missing_cols)) {
    stop("cohort_counts(): data has no column",
         if (length(missing_cols) > 1) "s" else "", " named ",
         paste(missing_cols, collapse = ", "),
         ". The cohort columns are declared in _study.yml.", call. = FALSE)
  }

  ok <- !is.na(d[[time]]) & !is.na(d[[event]])
  n  <- sum(ok)
  ev <- sum(d[[event]][ok] == 1)

  list(n          = as.integer(n),
       n_events   = as.integer(ev),
       n_censored = as.integer(n - ev))
}

#' Assert the cohort matches the study manifest
#'
#' @description
#' Compares \code{\link{cohort_counts}} against the \code{cohort} block of
#' \code{_study.yml} and errors on any disagreement. Call it before any
#' analysis that would otherwise run happily on an unreconciled cohort.
#'
#' @param d A data frame, typically from \code{\link{read_built}}.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return \code{invisible(TRUE)} on success; otherwise an error.
#'
#' @seealso \code{\link{cohort_counts}}
#'
#' @export
#'
#' @examples
#' cfg <- list(cohort = list(n = 5L, n_events = 2L, n_censored = 3L,
#'                           event = "dead", time = "iv_dead"))
#' d <- data.frame(dead = c(1, 1, 0, 0, 0), iv_dead = 1:5)
#' assert_cohort(d, cfg)
assert_cohort <- function(d, cfg = study_config()) {
  cc   <- cohort_counts(d, cfg)
  want <- list(n          = as.integer(cfg$cohort$n),
               n_events   = as.integer(cfg$cohort$n_events),
               n_censored = as.integer(cfg$cohort$n_censored))

  if (!identical(cc, want)) {
    stop("cohort gate: expected N=", want$n, " / events=", want$n_events,
         " / censored=", want$n_censored,
         ", got N=", cc$n, " / events=", cc$n_events,
         " / censored=", cc$n_censored,
         ". Analysis must not run on an unreconciled cohort.", call. = FALSE)
  }
  invisible(TRUE)
}
