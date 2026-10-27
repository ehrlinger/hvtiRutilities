#' Declare the packages a study needs
#'
#' @description
#' Records package names in the study's \code{DESCRIPTION}, the file renv reads
#' to build the study's \code{renv.lock} in explicit mode. Declaring rather than
#' letting renv scan the code means a stale template copy can never put a
#' package into the lockfile.
#'
#' Names are only ever added, and an entry already declared stays as written,
#' version constraint included. Every other field of the file is kept. The file
#' is rewritten only when the set changes, and a \code{DESCRIPTION} that is not a study project's (no
#' \code{Type: Project}) is never edited.
#'
#' @param packages Character. Package names to declare.
#' @param root Character(1). The study root. Defaults to the study that contains the working
#'   directory, found by its \code{_study.yml}; outside a study the function
#'   stops and writes nothing.
#' @return The sorted declared package names, invisibly.
#' @export
#' @examples
#' root <- file.path(tempdir(), "declare-example")
#' dir.create(root, showWarnings = FALSE)
#' study_declare("arrow", root)
study_declare <- function(packages = character(0), root = NULL) {
  root <- if (is.null(root)) study_root() else normalizePath(root, mustWork = TRUE)
  path <- file.path(root, "DESCRIPTION")
  record <- NULL
  entries <- character(0)
  if (file.exists(path)) {
    record <- read.dcf(path)
    if (!"Type" %in% colnames(record) || !identical(unname(record[1L, "Type"]), "Project")) {
      stop("study_declare(): ", path, " is not a study project DESCRIPTION (no Type: Project); ",
           "refusing to edit it", call. = FALSE)
    }
    # Re-read verbatim so every field is written back as it was found.
    record <- read.dcf(path, keep.white = colnames(record))
    if ("Depends" %in% colnames(record)) {
      entries <- trimws(strsplit(record[1L, "Depends"], ",", fixed = TRUE)[[1L]])
      entries <- entries[nzchar(entries)]
    }
  }
  have <- sub("\\s*\\(.*$", "", entries)
  new <- setdiff(unique(packages), have)
  all <- sort(c(have, new))
  if (!is.null(record) && !length(new)) return(invisible(all))
  entries <- c(entries, new)
  entries <- entries[order(c(have, new))]
  depends <- paste(entries, collapse = ", ")
  if (is.null(record)) {
    record <- matrix(c("Project", basename(root), depends), nrow = 1L,
                     dimnames = list(NULL, c("Type", "Title", "Depends")))
  } else if ("Depends" %in% colnames(record)) {
    record[1L, "Depends"] <- depends
  } else {
    record <- cbind(record, Depends = depends)
  }
  write.dcf(record, path, width = 80L, keep.white = colnames(record))
  invisible(all)
}
