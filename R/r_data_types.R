#' Handle type conversion and NA assignment for general cases.
#'
#' @param dataset input data
#' @param factor_size If a feature has fewer than factor_size unique
#'  values, make it a factor.
#'
#' @return data.frame with column types correctly set.
#'
#' @import lubridate
#' @export r_data_types
### Update to function
r_data_types = function(dataset, factor_size = 10) {
  keep_label = labelled::var_label(dataset, unlist = F, null_action = "fill")

  new_data = dataset
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(is.character), ~
                                                      dplyr::na_if(., "na")))
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(is.character), ~
                                                      dplyr::na_if(., "NA")))
  new_data <- dplyr::mutate(new_data, dplyr::across(
    dplyr::where(function(x)
      ! is.factor(x) &
        dplyr::n_distinct(x, na.rm = TRUE) < 3),
    ~ as.logical(.)
  ))
  new_data <- dplyr::mutate(new_data, dplyr::across(dplyr::where(is.character), ~
                                                      factor(., exclude = NA)))
  new_data <- dplyr::mutate(new_data, dplyr::across(
    dplyr::where(
      function(x)
        dplyr::n_distinct(x, na.rm = TRUE) < factor_size &
        dplyr::n_distinct(x, na.rm = TRUE) >
        2 &
        !is.factor(x) & is.numeric(x)
    ),
    ~ factor(., exclude = NA)
  ))

  labelled::var_label(new_data) = keep_label
  return(new_data)
}
