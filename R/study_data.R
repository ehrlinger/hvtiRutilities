# The data contract. The built dataset lives on a mutable network share outside
# version control: the SAS run that produced the results we validate against
# rewrote it in place, and nothing stops the next run rewriting it mid-analysis.
# Every stage records the manifest so a run cannot straddle two dataset states.
#
# The dataset name is not a constant here. It comes from _study.yml, because
# this package is shared across studies and a literal filename in R/ is exactly
# the early binding this design exists to remove.

#' Path to the study's built dataset
#'
#' @description
#' Resolves \code{<study root>/datasets/<built>}, where \code{built} is the
#' filename declared in \code{_study.yml}. The path is not checked for
#' existence.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return Character(1). The path to the built dataset.
#'
#' @seealso \code{\link{built_manifest}}, \code{\link{read_built}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "built-path-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.sas7bdat",
#'        cohort = list(n = 10L, n_events = 4L, n_censored = 6L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' built_path(study_config(root))
#' unlink(root, recursive = TRUE)
built_path <- function(cfg = study_config()) {
  file.path(cfg$root, "datasets", cfg$built)
}

#' Record the state of the built dataset
#'
#' @description
#' Returns a one-row data frame identifying the built dataset by name, size,
#' modification time and SHA-256. This is the record that lets a later reader
#' tell whether two results were produced from the same data.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A one-row data frame with columns \code{file}, \code{size_bytes},
#'   \code{mtime} and \code{sha256}.
#'
#' @seealso \code{\link{built_path}}, \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "built-manifest-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.csv",
#'        cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' built_manifest(study_config(root))
#' unlink(root, recursive = TRUE)
built_manifest <- function(cfg = study_config()) {
  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("built_manifest(): missing ", p, call. = FALSE)
  }
  info <- file.info(p)
  data.frame(
    file       = cfg$built,
    size_bytes = as.numeric(info$size),
    mtime      = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    sha256     = digest::digest(p, algo = "sha256", file = TRUE),
    stringsAsFactors = FALSE
  )
}

#' Read the study's built dataset
#'
#' @description
#' Reads the dataset named in \code{_study.yml} and normalises its types so
#' that both available read paths deliver the same frame.
#'
#' The normalisation is not cosmetic. \code{\link{read_clinical_data}} converts
#' SAS 0/1 numerics to logical while \code{haven::read_sas()} leaves them
#' numeric, and downstream modelling code rejects a logical status vector
#' outright — so without this the same document would run under one read path
#' and fail under the other. Labelled vectors are likewise reduced to plain
#' vectors, keeping the SAS variable label as an attribute because listings
#' print labels rather than names.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return A data frame with lower-cased names, no logical columns and no
#'   \code{haven_labelled} columns.
#'
#' @seealso \code{\link{built_manifest}}, \code{\link{assert_cohort}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "read-built-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' yaml::write_yaml(
#'   list(study = "Example", built = "example.csv",
#'        cohort = list(n = 3L, n_events = 1L, n_censored = 2L,
#'                      event = "dead", time = "iv_dead")),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' names(read_built(study_config(root)))
#' unlink(root, recursive = TRUE)
read_built <- function(cfg = study_config()) {
  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("read_built(): missing ", p, call. = FALSE)
  }

  # Carries SAS variable labels through; listings print labels, not names.
  d <- as.data.frame(read_clinical_data(p, convert_types = FALSE))
  names(d) <- tolower(names(d))

  logi <- vapply(d, is.logical, logical(1))
  d[logi] <- lapply(d[logi], as.integer)

  lab <- vapply(d, function(x) inherits(x, "haven_labelled"), logical(1))
  d[lab] <- lapply(d[lab], function(x) {
    a   <- attributes(x)
    out <- as.vector(x)
    if (!is.null(a$label)) attr(out, "label") <- a$label
    out
  })

  d
}
