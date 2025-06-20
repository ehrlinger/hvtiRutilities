#' Handle type conversion and NA assignment for general cases.
#'
#' @param dataset input data
#' @param factor_size If a feature has fewer than factor_size unique
#'  values, make it a factor.
#'
#' @return data.frame with column types correctly set.
#'
#' @export r_data_types
r_data_types = function(dataset, factor_size = 10) {
  ## Make sure NA is correctly encoded
  new_data = dataset
  new_data <- new_data |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character), ~ na_if(., "na")))
  new_data <- new_data |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character), ~ na_if(., "NA")))

  ##                   Auto encode logicals and factors
  ## Set modes correctly. For binary variables: transform to logical
  ## Check for range of 0,1, NA
  new_data <- new_data |>
    dplyr::mutate(dplyr::across(dplyr::where(\(x) dplyr::n_distinct(x, na.rm = TRUE) < 3), ~ as.logical(.)))

  # Convert character features to factors
  new_data <- new_data |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character), ~ factor(. , exclude = NA)))

  ## Convert features with fewer than n=10 unique values
  ## to factor
  new_data <- new_data |>
    dplyr::mutate(dplyr::across(
      dplyr::where(
        \(x) dplyr::n_distinct(x, na.rm = TRUE) < factor_size &
          dplyr::n_distinct(x, na.rm = TRUE) > 2 &
          is.numeric(x)
      ),
      ~ factor(. , exclude = NA)
    ))

  return(new_data)
}
