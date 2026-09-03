# Assemble the per-column record of what r_data_types() did.
#
# Built from the dispatcher's own return value, not from a second reading of
# the data, so a row cannot describe a rule other than the one that ran.
# Skipped columns never reach the dispatcher and are filled in here.
.type_report <- function(converted, dataset, skip_vars) {
  row <- function(variable, storage_in, rule, level_source, value) {
    data.frame(
      variable     = variable,
      storage_in   = storage_in,
      rule         = rule,
      level_source = level_source,
      n_levels     = if (is.factor(value)) {
        length(levels(value))
      } else {
        NA_integer_
      },
      storage_out  = class(value)[1],
      stringsAsFactors = FALSE
    )
  }

  rows <- lapply(names(dataset), function(v) {
    if (v %in% skip_vars) {
      col <- dataset[[v]]
      return(row(v, class(col)[1], "skipped", NA_character_, col))
    }
    r <- converted[[v]]
    row(v, r$storage_in, r$rule, r$level_source, r$value)
  })

  if (!length(rows)) {
    return(data.frame(variable = character(0), storage_in = character(0),
                      rule = character(0), level_source = character(0),
                      n_levels = integer(0), storage_out = character(0),
                      stringsAsFactors = FALSE))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Read the per-column type-conversion report
#'
#' @description
#' Returns the record \code{\link{r_data_types}} attaches to its result: one
#' row per column, naming the rule that fired and where the levels came from.
#'
#' @details
#' A column that became a factor because it was \emph{declared} one, and a
#' column that became a factor because it happened to have seven distinct
#' values, are otherwise the same object. This is how a caller tells them
#' apart.
#'
#' The columns are:
#' \itemize{
#'   \item \code{variable} -- the column name.
#'   \item \code{storage_in} -- its class as received, before conversion.
#'   \item \code{rule} -- one of \code{"value_labels"}, \code{"binary_logical"},
#'     \code{"binary_factor"}, \code{"character_factor"},
#'     \code{"n_distinct_factor"}, \code{"unchanged"} or \code{"skipped"}.
#'     \code{"unchanged"} means every rule was tested and none fired;
#'     \code{"skipped"} means the column was named in \code{skip_vars} and no
#'     rule was tested.
#'   \item \code{level_source} -- \code{"value labels"} where the levels came
#'     from the column's own value labels, \code{"inference"} where they came
#'     from counting distinct values, and \code{NA} where no levels were made.
#'   \item \code{n_levels} -- levels produced, or \code{NA} for a non-factor.
#'   \item \code{storage_out} -- the class of the returned column.
#' }
#'
#' The report is an attribute of the returned object. Operations that rebuild
#' a data frame -- most \pkg{dplyr} verbs among them -- drop it. Read it
#' directly from the \code{r_data_types()} result.
#'
#' @param x An object returned by \code{\link{r_data_types}}.
#'
#' @return A data frame with columns \code{variable}, \code{storage_in},
#'   \code{rule}, \code{level_source}, \code{n_levels} and \code{storage_out},
#'   one row per column of the converted dataset, in column order.
#'
#' @seealso \code{\link{r_data_types}}
#'
#' @export type_conversion_report
#'
#' @examples
#' converted <- r_data_types(datasets::mtcars, use_value_labels = FALSE)
#' type_conversion_report(converted)
type_conversion_report <- function(x) {
  report <- attr(x, "hvti_type_conversion", exact = TRUE)
  if (is.null(report)) {
    stop("No type-conversion report on this object: it did not come from ",
         "r_data_types(), or an intervening operation dropped its ",
         "attributes.", call. = FALSE)
  }
  report
}
