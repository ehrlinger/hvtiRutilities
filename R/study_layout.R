# A study layout maps stable taxonomy names to the directory spelling used by
# one study. New studies use numbered directories; adopted studies retain the
# bare names that existing code and SAS programs already reference.

.study_folders <- function() {
  c(
    datasets = "00_datasets",
    descriptive = "10_descriptive",
    distributions = "20_distributions",
    analyses = "30_analyses",
    graphs = "40_graphs",
    documents = "50_documents",
    estimates = "90_estimates"
  )
}

.study_layout <- function(root) {
  folders <- .study_folders()
  numbered <- any(dir.exists(file.path(root, unname(folders))))
  legacy <- any(dir.exists(file.path(root, names(folders))))

  if (numbered && legacy) {
    stop("study directory layout is mixed", call. = FALSE)
  }

  if (numbered) "numbered" else "legacy"
}

#' Resolve a directory in the study layout
#'
#' @description
#' Maps a logical study directory such as code{"datasets"} to the numbered
#' spelling used by new studies or the bare spelling retained by legacy
#' studies. A root containing both layouts is an error.
#'
#' @param folder Character. One logical study directory name.
#' @param root Character. Study root. Defaults to code{study_root()}.
#'
#' @return Character(1). The resolved directory path. Its existence is not
#'   required.
#'
#' @seealso code{\link{study_root}}, code{\link{sas_path}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "numbered-study-layout")
#' dir.create(file.path(root, "00_datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' study_dir("datasets", root)
#' unlink(root, recursive = TRUE)
study_dir <- function(folder, root = study_root()) {
  folders <- .study_folders()

  if (length(folder) != 1L || is.na(folder) ||
      !folder %in% names(folders)) {
    stop("unknown study folder: ", paste(folder, collapse = ", "),
         call. = FALSE)
  }

  leaf <- if (.study_layout(root) == "numbered") {
    folders[[folder]]
  } else {
    folder
  }

  file.path(root, leaf)
}
