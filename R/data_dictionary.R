#' Build a data dictionary from a labeled dataset
#'
#' @description
#' Creates a summary data frame describing every variable in a dataset:
#' name, label, R class, number of unique values, percent missing, and
#' a compact range or level summary.
#'
#' This is the single most useful artifact for documenting a clinical
#' dataset. It can be written directly to CSV or included in a Quarto
#' document as a table.
#'
#' @param data A data frame, tibble, or similar tabular object.
#'
#' @return A data frame with one row per variable and the following columns:
#' \describe{
#'   \item{variable}{Column name}
#'   \item{label}{Descriptive label (falls back to variable name if unlabeled)}
#'   \item{class}{Primary R class of the column}
#'   \item{n_unique}{Number of unique non-NA values}
#'   \item{pct_missing}{Percentage of rows that are \code{NA} (0-100)}
#'   \item{summary}{Compact summary: min / median / max for numeric,
#'     level counts for factor/character, TRUE percentage for logical}
#' }
#'
#' @seealso \code{\link{label_map}} for extracting labels only,
#'   \code{\link{r_data_types}} for automatic type conversion before building
#'   the dictionary.
#'
#' @export
#'
#' @examples
#' # Quick dictionary from synthetic clinical data
#' dta <- generate_survival_data(n = 100, seed = 42)
#' dict <- data_dictionary(dta)
#' head(dict, 10)
#'
#' # After type conversion
#' dta_clean <- r_data_types(dta,
#'   factor_size = 5,
#'   skip_vars = c("ccfid", "iv_dead", "iv_reop", "iv_opyrs")
#' )
#' dict_clean <- data_dictionary(dta_clean)
#' head(dict_clean, 10)
#'
#' # Write to CSV for documentation
#' \dontrun{
#' write.csv(data_dictionary(dta), "data_dictionary.csv", row.names = FALSE)
#' }
data_dictionary <- function(data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  if (ncol(data) == 0L) {
    return(data.frame(
      variable    = character(),
      label       = character(),
      class       = character(),
      n_unique    = integer(),
      pct_missing = numeric(),
      summary     = character(),
      stringsAsFactors = FALSE
    ))
  }

  labels <- labelled::var_label(data, unlist = TRUE, null_action = "fill")

  data.frame(
    variable    = names(data),
    label       = unname(labels),
    class       = vapply(data, function(x) class(x)[1L], character(1)),
    n_unique    = vapply(data, function(x) length(unique(x[!is.na(x)])), integer(1)),
    pct_missing = vapply(data, function(x) round(mean(is.na(x)) * 100, 1), numeric(1)),
    summary     = vapply(data, .summarise_column, character(1)),
    stringsAsFactors = FALSE
  )
}

## Internal helper: one-line summary per column type
.summarise_column <- function(x) {
  vals <- x[!is.na(x)]
  if (length(vals) == 0L) return("all NA")

  if (is.numeric(vals)) {
    sprintf("%.4g / %.4g / %.4g",
            min(vals), stats::median(vals), max(vals))
  } else if (is.logical(vals)) {
    sprintf("TRUE: %.0f%%", mean(vals) * 100)
  } else if (is.factor(vals) || is.character(vals)) {
    lvls <- if (is.factor(vals)) levels(vals) else sort(unique(vals))
    n <- length(lvls)
    preview <- paste(utils::head(lvls, 5), collapse = ", ")
    if (n > 5) preview <- paste0(preview, ", ...")
    sprintf("%d levels: %s", n, preview)
  } else if (inherits(vals, c("Date", "POSIXct", "POSIXlt"))) {
    sprintf("%s / %s", min(vals), max(vals))
  } else {
    paste(class(vals)[1L], "column")
  }
}
