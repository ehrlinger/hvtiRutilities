#' Handle type conversion and NA assignment for general cases.
#'
#' @param dataset input data
#' @param factor_size If a feature has fewer than factor_size unique
#'  values, make it a factor.
#' @param skip name of column to NOT convert.
#'
#' @return data.frame with column types correctly set.
#'
#' @import lubridate
#' @export r_data_types
#' @examples
#'  datasets::mtcars
#'   mtcars$vs # binary but numeric coding
#'   mtcars |> r_data_types(skip = "vs") # compare vs and am binary variables

### Update to function
r_data_types = function (dataset, factor_size = 10, skip = NULL) {

  if(!is.null(skip)) {
    skip_var = dataset |> dplyr::select(dplyr::all_of(skip))
  }

  keep_label = labelled::var_label(dataset, unlist = F, null_action = "fill")
  new_data <- dataset |> dplyr::select(!dplyr::all_of(skip)) |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character),
                                ~ dplyr::na_if(., "na"))) |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character),
                                ~ dplyr::na_if(., "NA"))) |>
    dplyr::mutate(dplyr::across(
      dplyr::where(function(x)
        ! is.factor(x) &
          dplyr::n_distinct(x, na.rm = TRUE) < 3),
      ~ as.logical(.)
    )) |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character),
                                ~factor(., exclude = NA))) |>
    dplyr::mutate(dplyr::across(
      dplyr::where(
        function(x)
          dplyr::n_distinct(x, na.rm = TRUE) < factor_size &
          dplyr::n_distinct(x, na.rm = TRUE) >
          2 &
          !is.factor(x) & is.numeric(x)
      ),
      ~ factor(., exclude = NA)
    ))

  if (!is.null(skip)) {
    new_data = cbind(new_data, skip_var)
  }

  labelled::var_label(new_data) = keep_label
  return(new_data)
}

