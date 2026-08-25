#' Column-level schema of a dataset
#'
#' @description
#' One row per column: creation position, name, R class, SAS two-valued type,
#' \code{format.sas} and label. This is the durable description of a source
#' dataset — what a schema sidecar records, and what a later read is compared
#' against.
#'
#' @details
#' \code{label} and \code{format} are read from the column attributes directly
#' and are \code{NA} when the source carries none. This is the difference from
#' \code{\link{proc_contents}}, which fills an absent label with the variable's
#' own name: right for a printed listing, wrong for a record that outlives the
#' source dataset.
#'
#' Nothing here describes the data, only its shape. Two reads of an unchanged
#' file produce an identical schema, which is what makes the sidecar's hash
#' meaningful.
#'
#' @param data A data frame, tibble, or similar tabular object.
#'
#' @return A data frame with columns \code{num} (creation position, integer),
#'   \code{variable}, \code{class} (first R class), \code{type}
#'   (\code{"Num"}/\code{"Char"}), \code{format} (SAS format or \code{NA}) and
#'   \code{label} (or \code{NA}).
#'
#' @seealso \code{\link{proc_contents}} for a printable listing that also
#'   summarises completeness.
#'
#' @export
#'
#' @examples
#' d <- data.frame(x = 1:3, y = letters[1:3])
#' attr(d$x, "label") <- "An identifier"
#' dataset_schema(d)
dataset_schema <- function(data) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }

  cols <- c("num", "variable", "class", "type", "format", "label")

  if (ncol(data) == 0L) {
    empty <- data.frame(num = integer(0), variable = character(0),
                        class = character(0), type = character(0),
                        format = character(0), label = character(0),
                        stringsAsFactors = FALSE)
    return(empty[, cols, drop = FALSE])
  }

  # Attributes are read directly rather than through labelled::var_label(),
  # whose null_action = "fill" would substitute the variable name.
  attr_chr <- function(x, which) {
    v <- attr(x, which, exact = TRUE)
    if (is.null(v) || length(v) == 0L) NA_character_ else as.character(v)[1L]
  }

  data.frame(
    num      = seq_len(ncol(data)),
    variable = names(data),
    class    = vapply(data, function(x) class(x)[1L], character(1)),
    type     = vapply(data,
                      function(x) if (is.character(x) || is.factor(x)) "Char" else "Num",
                      character(1)),
    format   = vapply(data, attr_chr, character(1), which = "format.sas"),
    label    = vapply(data, attr_chr, character(1), which = "label"),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}
