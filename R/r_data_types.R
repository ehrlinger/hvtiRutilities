# The character values that stand in for a missing observation in exported
# clinical data. Held here so the dispatcher and its tests agree on the list.
.na_strings <- c("NA", "na", "Na", "nA")

# Convert one column and say why.
#
# This is the only place a conversion decision is made. Returning the rule
# alongside the value is what keeps type_conversion_report() from being a
# second, drifting description of what the conversion does -- a report derived
# from a separate predicate can disagree with the data it claims to describe,
# and the disagreement is invisible.
#
# Branch order reproduces the four dplyr::across() passes this replaced:
# NA strings, binary-to-logical, character-to-factor, n_distinct-to-factor,
# then the optional logical-to-factor. The value-label branch is new and runs
# ahead of all of them, because a declared type beats an inferred one.
.convert_column <- function(x, factor_size, binary_factor, use_value_labels) {
  storage_in <- class(x)[1]
  out <- function(value, rule, level_source = NA_character_) {
    list(value = value, rule = rule, level_source = level_source,
         storage_in = storage_in)
  }

  # Dates and times are never altered by type conversion.
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) {
    return(out(x, "unchanged"))
  }

  has_val_labels <- inherits(x, "haven_labelled") &&
    length(labelled::val_labels(x)) > 0L

  if (has_val_labels && use_value_labels) {
    # nolabel_to_na = FALSE is the default and is named because this code
    # depends on it: a code the catalogue does not cover survives as its own
    # level rather than becoming NA. Losing an uncatalogued code silently is
    # the failure this branch exists to prevent, so it is not left to a
    # default that could move.
    return(out(labelled::to_factor(x, nolabel_to_na = FALSE),
               "value_labels", "value labels"))
  }

  # Value labels are not being used. Drop them rather than carrying them into
  # the numeric branches: as.logical() has no vctrs cast from haven_labelled
  # and aborts, which made a two-valued formatted SAS variable an error.
  if (inherits(x, "haven_labelled")) {
    x <- haven::zap_labels(x)
  }

  if (is.character(x)) {
    for (s in .na_strings) {
      x <- dplyr::na_if(x, s)
    }
  }

  n <- dplyr::n_distinct(x, na.rm = TRUE)

  # A column that is already logical is excluded rather than passed through
  # as.logical() as a no-op. The output is identical either way, but a matched
  # rule that changes nothing would have to report itself as "unchanged" --
  # which the report defines as no rule matching at all.
  if (!is.factor(x) && !is.character(x) && !is.logical(x) && n == 2L) {
    x <- as.logical(x)
    if (binary_factor) {
      return(out(factor(x, exclude = NA), "binary_factor", "inference"))
    }
    return(out(x, "binary_logical"))
  }

  if (is.character(x)) {
    return(out(factor(x, exclude = NA), "character_factor", "inference"))
  }

  if (n < factor_size && n > 2L && !is.factor(x) && is.numeric(x)) {
    return(out(factor(x, exclude = NA), "n_distinct_factor", "inference"))
  }

  # A column that was already logical and did not take the binary branch --
  # all-NA, or a single distinct value.
  if (binary_factor && is.logical(x)) {
    return(out(factor(x, exclude = NA), "binary_factor", "inference"))
  }

  out(x, "unchanged")
}

