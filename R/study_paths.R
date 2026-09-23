# Runtime path resolution. The study resolves to different absolute paths on
# the server and on a Mac mount, so nothing here may contain a literal prefix.
#
# The root is the directory holding _study.yml. This replaces the earlier
# marker-directory walk (datasets/ distributions/ graphs/ analyses/), which
# located a study by its shape rather than by its declaration and so could not
# tell a study root from a copy of one.

#' Locate the study root
#'
#' @description
#' Returns the absolute path of the directory holding \code{_study.yml}, found
#' by walking up from \code{start}. Errors if there is none, naming the
#' directories walked.
#'
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return Character(1). The absolute path of the study root.
#'
#' @seealso \code{\link{study_config}}, \code{\link{sas_path}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-root-example")
#' dir.create(root, showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat"),
#'   file.path(root, "_study.yml")
#' )
#' study_root(root)
#' unlink(root, recursive = TRUE)
study_root <- function(start = getwd()) {
  study_config(start, require_data = FALSE)$root
}

#' Build a path under the study root
#'
#' @description
#' Joins its arguments onto the study root. A first component naming a logical
#' study directory is resolved through the study's numbered or legacy layout.
#' Other components are passed through unchanged. Use this instead of any
#' literal path: the same study is mounted at different absolute paths on the
#' analysis server and on a laptop.
#'
#' @param ... Character. Path components, passed to \code{file.path()}.
#' @param start Character. Directory to start the upward walk from. Defaults
#'   to \code{getwd()}.
#'
#' @return Character(1). The joined path. It is not checked for existence.
#'
#' @seealso \code{\link{study_root}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "sas-path-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat"),
#'   file.path(root, "_study.yml")
#' )
#' sas_path("datasets", start = root)
#' unlink(root, recursive = TRUE)
sas_path <- function(..., start = getwd()) {
  root <- study_root(start)
  parts <- list(...)
  if (length(parts) && is.character(parts[[1L]]) &&
        length(parts[[1L]]) == 1L && !is.na(parts[[1L]]) &&
        parts[[1L]] %in% names(.study_folders())) {
    parts[[1L]] <- basename(study_dir(parts[[1L]], root))
  }
  do.call(file.path, c(list(root), parts))
}
