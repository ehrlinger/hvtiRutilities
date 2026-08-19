#' Tolerance classes for SAS parity comparison
#'
#' Tolerances are derived from what limits agreement for each quantity, not
#' tuned until things pass. Three regimes:
#'
#' * **Printed references are intervals, not numbers.** When SAS prints
#'   `-239.194`, the value that produced it lies in `[-239.1945, -239.1935)`.
#'   Half a unit in the last printed place is a floor that is derived.
#' * **Stored references carry machine precision**, so that floor does not
#'   apply. What remains is that two implementations run different optimizers
#'   on the same likelihood and converge to different points.
#' * **Counts are exact, or there is a bug.**
#'
#' @param class One of `"count"`, `"printed"`, `"loglik"`, `"mle_stored"`,
#'   `"mle_printed"`, `"vcov_stored"`, `"curvature"`.
#' @return A list with `rtol` and `atol`.
#' @export
#' @examples
#' parity_tolerance("loglik")
parity_tolerance <- function(class) {
  table <- list(
    count       = list(rtol = 0,     atol = 0),
    printed     = list(rtol = 0,     atol = NA_real_),  # set from digits
    loglik      = list(rtol = 0,     atol = 0.0005),
    mle_stored  = list(rtol = 1e-6,  atol = 1e-9),
    mle_printed = list(rtol = 1e-3,  atol = 1e-6),
    vcov_stored = list(rtol = 1e-4,  atol = 1e-9),
    curvature   = list(rtol = 1e-2,  atol = 1e-6)
  )
  if (!class %in% names(table)) {
    stop("parity_tolerance(): unknown class '", class, "'. Valid classes: ",
         paste(names(table), collapse = ", "), call. = FALSE)
  }
  table[[class]]
}
