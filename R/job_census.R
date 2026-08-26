# Attributing a file to a study, and saying how confidently.
#
# The study is the directory holding the taxonomy folder -- `distributions`,
# `analyses`, `graphs` and the rest. Files nest below those folders in the
# real corpus (preserve_root has ten hp.* files in graphs/Training/ and its R
# jobs two levels down in analyses/R_hazard/qmd/), so the walk finds the
# NEAREST taxonomy ancestor rather than assuming the file's own parent.
#
# Nothing is discarded. A file with no taxonomy folder anywhere above it gets
# status "unplaced" and keeps its row: a sweep that reports only what it kept
# makes a missing job indistinguishable from a job that does not exist, and
# that is exactly how shape-census.R under-reported twice.

.job_placement <- function(paths, root) {
  folders <- unique(hvti_taxonomy()$folder)

  # Strip the root prefix BY POSITION, not with a regex anchor. A root path is
  # arbitrary input -- a directory named "study (copy)" or "v1.2+" carries
  # regex metacharacters -- and an unescaped anchor matches the wrong thing
  # while still looking like it worked, because `.` and `-` match themselves.
  # normalizePath() on both sides so a symlinked root (/var -> /private/var on
  # macOS) does not make the prefix fail to line up.
  nroot <- normalizePath(root, mustWork = FALSE)
  npaths <- normalizePath(paths, mustWork = FALSE)
  rel <- substring(npaths, nchar(nroot) + 2L)

  parts <- strsplit(rel, "/", fixed = TRUE)

  out <- lapply(parts, function(p) {
    # Drop the basename: only directory components can be a taxonomy folder.
    dirs <- utils::head(p, -1L)
    hits <- which(dirs %in% folders)
    if (!length(hits)) {
      return(list(study = NA_character_, folder = NA_character_,
                  status = "unplaced", depth = NA_integer_))
    }
    i <- max(hits)                       # nearest to the file
    depth <- length(dirs) - i
    list(
      study  = if (i == 1L) "." else paste(dirs[seq_len(i - 1L)], collapse = "/"),
      folder = dirs[[i]],
      status = if (depth == 0L) "placed" else "nested",
      depth  = as.integer(depth)
    )
  })

  data.frame(
    study  = vapply(out, `[[`, character(1), "study"),
    folder = vapply(out, `[[`, character(1), "folder"),
    status = vapply(out, `[[`, character(1), "status"),
    depth  = vapply(out, `[[`, integer(1), "depth"),
    stringsAsFactors = FALSE
  )
}

