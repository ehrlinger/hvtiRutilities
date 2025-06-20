##=============================================================================
## Build a lookup map of data labels
#'
#' ### Insert new labels at the end
#' labelled::var_label(built) = list(
#'   ecg_rbb = "ECG: Right Bundle Branch Block",
#'   grp_vbav = "Bicuspid AV",
#'   outcome = "Postop PPI"
#' )
#'
#' @param built a dataset with sas labels
#'
#' @return a hash function
#'
#' @examples
# # Build the map.
# avsd_label_map <- label_map(avsd_raw)
# dta$label <- avsd_label_map$label[match(dta$name, avsd_label_map$key)]
#'
#'
#' @export
### New label function
label_map = function(built) {
  return(data.frame(
    key = names(built),
    label = built |>
      labelled::var_label(unlist = T, null_action = "fill")
  ))
}
