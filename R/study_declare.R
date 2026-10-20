#' Declare the packages a study needs
#'
#' @description
#' Records package names in the study's \code{DESCRIPTION}, the file renv reads
#' to build the study's \code{renv.lock} in explicit mode. Declaring rather than
#' letting renv scan the code means a stale template copy can never put a
#' package into the lockfile.
#'
#' Names are only ever added. The file is rewritten only when the set changes,
#' and a \code{DESCRIPTION} that is not a study project's (no
#' \code{Type: Project}) is never edited.
#'
#' @param packages Character. Package names to declare.
#' @param root Character(1). The study root; by default the study enclosing the
#'   working directory, as \code{\link{study_root}} finds it.
#' @return The sorted declared package names, invisibly.
#' @export
#' @examples
#' root <- file.path(tempdir(), "declare-example")
#' dir.create(root, showWarnings = FALSE)
#' study_declare("arrow", root)
study_declare <- function(packages = character(0), root = NULL) {
  root <- if (is.null(root)) study_root() else normalizePath(root, mustWork = TRUE)
  path <- file.path(root, "DESCRIPTION")
  have <- character(0)
  if (file.exists(path)) {
    dcf <- read.dcf(path)
    if (!"Type" %in% colnames(dcf) || !identical(unname(dcf[1L, "Type"]), "Project")) {
      stop("study_declare(): ", path, " is not a study project DESCRIPTION (no Type: Project); ",
           "refusing to edit it", call. = FALSE)
    }
    if ("Depends" %in% colnames(dcf)) {
      have <- trimws(strsplit(dcf[1L, "Depends"], ",", fixed = TRUE)[[1L]])
      have <- sub("\\s*\\(.*$", "", have[nzchar(have)])
    }
  }
  all <- sort(unique(c(have, packages)))
  if (file.exists(path) && setequal(all, have)) return(invisible(all))
  fields <- matrix(c("Project", basename(root), paste(all, collapse = ", ")), nrow = 1L,
                   dimnames = list(NULL, c("Type", "Title", "Depends")))
  write.dcf(fields, path, width = 80L)
  invisible(all)
}