#' Inventory the job files under one or more corpus roots
#'
#' @description
#' Walks each root and returns one row per file. This is a filename-only
#' sweep: no file is opened, nothing is parsed, and there is no
#' \code{TemporalHazard} dependency.
#'
#' @details
#' \strong{Nothing is filtered out.} Placement and classification are columns,
#' not reasons to drop a row, so a file this sweep cannot classify stays
#' findable. A sweep that reports only what it kept makes a missing job
#' indistinguishable from a job that does not exist.
#'
#' There is deliberately no extension allowlist. See
#' \code{vignette}-adjacent design note
#' \code{specs/2026-08-26-job-type-inventory-design.md}, section 4.4: a
#' plausible default tuned on the hazard prefixes would have dropped every
#' R-side job in the corpus.
#'
#' \strong{Run this server-side.} It stats every file beneath \code{roots},
#' which is metadata-latency-bound over an SMB mount -- a 40-file scan has
#' timed out at two minutes over the share.
#'
#' @param roots Character. One or more directories to sweep.
#'
#' @return A data frame with one row per file and the columns \code{path},
#'   \code{study}, \code{folder}, \code{status}, \code{depth}, \code{naming},
#'   \code{prefix}, \code{is_template}, \code{stem}, \code{ext},
#'   \code{prefix_class}, \code{folder_expected} and \code{folder_ok}.
#'   Zero rows if the roots hold no files.
#'
#' @seealso \code{\link{job_census}}, \code{\link{hvti_taxonomy}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "job-files-example")
#' dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#' job_files(d)[, c("study", "folder", "prefix", "status")]
#' unlink(d, recursive = TRUE)
job_files <- function(roots) {
  stopifnot(is.character(roots), length(roots) >= 1L)

  per_root <- lapply(roots, function(r) {
    paths <- list.files(r, recursive = TRUE, full.names = TRUE,
                        all.files = TRUE, no.. = TRUE)
    paths <- paths[!dir.exists(paths)]
    if (!length(paths)) return(NULL)

    base <- basename(paths)
    fields <- .job_name_fields(base)
    place <- .job_placement(paths, r)

    # The stem drops the FINAL extension only: hz.dead.lst -> hz.dead, so the
    # .lst, .sas, .log and .sas~ of one job share a stem and count as one job.
    has_ext <- grepl("[.]", base)
    stem <- ifelse(has_ext, sub("[.][^.]*$", "", base), base)
    ext <- ifelse(has_ext, sub("^.*[.]", "", base), NA_character_)

    # A name whose only dot is a leading one (.DS_Store, .gitignore) drops
    # its entire name under the split above, leaving stem = "" and the whole
    # name misread as the extension. macOS writes .DS_Store throughout any
    # share this corpus is swept from, so this is common, not hypothetical.
    # Treat it the same as a name with no dot at all: whole name as stem, no
    # extension.
    no_real_ext <- has_ext & !nzchar(stem)
    stem <- ifelse(no_real_ext, base, stem)
    ext <- ifelse(no_real_ext, NA_character_, ext)

    tx <- hvti_taxonomy()
    # incomparables = NA keeps an unmatched (NA) prefix from matching the
    # taxonomy's own NA prefix row ("estimates") -- match() otherwise pairs
    # NA with NA and mislabels every unclassified file as an estimates file.
    i <- match(fields$prefix, tx$prefix, incomparables = NA_character_)
    folder_expected <- tx$folder[i]

    prefix_class <- ifelse(
      is.na(fields$prefix), NA_character_,
      ifelse(!is.na(i), "known",
             ifelse(fields$prefix %in% hvti_non_prefixes(),
                    "non_prefix", "unknown"))
    )

    data.frame(
      path = paths,
      study = place$study,
      folder = place$folder,
      status = place$status,
      depth = place$depth,
      naming = fields$naming,
      prefix = fields$prefix,
      is_template = fields$is_template,
      stem = stem,
      ext = ext,
      prefix_class = prefix_class,
      folder_expected = folder_expected,
      folder_ok = !is.na(folder_expected) & !is.na(place$folder) &
        folder_expected == place$folder,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, per_root)
  if (is.null(out)) {
    out <- data.frame(
      path = character(0), study = character(0), folder = character(0),
      status = character(0), depth = integer(0), naming = character(0),
      prefix = character(0), is_template = logical(0), stem = character(0),
      ext = character(0), prefix_class = character(0),
      folder_expected = character(0), folder_ok = logical(0),
      stringsAsFactors = FALSE
    )
  }
  rownames(out) <- NULL
  out
}

#' Roll a job-file inventory up to studies and prefixes
#'
#' @description
#' Answers the question the template roadmap keeps needing: for each job
#' prefix, which studies have run it and how many jobs each.
#'
#' @details
#' Two count columns, deliberately. \code{n_jobs} counts distinct stems and is
#' the honest unit -- the \code{.lst}, \code{.sas} and \code{.log} of one job
#' are one job, and an editor backup does not create a second. \code{n_files}
#' counts rows, and exists because the hand-count this replaces counted files;
#' keeping both means the new output can be reconciled against the table that
#' already drove a decision.
#'
#' The \code{job_files()} rows are kept on the result as the \code{"files"}
#' attribute, so the accounting -- unplaced files, unknown prefixes, misfiled
#' jobs -- stays reachable from the summary rather than being computed and
#' thrown away.
#'
#' @param x Character roots to sweep, or a data frame returned by
#'   \code{\link{job_files}}.
#'
#' @return A data frame of class \code{hvti_job_census} with one row per
#'   \code{(study, prefix, folder, is_template)} and columns \code{n_jobs} and
#'   \code{n_files}. The originating \code{job_files()} rows are attached as
#'   the \code{"files"} attribute.
#'
#' @seealso \code{\link{job_files}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "job-census-example")
#' dir.create(file.path(d, "alpha", "distributions"), recursive = TRUE)
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.lst"))
#' file.create(file.path(d, "alpha", "distributions", "hz.dead.sas"))
#' job_census(d)
#' unlink(d, recursive = TRUE)
job_census <- function(x) {
  files <- if (is.data.frame(x)) x else job_files(x)

  keep <- !is.na(files$prefix) & !is.na(files$study)
  src <- files[keep, , drop = FALSE]

  if (!nrow(src)) {
    out <- data.frame(
      study = character(0), prefix = character(0), folder = character(0),
      is_template = logical(0), n_jobs = integer(0), n_files = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    key <- paste(src$study, src$prefix, src$folder, src$is_template,
                 sep = "\r")
    split_src <- split(src, key)
    out <- do.call(rbind, lapply(split_src, function(g) {
      data.frame(
        study = g$study[[1]],
        prefix = g$prefix[[1]],
        folder = g$folder[[1]],
        is_template = g$is_template[[1]],
        n_jobs = length(unique(g$stem)),
        n_files = nrow(g),
        stringsAsFactors = FALSE
      )
    }))
    out <- out[order(out$prefix, out$study, out$is_template), , drop = FALSE]
  }

  rownames(out) <- NULL
  attr(out, "files") <- files
  class(out) <- c("hvti_job_census", "data.frame")
  out
}
