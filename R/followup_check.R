#' Check recorded follow-up before a time-related analysis
#'
#' @description
#' Summarises an event indicator and its follow-up intervals the way the
#' `dc-gfup` template reports them: counts for the whole cohort and its
#' event and censored subsets, the missing, negative and zero intervals, a
#' [proc_means()] table for each subset, and the rows worth a second
#' look. It checks recorded follow-up; it does not establish completeness
#' against a close date.
#'
#' @details
#' Every argument is checked before anything is computed, and every column
#' that is not in `data` is named in one error, so a job with three
#' misspellings says so once.
#'
#' A row with a missing event is counted in `missing_event` and belongs
#' to neither the event nor the censored subset. A row is *suspicious*
#' when its event is missing or any of its intervals is missing, negative or
#' zero.
#'
#' The quartiles in `intervals` use R's default interpolated quantiles
#' (`type = 7`), while [proc_means()] uses the SAS
#' `QNTLDEF=5` estimator, so a median in the two tables can disagree on
#' a small subset. The difference is deliberate: `intervals` is a quick
#' screen, and `means` is the table to compare against SAS.
#'
#' `means` reports the 15th and 85th percentiles rather than the
#' quartiles, because those are what the group's descriptive summaries show.
#' SAS `PROC MEANS` prints no percentiles unless asked, so a parity
#' comparison names the same statistics on the SAS side, or passes the SAS
#' job's list to `stats`.
#'
#' Identifiers are never included unless named in `identifier`. Check the
#' result before sharing a report that shows `review` with one.
#'
#' @param data A data frame, one row per patient.
#' @param time Names of one or more follow-up interval columns, in years.
#'   Was `followup` before 2026-11; `followup =` still works for one
#'   release, with a warning.
#' @param event Name of the event indicator: 1 or `TRUE` for an event, 0
#'   or `FALSE` for censored. Missing values are allowed and counted.
#' @param identifier `NULL` (the default), or the name of one column to
#'   show in `review`.
#' @param max_rows The most suspicious rows to return in `review`, in data
#'   order. Default 25.
#' @param stats Character vector of SAS statistic keywords for the
#'   `means` tables, passed to [proc_means()] and validated the
#'   same way. Default
#'   `c("n", "nmiss", "mean", "std", "min", "p15", "median", "p85", "max")`.
#'
#' @param followup Deprecated: the old name of `time`, kept for one release.
#' @return An object of class `followup_check`, a list of four
#'   components, three data frames and a list of three:
#' \describe{
#'   \item{`cohort`}{One row: `full`, `event`, `censored`
#'     and `missing_event` counts.}
#'   \item{`intervals`}{One row per interval: `missing`,
#'     `negative` and `zero` counts, then `min`, `q1`,
#'     `median`, `q3`, `mean`, `sd` and `max` of the
#'     observed values.}
#'   \item{`means`}{A named list, `full`, `event` and
#'     `censored`, of [proc_means()] tables over the
#'     intervals, one column per statistic in `stats`.}
#'   \item{`review`}{Up to `max_rows` suspicious rows, with the
#'     event, the intervals and any `identifier`.}
#' }
#'
#' @seealso [proc_means()], [cohort_counts()], which counts
#'   the analysable cohort rather than checking follow-up.
#'
#' @examples
#' d <- data.frame(dead = c(1, 0, 0, NA, 1), iv_dead = c(2.5, 4, 0, 1.2, NA))
#' fc <- followup_check(d, time = "iv_dead", event = "dead")
#' fc
#' fc$cohort
#' fc$review
#' @export
followup_check <- function(data, time, event, identifier = NULL, max_rows = 25L,
                           stats = c("n", "nmiss", "mean", "std", "min", "p15", "median", "p85", "max"),
                           followup) {
  cl <- sys.call()
  env <- parent.frame()
  if (.hvti_old_call(cl, env, renamed = "followup", positional = 3L)) {
    .hvti_deprecate("followup_check_args",
                    "followup_check(): the arguments are now (data, time, event, ...), as in survival::Surv(). ",
                    "`followup =` is now `time =`, and two unnamed arguments after the data are read in the ",
                    "old order, event then follow-up, for one more release. Name them: time =, event =.")
    # Errors name the argument the caller wrote, so an old `followup =` caller
    # still reads `followup` in them for the one release the shim lives.
    arg <- if ("followup" %in% names(.hvti_call_args(cl, env))) "followup" else "time"
    return(.hvti_recall(cl, env,
                        function(data, event, followup, identifier = NULL, max_rows = 25L, stats) NULL,
                        function(...) .followup_check(..., arg = arg), c(followup = "time")))
  }
  .followup_check(data, time, event, identifier, max_rows, stats)
}

.followup_check <- function(data, time, event, identifier = NULL, max_rows = 25L,
                            stats = eval(formals(followup_check)$stats), arg = "time") {
  followup <- time
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  field_names <- function(x) is.character(x) && length(x) > 0L && !anyNA(x) && all(nzchar(x)) && !anyDuplicated(x)
  if (!field_names(event) || length(event) != 1L) stop("`event` must name one column.", call. = FALSE)
  if (!field_names(followup)) stop("`", arg, "` must name one or more distinct columns.", call. = FALSE)
  if (!is.null(identifier) && (!field_names(identifier) || length(identifier) != 1L)) {
    stop("`identifier` must be NULL or one column name.", call. = FALSE)
  }
  if (!is.numeric(max_rows) || length(max_rows) != 1L || is.na(max_rows) ||
        !is.finite(max_rows) || max_rows < 1 || max_rows != floor(max_rows)) {
    stop("`max_rows` must be one positive integer.", call. = FALSE)
  }
  .validate_stats(stats)
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
    stop("`", arg, "` columns must be numeric: ", paste(not_numeric, collapse = ", "), call. = FALSE)
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
  means <- lapply(subsets, function(s) proc_means(s, vars = followup, stats = stats))
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
