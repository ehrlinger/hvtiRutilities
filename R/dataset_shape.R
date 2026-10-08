# Dataset shape: what kind of dataset a contract names, which columns make its
# rows unique, and, for a combined dataset, which registered datasets it was
# built from. Design: hvtiR dev/specs/2026-10-07-ancillary-datasets-design.md.

.study_kinds <- c("built", "subset", "ancillary", "combined")

.study_validate_shape <- function(contract, found, name, known, default) {
  bad <- function(what) {
    stop("study_config(): ", found, " ", what, " for dataset '", name, "'.", call. = FALSE)
  }
  kind <- contract$kind
  key <- contract$key
  parents <- contract$parents
  if (!is.null(kind)) {
    if (!(is.character(kind) && length(kind) == 1L && kind %in% .study_kinds)) {
      bad(paste0("has an invalid kind; expected one of ", toString(.study_kinds)))
    }
    if (default && !identical(kind, "built")) bad(paste0("has kind '", kind, "'; the study dataset is kind built"))
    if (!default && identical(kind, "built")) bad("has kind built, which only the study dataset may have")
  }
  if (!is.null(key) &&
        !(is.character(key) && length(key) >= 1L && !anyNA(key) && all(nzchar(key)) && !anyDuplicated(key))) {
    bad("has an invalid key; expected one or more distinct column names")
  }
  if (identical(kind, "combined")) {
    valid <- is.character(parents) && length(parents) >= 1L && !anyNA(parents) && !anyDuplicated(parents) &&
      all(parents %in% known) && !name %in% parents
    if (!valid) bad("needs parents naming other registered datasets")
  } else if (!is.null(parents)) {
    bad("has parents but is not kind combined")
  }
  invisible(TRUE)
}

.study_validate_shapes <- function(raw, found) {
  known <- c(if (!is.null(raw$built)) "study", names(raw$additional_datasets))
  .study_validate_shape(raw[c("kind", "key", "parents")], found, "study", known, default = TRUE)
  for (name in names(raw$additional_datasets)) {
    .study_validate_shape(raw$additional_datasets[[name]], found, name, known, default = FALSE)
  }
  raw
}
