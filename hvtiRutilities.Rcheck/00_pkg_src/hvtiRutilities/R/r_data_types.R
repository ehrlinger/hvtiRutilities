#' Automatically infer and convert data types
#'
#' @description
#' Intelligently converts column types in a dataset based on their content.
#' Handles character-to-factor conversion, binary numeric variables, and
#' various NA representations. Preserves variable labels from SAS/labelled data.
#'
#' @details
#' The function applies the following transformations in order:
#' \enumerate{
#'   \item Converts character strings "NA", "na", "Na", "nA" to actual NA values
#'   \item Converts numeric/integer columns with exactly 2 unique values to logical
#'   \item Converts remaining character columns to factors
#'   \item Converts numeric columns with 3 to \code{factor_size} unique values to factors
#'   \item Optionally converts logical columns to factors if \code{binary_factor = TRUE}
#' }
#'
#' @param dataset A data frame, tibble, data.table, or similar tabular object
#' @param factor_size Integer threshold for factor conversion. Numeric variables
#'   with fewer than this many unique values (but more than 2) will be converted
#'   to factors. Must be between 2 and 50. Default is 10.
#' @param skip_vars Character vector of column names to exclude from conversion.
#'   These columns will remain unchanged. Default is NULL (convert all columns).
#' @param binary_factor Logical. If TRUE, binary variables are converted to factors
#'   instead of logical. Default is FALSE (convert to logical).
#'
#' @return An object of the same class as \code{dataset} with columns converted
#'   according to the function's rules. Variable labels are preserved.
#'
#' @export r_data_types
#'
#' @examples
#' # Basic usage with sample data
#' dta <- sample_data(n = 100)
#' str(dta)  # Original types
#' dta_converted <- r_data_types(dta)
#' str(dta_converted)  # Converted types
#'
#' # Real data example with mtcars
#' str(datasets::mtcars$vs)  # numeric (0/1)
#' mtcars_converted <- r_data_types(datasets::mtcars)
#' str(mtcars_converted$vs)  # logical (FALSE/TRUE)
#'
#' # Skip specific columns
#' mtcars_partial <- r_data_types(datasets::mtcars, skip_vars = c("vs", "am"))
#' str(mtcars_partial$vs)  # Still numeric (unchanged)
#'
#' # Control factor creation threshold
#' mtcars_strict <- r_data_types(datasets::mtcars, factor_size = 5)
#'
#' # Keep binary variables as factors
#' mtcars_factors <- r_data_types(datasets::mtcars, binary_factor = TRUE)
#' str(mtcars_factors$vs)  # Factor instead of logical
r_data_types <- function(dataset,
                         factor_size = 10,
                         skip_vars = NULL,
                         binary_factor = FALSE) {
  # Retain all labels for our data
  keep_label <- labelled::var_label(dataset, unlist = FALSE,
                                    null_action = "fill")

  # Separate our skipped columns if needed first.
  if (!is.null(skip_vars) && all(skip_vars %in% colnames(dataset))) {
    skip_dta <- dataset |> dplyr::select(dplyr::all_of(skip_vars))
    new_data <- dataset |> dplyr::select(!dplyr::all_of(skip_vars))
  } else if (!is.null(skip_vars) &&
             any(!(skip_vars %in% colnames(dataset)))) {
    stop("One or more columns in 'skip_vars' not found in dataset.")
  } else {
    new_data <- dataset
  }

  # Check factorsize
  if (!is.numeric(factor_size) || factor_size <= 1) {
    stop("'factor_size' must be a numeric value greater than 1.")
  } else if (factor_size %% 1 != 0) {
    stop("'factor_size' must be a whole number (integer).")
  } else if (factor_size > 50) {
    stop("'factor_size' must be 50 or less to avoid excessive factor creation. You specified ", factor_size, ".")
  }

  # Convert Variables to new types
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(is.character),
                                                    ~ . |>
                                                      dplyr::na_if("na") |>
                                                      dplyr::na_if("NA") |>
                                                      dplyr::na_if("Na") |>
                                                      dplyr::na_if("nA")))
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(function(x) {
    !is.factor(x) &
      !is.character(x) &
      dplyr::n_distinct(x, na.rm = TRUE) < 3
  }), ~ as.logical(.)))
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(is.character),
                                                    ~ factor(., exclude = NA)))
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(function(x) {
    dplyr::n_distinct(x, na.rm = TRUE) < factor_size &
      dplyr::n_distinct(x, na.rm = TRUE) > 2 &
      !is.factor(x) & is.numeric(x)
  }), ~ factor(., exclude = NA)))

  # Opt to convert binary variables into factors, rather than logical data.
  if (binary_factor) {
    new_data <- dplyr::mutate(new_data,
                              dplyr::across(dplyr::where(is.logical),
                                            ~ factor(., exclude = NA)))
  }

  # Restore skipped columns in original order
  if (!is.null(skip_vars)) {
    # Combine processed and skipped data
    combined <- dplyr::bind_cols(new_data, skip_dta)
    # Restore original column order
    combined <- combined[, names(dataset), drop = FALSE]
    new_data <- combined
  }

  labelled::var_label(new_data) <- keep_label
  new_data
}
