#' Review a rebuilt study dataset before registering it
#'
#' @description
#' Compares the working dataset, as it stands in the study's datasets folder,
#' with its registered version, the dated parquet jobs read. It reads both and
#' writes nothing. Run it after a rebuild and before
#' \code{\link{update_manifest}()}, which registers the rebuilt file as the next
#' version. It describes how the data changed; it does not certify that the
#' new file is analytically or clinically correct.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}. \code{"built"} is a second name for \code{"study"}.
#'
#' @return An object of class \code{"built_review"} with
#'   \describe{
#'     \item{dataset}{The logical dataset name.}
#'     \item{registered}{The current version record from \code{manifest.yaml}.}
#'     \item{working}{A list with the source file's \code{sha256}, \code{n_rows} and \code{n_cols}.}
#'     \item{changed}{\code{TRUE} when the source differs from the registered version.}
#'     \item{comparison}{A \code{\link{compare_datasets}} result, or \code{NULL} when unchanged.}
#'   }
#'
#' @seealso \code{\link{update_manifest}}, \code{\link{read_built}}
#'
#' @export
#'
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   root <- file.path(tempdir(), "review-built-example")
#'   suppressMessages(study_setup(root, "Example", 1L))
#'   path <- file.path(study_dir("datasets", root), "example.csv")
#'   write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3), path, row.names = FALSE)
#'   suppressMessages(register_data(root, "example.csv"))
#'   write.csv(data.frame(DEAD = c(1, 0, 0, 1), IV_DEAD = 1:4), path, row.names = FALSE)
#'   review_built(study_config(root))
#'   unlink(root, recursive = TRUE)
#' }
review_built <- function(cfg = study_config(), dataset = "study") {
  dataset <- .canonical_dataset(dataset)
  .study_dataset(cfg, dataset)
  p <- built_path(cfg, dataset)
  entry <- .manifest_entry(file.path(cfg$root, "manifest.yaml"), p)
  if (!.is_versioned(entry)) {
    stop("review_built(): nothing is registered to compare against for ", basename(p),
         ". Register it with register_data(), or run update_manifest() to convert a legacy entry.", call. = FALSE)
  }
  # .source_changed() reads a missing source as unchanged; a review must not.
  if (!file.exists(p)) {
    stop("review_built(): ", basename(p), " is not on disk, so there is nothing to review. Jobs keep reading ",
         entry$parquet, ".", call. = FALSE)
  }
  changed <- .source_changed(p, entry)
  raw <- read_clinical_data(p, convert_types = FALSE)
  .assert_no_lowercase_collision(raw, p, "review_built")
  working <- .normalise_built(as.data.frame(raw))
  comparison <- if (changed) {
    registered <- suppressMessages(.read_registered_version(p, entry),
                                   classes = "hvtiRutilities_source_changed")
    compare_datasets(.normalise_built(registered), working)
  }
  structure(
    list(dataset = dataset, registered = .history_record(entry),
         working = list(sha256 = digest::digest(p, algo = "sha256", file = TRUE),
                        n_rows = nrow(working), n_cols = ncol(working)),
         changed = changed, comparison = comparison),
    class = "built_review"
  )
}

#' @export
print.built_review <- function(x, ...) {
  r <- x$registered
  if (!x$changed) {
    cat(x$dataset, ": the working file is unchanged since ", r$extract_date, " (", r$parquet, ").\n", sep = "")
    return(invisible(x))
  }
  cat(x$dataset, ": the working file differs from ", r$parquet, " (registered ", r$extract_date, ").\n", sep = "")
  print(x$comparison)
  cat("Register it as the next version with hvtiRutilities::update_manifest().\n")
  invisible(x)
}
