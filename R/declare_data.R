#' Name a study's working dataset without registering it
#'
#' Writes the study dataset's contract, \code{built:} and \code{key:}, to
#' \code{_study.yml}, and an empty \code{manifest.yaml} when the study has none.
#' It registers no version. The dataset is then known but has no registered
#' version, so every read of it is a working read: allowed in the console and
#' in a draft render, refused in a final one. Register it with
#' \code{\link{update_manifest}()} when it is ready.
#'
#' A new study's first build needs this before any job can read it, because
#' \code{\link{read_built}()} finds the file through the contract. The empty
#' manifest is there because the templates call \code{\link{verify_manifest}()}
#' before reading data, and that stops on a missing file. An existing manifest
#' is left untouched. The \code{bd} template calls this on its first render
#' with \code{REGISTER = FALSE}.
#'
#' @param root The study root.
#' @param built The working file's name in the datasets folder, with its extension.
#' @param key Columns that make a row unique, or \code{NULL} to leave
#'   \code{key:} unset.
#' @return \code{TRUE}, invisibly, when the contract was written, or a
#'   \code{key} was added to a declaration that had none;
#'   \code{FALSE}, invisibly, when \code{built} was already declared.
#'   Stops when the study already declares a different file or a different key.
#' @examples
#' root <- file.path(tempdir(), "declare-example")
#' suppressMessages(study_setup(root, "Example", 1L, renv = FALSE))
#' saveRDS(data.frame(ccfid = 1:3), file.path(study_dir("datasets", root), "study_cohort.rds"))
#' declare_data(root, built = "study_cohort.rds", key = "ccfid")
#' unlink(root, recursive = TRUE)
#' @export
declare_data <- function(root = getwd(), built, key = NULL) {
  built <- .study_scalar(built, "built", TRUE, caller = "declare_data")
  if (!identical(basename(built), built) || !nzchar(tools::file_ext(built))) {
    stop("declare_data(): built must be one filename with its extension", call. = FALSE)
  }
  if (!is.null(key) && (!is.character(key) || !length(key) || anyNA(key) || !all(nzchar(key)))) {
    stop("declare_data(): key must be NULL or column names", call. = FALSE)
  }
  cfg <- study_config(root, require_data = FALSE)
  raw <- .read_study_yml(cfg$file, "declare_data")
  manifest_path <- file.path(cfg$root, "manifest.yaml")
  if (!is.null(raw$built)) {
    if (identical(raw$built, built)) {
      if (!is.null(key) && is.null(raw$key)) {
        raw$key <- key
        raw <- .study_validate_shapes(raw, cfg$file, caller = "declare_data")
        .study_write_atomic(raw, cfg$file)
        if (!file.exists(manifest_path)) .write_manifest(list(datasets = list()), manifest_path)
        return(invisible(TRUE))
      }
      if (!is.null(key) && !identical(as.character(raw$key), key)) {
        stop("declare_data(): _study.yml already declares ", built, " with key ",
             paste(raw$key, collapse = ", "),
             ". Change the key deliberately in _study.yml.", call. = FALSE)
      }
      # A study declared before declare_data() wrote a manifest still gets one.
      if (!file.exists(manifest_path)) .write_manifest(list(datasets = list()), manifest_path)
      return(invisible(FALSE))
    }
    stop("declare_data(): _study.yml already declares ", raw$built, ", not ", built,
         ". A study has one study dataset; change it deliberately in _study.yml.", call. = FALSE)
  }
  path <- file.path(study_dir("datasets", cfg$root), built)
  if (!file.exists(path)) stop("declare_data(): dataset is missing: ", path, call. = FALSE)
  raw$built <- built
  if (!is.null(key)) raw$key <- key
  raw <- .study_validate_shapes(raw, cfg$file, caller = "declare_data")
  .study_write_atomic(raw, cfg$file)
  if (!file.exists(manifest_path)) .write_manifest(list(datasets = list()), manifest_path)
  invisible(TRUE)
}
