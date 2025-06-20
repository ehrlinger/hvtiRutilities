##=============================================================================
#' Build a lookup map of data labels
#' @description builds a
#'
#' @param built a dataset with sas labels
#'
#' @return a hash function with label:key pairs
#'
#' # Build the map.
#' avsd_label_map <- label_map(avsd_raw)
#' dta$label <- avsd_label_map$label[match(dta$name, avsd_label_map$key)]
#'
#'
#' @export
label_map = function(built) {
  return(data.frame(
    key = names(built),
    label = built |>
      labelled::var_label(unlist = T, null_action = "fill")
  ))
}