#' Automatically infer and convert data types
#'
#' @description
#' Intelligently converts column types in a dataset based on their content.
#' Handles character-to-factor conversion, binary numeric variables, and
#' various NA representations. Preserves variable labels from SAS/labelled data.
#'
#' @details
#' Each column is converted by the first rule that matches, in this order:
#' \enumerate{
#'   \item When \code{use_value_labels = TRUE} and the column carries value
#'     labels, they become the factor levels. This runs ahead of every rule
#'     below: a declared type is not subject to a threshold on distinct
#'     values.
#'   \item Character strings "NA", "na", "Na" and "nA" become \code{NA}.
#'   \item Numeric or integer columns with exactly 2 distinct values become
#'     logical, or factors when \code{binary_factor = TRUE}.
#'   \item Remaining character columns become factors.
#'   \item Numeric columns with 3 to \code{factor_size} distinct values
#'     become factors.
#'   \item Logical columns become factors when \code{binary_factor = TRUE}.
#' }
#'
#' Date, POSIXct, and POSIXlt columns are never altered by type conversion.
#'
#' Which rule fired on which column is recorded on the result and read back
#' with \code{\link{type_conversion_report}}.
#'
#' @param dataset A data frame, tibble, data.table, or similar tabular object
#' @param factor_size Integer threshold for factor conversion. Numeric variables
#'   with fewer than this many unique values (but more than 2) will be converted
#'   to factors. Must be between 2 and 50. Default is 10.
#' @param skip_vars Character vector of column names to exclude from conversion.
#'   These columns will remain unchanged. Default is NULL (convert all columns).
#' @param binary_factor Logical. If TRUE, binary variables are converted to
#'   factors instead of logical. Default is FALSE (convert to logical).
#' @param use_value_labels Logical. If TRUE, a column carrying value labels --
#'   what \pkg{haven} reads from a SAS numeric-plus-format variable -- is
#'   converted through \code{\link[labelled]{to_factor}}, so the level text is
#'   kept. If FALSE the value labels are dropped and the numeric codes are
#'   converted instead. Default is FALSE, which warns once per session; the
#'   default becomes TRUE in a later release.
#'
#' @return An object of the same class as \code{dataset} with columns
#'   converted according to the function's rules. Variable labels are
#'   preserved. The result carries a per-column conversion report, read with
#'   \code{\link{type_conversion_report}}.
#'
#' @seealso \code{\link{type_conversion_report}} for the record of which rule
#'   fired on which column.
#'
#' @export r_data_types
#'
#' @examples
#' # Basic usage with sample data
#' dta <- sample_data(n = 100)
#' str(dta)  # Original types
#' dta_converted <- r_data_types(dta, use_value_labels = FALSE)
#' str(dta_converted)  # Converted types
#'
#' # Real data example with mtcars
#' str(datasets::mtcars$vs)  # numeric (0/1)
#' mtcars_converted <- r_data_types(datasets::mtcars,
#'                                  use_value_labels = FALSE)
#' str(mtcars_converted$vs)  # logical (FALSE/TRUE)
#'
#' # Skip specific columns
#' mtcars_partial <- r_data_types(datasets::mtcars,
#'                                skip_vars = c("vs", "am"),
#'                                use_value_labels = FALSE)
#' str(mtcars_partial$vs)  # Still numeric (unchanged)
#'
#' # Control factor creation threshold
#' mtcars_strict <- r_data_types(datasets::mtcars, factor_size = 5,
#'                               use_value_labels = FALSE)
#'
#' # Keep binary variables as factors
#' mtcars_factors <- r_data_types(datasets::mtcars, binary_factor = TRUE,
#'                                use_value_labels = FALSE)
#' str(mtcars_factors$vs)  # Factor instead of logical
#'
#' # Keep the level text of a SAS formatted variable
#' disp <- haven::labelled(c(1, 2, 1, 3),
#'                         labels = c(Home = 1, Rehab = 2, SNF = 3),
#'                         label  = "Discharge disposition")
#' converted <- r_data_types(data.frame(disp = disp), use_value_labels = TRUE)
#' levels(converted$disp)
#' type_conversion_report(converted)
r_data_types <- function(dataset,
                         factor_size = 10,
                         skip_vars = NULL,
                         binary_factor = FALSE,
                         use_value_labels = FALSE) {
  if (missing(use_value_labels) &&
        is.null(.hvti_deprecated$use_value_labels)) {
    .hvti_deprecated$use_value_labels <- TRUE
    warning(
      "r_data_types(): 'use_value_labels' defaults to FALSE, so a column ",
      "carrying SAS value labels is converted from its numeric codes and ",
      "the level text -- Home, Rehab, SNF -- is discarded. Pass ",
      "use_value_labels = TRUE to convert through the labels instead, or ",
      "FALSE to silence this warning. The default will become TRUE in a ",
      "later release.",
      call. = FALSE
    )
  }

  # Validate inputs before doing any work
  if (!is.data.frame(dataset)) {
    stop("'dataset' must be a data.frame or similar tabular object.")
  }

  if (!is.numeric(factor_size) || is.nan(factor_size) || factor_size <= 1) {
    stop("'factor_size' must be a numeric value greater than 1.")
  } else if (factor_size %% 1 != 0) {
    stop("'factor_size' must be a whole number (integer).")
  } else if (factor_size > 50) {
    stop("'factor_size' must be 50 or less to avoid excessive factor creation. You specified ", factor_size, ".")
  }

  if (!is.null(skip_vars)) {
    if (!is.character(skip_vars)) {
      stop("'skip_vars' must be a character vector of column names.")
    }
    if (any(!(skip_vars %in% colnames(dataset)))) {
      stop("One or more columns in 'skip_vars' not found in dataset.")
    }
  }

  # Retain all labels for our data
  keep_label <- labelled::var_label(dataset, unlist = FALSE,
                                    null_action = "fill")

  # Separate our skipped columns if needed first.
  if (!is.null(skip_vars)) {
    skip_dta <- dataset |> dplyr::select(dplyr::all_of(skip_vars))
    new_data <- dataset |> dplyr::select(!dplyr::all_of(skip_vars))
  } else {
    new_data <- dataset
  }

  # Convert Variables to new types
  converted <- lapply(new_data, .convert_column,
                      factor_size      = factor_size,
                      binary_factor    = binary_factor,
                      use_value_labels = use_value_labels)
  # `[]<-` rather than a rebuild: it preserves the tibble/data.table class of
  # the input, which the contract promises and the extended tests assert.
  new_data[] <- lapply(converted, `[[`, "value")

  # Restore skipped columns in original order
  if (!is.null(skip_vars)) {
    # Combine processed and skipped data
    combined <- dplyr::bind_cols(new_data, skip_dta)
    # Restore original column order
    combined <- combined[, names(dataset), drop = FALSE]
    new_data <- combined
  }

  labelled::var_label(new_data) <- keep_label
  attr(new_data, "hvti_type_conversion") <-
    .type_report(converted, dataset, skip_vars)
  new_data
}
