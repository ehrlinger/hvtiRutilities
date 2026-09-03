## =============================================================================
#' Declare value labels for coded variables from a YAML file
#'
#' @description
#' Reads a study's \code{value_labels.yml} and attaches the declared
#' code-to-text mappings to the matching columns as value labels, via
#' \code{labelled::val_labels()}. It declares; it does not convert. Pass the
#' result to \code{\link{r_data_types}} with \code{use_value_labels = TRUE} to
#' turn the declarations into factors with text levels.
#'
#' A \code{.sas7bdat} file stores a format's \emph{name} (\code{YESNOF.}); the
#' code-to-text mapping lives in a \code{.sas7bcat} catalogue. The study
#' corpus has no catalogues, so this file is not a supplement to one - it is
#' the only place the mapping can come from. Because the declaration is
#' written into the same slot a catalogue would have filled, everything
#' downstream reads it without a second code path.
#'
#' The function is safe to call unconditionally: a study with no
#' \code{value_labels.yml} gets its data back unchanged.
#'
#' @details
#' The file maps each variable to its codes, and each code to the text that
#' code means:
#'
#' \preformatted{
#' disp:
#'   1: Home
#'   2: Rehab
#'   3: SNF
#' approach:
#'   1: Ascending aorta only
#'   2: Ascending aorta plus arch
#' }
#'
#' This is the home for enumerated level definitions, and it is deliberately
#' \strong{not} the display label. Level definitions crammed into a variable
#' label are what forced them to be reconstructed by hand in every table, and
#' a label carrying eight mutually exclusive options cannot survive
#' \code{label_max} (see \code{\link{label_map}}). Declaring them here keeps
#' the two jobs apart: the converter reads this file, and a table renderer
#' reads the label.
#'
#' Two rules worth knowing before relying on the result:
#' \itemize{
#'   \item \strong{Value labels already on the column win.} A column that
#'     arrives labelled - from a catalogue, or from an earlier call - is left
#'     alone and the variable is named in a warning, so a declaration can
#'     never silently overwrite a mapping read from the source.
#'   \item \strong{A variable named in the file but absent from the data is
#'     reported.} A typo that quietly declares nothing is the failure this
#'     file is least able to notice.
#' }
#'
#' The \code{ordered} key is reserved for the ordinal declaration and is
#' \strong{refused} rather than partly honoured. Ordinality is blocked on a
#' statistical decision; reserving the key now keeps one home for both
#' declarations without pre-empting it.
#'
#' @param data A data frame whose coded columns should be declared.
#' @param value_labels_file Path to a YAML file of value-label declarations.
#'   Defaults to \code{"value_labels.yml"} in the current working directory.
#'   A path that does not exist is not an error.
#'
#' @return \code{data}, with value labels attached to the declared columns
#'   via \code{labelled::val_labels()}. Columns not named in the file, and
#'   columns that already carry value labels, are returned unchanged.
#'
#' @seealso \code{\link{r_data_types}} for converting declarations to
#'   factors, \code{\link{apply_label_overrides}} for the same pattern one
#'   level up - declaring \emph{variable} labels rather than value labels,
#'   \code{\link{read_clinical_data}} for the \code{catalog_file} argument
#'   that would supply these mappings if a catalogue existed.
#'
#' @export
#'
#' @examples
#' tmp <- tempfile(fileext = ".yml")
#' writeLines(c("disp:", "  1: Home", "  2: Rehab", "  3: SNF"), tmp)
#'
#' dta <- data.frame(disp = c(1, 2, 1, 3))
#' dta <- apply_value_labels(dta, tmp)
#' labelled::val_labels(dta$disp)
#'
#' # Declare, then convert
#' r_data_types(dta, use_value_labels = TRUE)$disp
#'
#' unlink(tmp)
apply_value_labels <- function(data,
                               value_labels_file = "value_labels.yml") {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  if (!is.character(value_labels_file) || length(value_labels_file) != 1L) {
    stop("'value_labels_file' must be a single file path.", call. = FALSE)
  }
  if (!file.exists(value_labels_file)) {
    return(data)
  }

  decl <- yaml::read_yaml(value_labels_file)
  if (!is.list(decl) || length(decl) == 0L) {
    return(data)
  }

  .reject_reserved_keys(decl)

  unknown <- setdiff(names(decl), names(data))
  if (length(unknown) > 0) {
    warning(
      sprintf(
        "%s declares %d variable(s) not present in the data: %s.",
        basename(value_labels_file), length(unknown),
        paste(unknown, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  declared <- intersect(names(decl), names(data))
  skipped <- character(0)

  for (v in declared) {
    if (length(labelled::val_labels(data[[v]])) > 0) {
      skipped <- c(skipped, v)
      next
    }
    labelled::val_labels(data[[v]]) <-
      .value_label_vector(decl[[v]], data[[v]], v)
  }

  if (length(skipped) > 0) {
    warning(
      sprintf(
        paste0("%d variable(s) already carry value labels and were left ",
               "as read: %s. Value labels on the column take priority ",
               "over %s."),
        length(skipped), paste(skipped, collapse = ", "),
        basename(value_labels_file)
      ),
      call. = FALSE
    )
  }

  data
}

## Reserve the ordinal declaration's key without implementing it. Honouring
## half of it would be worse than refusing: an `ordered: true` that silently
## does nothing reads in the file as though ordinality had been declared.
.reject_reserved_keys <- function(decl) {
  has_ordered <- vapply(
    decl,
    function(x) is.list(x) && "ordered" %in% names(x),
    logical(1)
  )
  if (any(has_ordered)) {
    stop(
      sprintf(
        paste0("'ordered' is reserved for the ordinal declaration and is ",
               "not implemented yet (%s). Remove it; ordinality is blocked ",
               "on a statistical decision."),
        paste(names(decl)[has_ordered], collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(NULL)
}

## Turn one variable's YAML entry into the vector val_labels() wants: the
## level text as names, the codes as values, typed to match the column.
.value_label_vector <- function(entry, column, var) {
  if (!is.list(entry) || length(entry) == 0L || is.null(names(entry))) {
    stop(
      sprintf(
        paste0("Value labels for '%s' must be a mapping of code to text, ",
               "e.g. '1: Home'."),
        var
      ),
      call. = FALSE
    )
  }

  codes <- names(entry)
  text <- vapply(entry, as.character, character(1), USE.NAMES = FALSE)

  if (is.character(column) || is.factor(column)) {
    return(stats::setNames(codes, text))
  }

  numeric_codes <- suppressWarnings(as.numeric(codes))
  if (anyNA(numeric_codes)) {
    stop(
      sprintf(
        paste0("Value labels for '%s' have non-numeric codes (%s) but the ",
               "column is numeric."),
        var, paste(codes[is.na(numeric_codes)], collapse = ", ")
      ),
      call. = FALSE
    )
  }

  stats::setNames(numeric_codes, text)
}
