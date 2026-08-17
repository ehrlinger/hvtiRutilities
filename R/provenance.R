# The provenance sidecar.
#
# renv.lock alone does not close the provenance gap. It is project-scoped and
# time-varying: a study runs eighty jobs over three years and is snapshotted
# repeatedly, so the lock at the end does not say what produced a particular
# output in month two. The lock is a restore mechanism, not a record. The
# result is job-scoped and frozen when filed, so the record lives beside it.
#
# JSON, not RDS: the record must be readable in 2035 by someone who may not
# have R, and two runs must be diffable with diff. RDS fails both.

# Required top-level keys and their expected JSON types. The structural test
# reads this; it is also what a formal JSON Schema would be generated from.
.provenance_required <- function() {
  c(job       = "character",
    rendered  = "character",
    study     = "list",
    r         = "list",
    packages  = "list",
    renv_lock = "list",
    data      = "list",
    cohort    = "list")
}

# Every loaded namespace, sorted, with the source recorded where the
# installation left a trace of one. Not a curated list: a curated list is what
# goes wrong when a dependency starts mattering and nobody notices.
.loaded_packages <- function() {
  ns <- sort(loadedNamespaces())
  lapply(ns, function(p) {
    desc <- tryCatch(utils::packageDescription(p), error = function(e) NULL)
    src <- if (is.null(desc)) {
      NA_character_
    } else if (!is.null(desc$RemoteType)) {
      desc$RemoteType
    } else if (!is.null(desc$Repository)) {
      desc$Repository
    } else if (identical(desc$Priority, "base")) {
      "base"
    } else {
      NA_character_
    }
    list(package = p,
         version = as.character(utils::packageVersion(p)),
         source  = src)
  })
}

#' Name the provenance sidecar for an output
#'
#' @description
#' Returns the path of the sidecar belonging to a rendered output: the output
#' path with its extension replaced by \code{.provenance.json}.
#'
#' @param path Character(1). Path to a rendered output.
#'
#' @return Character(1). The sidecar path.
#'
#' @seealso \code{\link{record_provenance}}
#'
#' @export
#'
#' @examples
#' provenance_path("_output/01.hz.dead_JR.html")
provenance_path <- function(path) {
  file.path(dirname(path),
            paste0(tools::file_path_sans_ext(basename(path)),
                   ".provenance.json"))
}

#' Write the provenance record for a rendered output
#'
#' @description
#' Writes \code{<output>.provenance.json} beside a rendered result, recording
#' what produced it: the study manifest and its checksum, the R version and
#' platform, every loaded package and its version, the \code{renv.lock}
#' checksum if there is one, the built dataset's checksum, and the cohort.
#'
#' This closes a loop that is otherwise impossible. Revisiting a study becomes:
#' read the sidecar off the filed output, \code{renv::restore()} to that lock,
#' re-render, confirm the filed numbers reproduce, and only then wind forward.
#'
#' Failure to write the sidecar is an error rather than a warning. Every other
#' failure in this design is recoverable; a silently unrecorded result is not.
#'
#' @param path Character(1). Path to the rendered output the record belongs to.
#'   The file itself need not exist; only its name and directory are used.
#' @param extra List. Additional named fields merged into the record - for
#'   example a \code{template} block naming the template and its version.
#'   Required keys cannot be displaced.
#' @param cfg List. A study manifest from \code{\link{study_config}}.
#'
#' @return Invisibly, the record that was written, as a list.
#'
#' @seealso \code{\link{provenance_path}}, \code{\link{study_config}},
#'   \code{\link{built_manifest}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "provenance-example")
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
#' out <- file.path(root, "example.html")
#' writeLines("<html></html>", out)
#' rec <- record_provenance(out, cfg = study_config(root))
#' rec$job
#' unlink(root, recursive = TRUE)
record_provenance <- function(path, extra = list(), cfg = study_config()) {
  sidecar <- provenance_path(path)

  lock      <- file.path(cfg$root, "renv.lock")
  lock_rec  <- if (file.exists(lock)) {
    list(path   = "renv.lock",
         sha256 = digest::digest(lock, algo = "sha256", file = TRUE))
  } else {
    NULL
  }

  bm <- built_manifest(cfg)

  record <- list(
    job      = tools::file_path_sans_ext(basename(path)),
    # Fixed-offset UTC, so two machines in different zones produce comparable
    # records and the string sorts chronologically.
    rendered = format(as.POSIXlt(Sys.time(), tz = "UTC"),
                      "%Y-%m-%dT%H:%M:%SZ"),
    study    = list(
      name   = cfg$study,
      file   = basename(cfg$file),
      sha256 = digest::digest(cfg$file, algo = "sha256", file = TRUE)
    ),
    r = list(
      version  = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    ),
    packages  = .loaded_packages(),
    renv_lock = lock_rec,
    data      = list(list(
      file   = bm$file,
      bytes  = bm$size_bytes,
      mtime  = bm$mtime,
      sha256 = bm$sha256
    )),
    cohort = list(
      n          = cfg$cohort$n,
      n_events   = cfg$cohort$n_events,
      n_censored = cfg$cohort$n_censored
    )
  )

  # Extra fields are appended, never allowed to displace a required key.
  extra <- extra[setdiff(names(extra), names(.provenance_required()))]
  record <- c(record, extra)

  # A warning is treated as a failure, not passed through. write_json() warns
  # before it errors on an unwritable path, and any warning here means the
  # record may not have landed - which is precisely the state this function
  # exists to make impossible. Failing loud beats a warning nobody reads.
  written <- tryCatch({
    jsonlite::write_json(record, sidecar, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", digits = NA)
    TRUE
  }, error   = function(e) conditionMessage(e),
     warning = function(w) conditionMessage(w))

  if (!isTRUE(written)) {
    stop("record_provenance(): could not write the provenance sidecar ",
         sidecar, ": ", written,
         "\nAn unrecorded result is the failure this check exists to prevent.",
         call. = FALSE)
  }

  invisible(record)
}
