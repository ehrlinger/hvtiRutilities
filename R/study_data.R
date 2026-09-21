# The data contract. The built dataset lives on a mutable network share outside
# version control: the SAS run that produced the results we validate against
# rewrote it in place, and nothing stops the next run rewriting it mid-analysis.
# Every stage records the manifest so a run cannot straddle two dataset states.
#
# The dataset name is not a constant here. It comes from _study.yml, because
# this package is shared across studies and a literal filename in R/ is exactly
# the early binding this design exists to remove.

.study_dataset <- function(cfg, dataset = "study") {
  if (!is.character(dataset) || length(dataset) != 1L || is.na(dataset) ||
        !nzchar(dataset)) {
    stop("dataset must be one non-empty character name", call. = FALSE)
  }

  if (identical(dataset, "study")) {
    return(list(
      dataset = dataset,
      built = cfg$built,
      population = cfg$population,
      release = cfg$release
    ))
  }

  out <- cfg$additional_datasets[[dataset]]
  if (is.null(out)) {
    choices <- c("study", names(cfg$additional_datasets))
    stop("unknown dataset '", dataset, "'; registered: ",
         paste(choices, collapse = ", "), call. = FALSE)
  }
  list(
    dataset = dataset,
    built = out$built,
    population = out$population,
    release = out$release
  )
}

#' Path to the study's built dataset
#'
#' @description
#' Resolves the registered filename beneath the study's logical
#' \code{datasets} directory. The path is not checked for existence.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}.
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
#'   list(study = "Example", built = "example.sas7bdat"),
#'   file.path(root, "_study.yml")
#' )
#' built_path(study_config(root))
#' unlink(root, recursive = TRUE)
built_path <- function(cfg = study_config(), dataset = "study") {
  contract <- .study_dataset(cfg, dataset)
  if (is.null(contract$built)) {
    stop("built_path(): dataset '", dataset, "' has no registered file",
         call. = FALSE)
  }
  file.path(study_dir("datasets", cfg$root), contract$built)
}

#' Record the state of the built dataset
#'
#' @description
#' Returns a one-row data frame identifying the built dataset by name, size,
#' modification time and SHA-256. This is the record that lets a later reader
#' tell whether two results were produced from the same data.
#'
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}.
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
#'   list(study = "Example", built = "example.csv"),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' built_manifest(study_config(root))
#' unlink(root, recursive = TRUE)
built_manifest <- function(cfg = study_config(), dataset = "study") {
  contract <- .study_dataset(cfg, dataset)
  p <- built_path(cfg, dataset)
  if (!file.exists(p)) {
    stop("built_manifest(): missing ", p, call. = FALSE)
  }
  info <- file.info(p)
  data.frame(
    file       = contract$built,
    size_bytes = as.numeric(info$size),
    mtime      = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    sha256     = digest::digest(p, algo = "sha256", file = TRUE),
    stringsAsFactors = FALSE
  )
}

