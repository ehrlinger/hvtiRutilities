#' Compare one R quantity against its SAS reference
#'
#' Errors -- never warns, never skips -- when the quantity is absent on either
#' side. A comparison that cannot fail is worse than no comparison.
#'
#' The outcome is three-state. \code{R_BETTER} fires only for a log-likelihood
#' that exceeds SAS's beyond tolerance: a multi-start optimizer regularly beats
#' a single-start one, and recording that as a failure would train the reader
#' to distrust a real improvement.
#'
#' @param quantity Name of the quantity, used in the report.
#' @param r Value computed in R.
#' @param sas Value from the SAS reference.
#' @param class Tolerance class; see \code{\link{parity_tolerance}}.
#' @param source Where the SAS value came from -- \code{"lst"} or
#'   \code{"outhaz"}.
#' @param digits For \code{class = "printed"}, the number of decimal places
#'   the reference was printed to, as a single non-negative whole number. The
#'   tolerance becomes half of the last place.
#' @section Relative discrepancy at a zero reference:
#' When the SAS value is zero there is no relative scale. The reported
#' \code{rel_diff} is \code{0} if the two agree exactly and \code{Inf}
#' otherwise -- never \code{NA}, which \code{\link{parity_headline}} would
#' drop, reporting a real failure as no discrepancy at all.
#' @return A one-row data frame.
#' @export
#' @examples
#' compare_parity("log_likelihood", r = -239.1941, sas = -239.194,
#'                class = "loglik")
compare_parity <- function(quantity, r, sas, class, source = "lst",
                           digits = NA_integer_) {
  absent <- function(x) is.null(x) || length(x) != 1L || is.na(x)
  if (absent(r) || absent(sas)) {
    stop("compare_parity(): '", quantity, "' is absent on ",
         if (absent(r)) "the R side" else "the SAS side",
         ". Every requested quantity must be present on both sides -- a ",
         "comparison that cannot fail is worse than no comparison.",
         call. = FALSE)
  }

  tol <- parity_tolerance(class)
  if (class == "printed") {
    if (length(digits) != 1L || !is.numeric(digits) || is.na(digits) ||
        digits < 0 || digits != trunc(digits)) {
      stop("compare_parity(): class 'printed' needs `digits`, a single ",
           "non-negative whole number -- the decimal places '", quantity,
           "' was printed to.", call. = FALSE)
    }
    tol$atol <- 0.5 * 10^(-digits)
  }

  abs_diff <- abs(r - sas)
  # A zero reference has no relative scale, but NA would be worse than
  # useless: parity_headline() takes a max with na.rm = TRUE, so a real
  # discrepancy at a zero reference would be dropped and reported as no
  # discrepancy at all.
  rel_diff <- if (sas == 0) {
    if (abs_diff == 0) 0 else Inf
  } else {
    abs_diff / abs(sas)
  }
  within <- abs_diff <= tol$atol + tol$rtol * abs(sas)

  outcome <- if (within) {
    "PASS"
  } else if (identical(quantity, "log_likelihood") && r > sas) {
    "R_BETTER"
  } else {
    "DIFFERS"
  }

  data.frame(quantity = quantity, r = r, sas = sas, source = source,
             abs_diff = abs_diff, rel_diff = rel_diff,
             rtol = tol$rtol, atol = tol$atol, outcome = outcome,
             stringsAsFactors = FALSE)
}

#' Summarise a parity table as one reviewer-facing claim
#'
#' The headline, not the badge, is the claim to report. It is falsifiable and
#' independent of whatever thresholds were chosen. A maximum relative
#' discrepancy of exactly zero across many quantities is not a triumph -- it
#' means nothing was really compared -- so it is flagged rather than
#' celebrated.
#'
#' @param df A data frame of \code{\link{compare_parity}} rows.
#' @return A single string.
#' @export
#' @examples
#' parity_headline(compare_parity("a", 1.0001, 1, class = "mle_printed"))
parity_headline <- function(df) {
  n <- nrow(df)
  worst <- suppressWarnings(max(df$rel_diff, na.rm = TRUE))
  # -Inf is max() of nothing comparable; +Inf is a real discrepancy against a
  # zero reference and must survive to the headline.
  if (is.infinite(worst) && worst < 0) worst <- 0
  fmt <- paste("Across %d compared quantities, the largest relative",
               "discrepancy was %.2e.")
  base <- sprintf(fmt, n, worst)
  if (worst == 0) {
    paste(base,
          "A maximum relative discrepancy of exactly zero is a warning sign,",
          "not a result -- check that the comparison is reaching real values.")
  } else {
    base
  }
}
