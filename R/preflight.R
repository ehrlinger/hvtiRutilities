#' Audit the analysis environment before running an analysis
#'
#' Reports the version of every package a hazard-family analysis depends on.
#' Run it on the machine that will do the work, before anything else.
#'
#' `numDeriv` is only a *Suggests* of `TemporalHazard`, so `install_github()`
#' does not pull it. Its absence silently costs standard errors on any
#' interval- or left-censored multiphase fit: the analytic multiphase Hessian
#' declines for those statuses by design and the optimizer falls back to
#' `numDeriv`; with it missing there is no third option, and `vcov()` returns a
#' bare logical while `rcond` and `pd` come back `NA` with nothing naming the
#' cause.
#'
#' @param extra Character vector of additional package names to report.
#' @return A data frame with columns `component`, `found`, `version`, `notes`.
#' @export
#' @examples
#' preflight_report()
preflight_report <- function(extra = character(0)) {
  pkgs <- c("TemporalHazard", "hvtiRutilities", "haven", "survival",
            "hvtiPlotR", "testthat", "quarto", "ggplot2", "numDeriv",
            extra)
  pkgs <- unique(pkgs)

  notes <- c(numDeriv = paste(
    "Suggests-only for TemporalHazard; absence silently costs standard",
    "errors on interval- or left-censored multiphase fits."
  ))

  rows <- lapply(pkgs, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)),
                  error = function(e) NA_character_)
    data.frame(component = p,
               found     = !is.na(v),
               version   = if (is.na(v)) "" else v,
               notes     = if (p %in% names(notes)) notes[[p]] else "",
               stringsAsFactors = FALSE)
  })

  rbind(
    data.frame(component = "R",
               found     = TRUE,
               version   = paste(R.version$major, R.version$minor, sep = "."),
               notes     = "",
               stringsAsFactors = FALSE),
    do.call(rbind, rows)
  )
}