# Errors if lowercasing `names(d)` would collide, naming the colliding
# original names. Called from inside the reader closure passed to
# .cache_read(), so a collision is caught before any cache artifact --
# .parquet, .schema.csv, or the manifest entry -- has been written for a
# dataset that can never be read. SAS names are case-insensitive and cannot
# collide this way; .csv, .xlsx and .rds sources can.
#
# Defined ABOVE read_built()'s roxygen block, not between it and the function.
# Roxygen attaches a block to the NEXT statement, so a definition placed in
# between silently steals the documentation -- read_built.Rd disappears, this
# internal gets documented and exported in its place, and read_built() stops
# being exported. devtools::test() does not catch it, because load_all()
# exposes internals regardless of NAMESPACE; only an installed package breaks.
.assert_no_lowercase_collision <- function(d, path) {
  lower <- tolower(names(d))
  if (anyDuplicated(lower)) {
    clashes <- unique(lower[duplicated(lower)])
    detail <- vapply(clashes, function(x) {
      paste0(x, " <- ", paste(names(d)[lower == x], collapse = ", "))
    }, character(1))
    stop("read_built(): lowercasing column names produces duplicates in ",
         basename(path), ": ", paste(detail, collapse = "; "),
         ". Rename the colliding columns at the source.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Read the study's built dataset
#'
#' @description
#' Reads the dataset named in \code{_study.yml} and normalises its types so
#' that both available read paths deliver the same frame.
#'
#' For a release-aware contract, the pinned release is verified before cache
#' access. A later valid release emits a message of class
#' \code{hvtiRutilities_update_available}; an unavailable catalog or invalid
#' candidate emits \code{hvtiRutilities_update_status_unknown} and the pinned
#' data are still read. A changed pinned release errors with class
#' \code{hvtiRutilities_release_integrity}. A withdrawn pin errors with class
#' \code{hvtiRutilities_withdrawn_release} unless \code{allow_withdrawn} is
#' \code{TRUE}.
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
#' @param refresh Logical. If \code{TRUE}, force a re-read from the source and
#'   a reconversion regardless of the manifest's role or cached stamp.
#'   "The source changed" is not always something a timestamp can express --
#'   a rebuild that preserves \code{mtime}, a restored backup, a correction
#'   applied out of band. Errors if the manifest entry has
#'   \code{role: "primary"}: that role means the source has been retired and
#'   the parquet is authoritative, so there is nothing to refresh from.
#' @param dataset Character(1). Logical dataset name. Defaults to
#'   \code{"study"}.
#' @param allow_withdrawn Logical. If \code{TRUE}, allow a deliberately pinned
#'   withdrawn release to be read for revision work. The default is
#'   \code{FALSE}.
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
#'   list(study = "Example", built = "example.csv"),
#'   file.path(root, "_study.yml")
#' )
#' write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' names(read_built(study_config(root)))
#' unlink(root, recursive = TRUE)
read_built <- function(cfg = study_config(), refresh = FALSE,
                       dataset = "study", allow_withdrawn = FALSE) {
  if (!is.logical(allow_withdrawn) || length(allow_withdrawn) != 1L ||
        is.na(allow_withdrawn)) {
    stop("allow_withdrawn must be TRUE or FALSE", call. = FALSE)
  }
  contract <- .study_dataset(cfg, dataset)
  if (!is.null(contract$release)) {
    .enforce_release_read(cfg, dataset, allow_withdrawn)
  }
  p <- built_path(cfg, dataset)
  manifest_path <- file.path(cfg$root, "manifest.yaml")

  if (!file.exists(p)) {
    # role: "primary" means the source was retired on purpose -- promotion
    # exists precisely so this dataset can still be served with no source on
    # disk. A promoted entry whose parquet is ALSO missing is still an
    # error, but the parquet -- not the source retired on purpose -- is the
    # copy that's actually missing.
    entry <- .manifest_entry(manifest_path, p)
    if (identical(entry$role, "primary")) {
      parquet <- .derived_paths(p)$parquet
      if (!file.exists(parquet)) {
        stop("read_built(): missing ", parquet, call. = FALSE)
      }
    } else {
      stop("read_built(): missing ", p, call. = FALSE)
    }
  }

  # Carries SAS variable labels through; listings print labels, not names.
  # The collision check runs INSIDE the reader closure, before .cache_read()
  # writes anything: a check placed after .cache_read() returns would already
  # be too late on a cache miss, which writes the .parquet, .schema.csv and
  # manifest entry for a dataset it is about to discover can never be read.
  d <- as.data.frame(
    .cache_read(p,
                function(f) {
                  raw <- read_clinical_data(f, convert_types = FALSE)
                  .assert_no_lowercase_collision(raw, f)
                  raw
                },
                manifest_path = manifest_path,
                refresh = refresh)
  )

  # Lowercasing is unconditional, so a source carrying both FOO and foo would
  # yield two columns named foo and every downstream d$foo would silently take
  # the first. The check above already ruled this out for `d`; this just
  # applies it.
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
