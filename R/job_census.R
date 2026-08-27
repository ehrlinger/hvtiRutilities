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
  # winslash = "/" on BOTH calls. normalizePath() defaults to winslash = "\\"
  # on Windows, which would hand .job_placement_rel() a path separated by
  # backslashes; R-CMD-check.yaml runs windows-latest, so the default would
  # redden CI with a census of zero rows rather than fail loudly.
  # And it is still worth calling normalizePath() at all, rather than
  # skipping it to dodge the winslash issue entirely: without it, a symlinked
  # root (/var -> /private/var on macOS) leaves the root's raw path and the
  # file's resolved path disagreeing, so the prefix strip in
  # .job_placement_rel() fails to line up.
  .job_placement_rel(
    normalizePath(paths, winslash = "/", mustWork = FALSE),
    normalizePath(root, winslash = "/", mustWork = FALSE)
  )
}

# The classification itself, on already-normalised paths. Split out from
# .job_placement() so the separator handling can be asserted on directly:
# through normalizePath() the Windows bug is untestable on a Mac, and an
# untestable guarantee is one that regresses.
.job_placement_rel <- function(npaths, nroot) {
  folders <- unique(hvti_taxonomy()$folder)

  # Strip the root prefix BY POSITION, not with a regex anchor. A root path is
  # arbitrary input -- a directory named "study (copy)" or "v1.2+" carries
  # regex metacharacters -- and an unescaped anchor matches the wrong thing
  # while still looking like it worked, because `.` and `-` match themselves.
  rel <- substring(npaths, nchar(nroot) + 2L)

  # Accept either separator. "/" is what winslash = "/" produces, and the
  # backslash arm is the belt to that braces: a component split that silently
  # returns the whole path as one element classifies every file "unplaced",
  # which reads as a clean empty answer rather than as a bug.
  parts <- strsplit(rel, "[/\\\\]")

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

# Validate, normalise and de-overlap the sweep roots.
#
# A root that does not exist is an ERROR, not an empty result. The corpus
# lives on a share, and a share that failed to mount is an empty directory
# indistinguishable from a corpus with no jobs in it -- a confident zero-row
# answer there is the failure this sweep exists to make impossible.
.job_roots <- function(roots) {
  if (anyNA(roots)) {
    stop("job_files(): `roots` contains NA. Every root must name an existing ",
         "directory that CONTAINS studies.", call. = FALSE)
  }
  for (r in roots) {
    if (dir.exists(r)) next
    if (file.exists(r)) {
      stop("job_files(): root is a file, not a directory: ", r,
           ". A root must be a directory containing studies.", call. = FALSE)
    }
    stop("job_files(): root does not exist: ", r,
         ". If it is a network share, check that it is mounted -- an ",
         "unmounted share and an empty corpus produce the same table.",
         call. = FALSE)
  }

  norm <- normalizePath(roots, winslash = "/", mustWork = FALSE)
  # The same path twice would emit every file twice under the same study
  # label, doubling n_files for no reason a reader could see.
  norm <- norm[!duplicated(norm)]
  if (length(norm) < 2L) return(norm)

  # An inner root emits every file beneath it a SECOND time, under a second
  # study label, so a prefix present in one study reads as two distinct
  # studies -- and distinct studies is the number that decides whether a
  # template is unblocked.
  #
  # Guarded on length above: paste0(character(0), "/") is "/", not
  # character(0), so a single root would otherwise test as sitting inside a
  # phantom root named "" and drop itself.
  encloses <- function(i) startsWith(norm[i], paste0(norm[-i], "/"))
  inner <- vapply(seq_along(norm), function(i) any(encloses(i)), logical(1))
  for (i in which(inner)) {
    outer <- norm[-i][encloses(i)][[1]]
    warning("job_files(): root '", norm[i], "' sits inside root '", outer,
            "', so every file under it would be counted twice, once under ",
            "each root's study labels. Dropping the inner root.",
            call. = FALSE)
  }
  norm[!inner]
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
#' \code{folder_ok} is \code{folder == folder_expected}, and is therefore
#' \code{NA} -- not \code{FALSE} -- whenever either side is unknown. An
#' unplaced file has no folder and an unparsed name has no expected folder;
#' neither is a misfiled job, and \code{!folder_ok} must not select them.
#'
#' \strong{Run this server-side.} It stats every file beneath \code{roots},
#' which is metadata-latency-bound over an SMB mount -- a 40-file scan has
#' timed out at two minutes over the share.
#'
#' @param roots Character. One or more directories to sweep. A root is a
#'   directory that \emph{contains} studies, not a study itself: the study is
#'   read as the path from the root down to the taxonomy folder's parent, so a
#'   root that is itself a study leaves nothing to name it and every prefix
#'   collapses to one study called \code{"."} (warned about). Each root must
#'   exist and be a directory, or this errors. A duplicate root is dropped; a
#'   root nested inside another warns and the inner one is dropped, since its
#'   files would otherwise be counted twice under two study labels.
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
  if (!is.character(roots)) {
    stop("job_files(): `roots` must be a character vector of directory ",
         "paths, not ", class(roots)[1], ".", call. = FALSE)
  }
  if (length(roots) < 1L) {
    stop("job_files(): `roots` must have length at least one; got a ",
         "zero-length character vector. Provide at least one directory ",
         "to sweep.", call. = FALSE)
  }
  roots <- .job_roots(roots)

  per_root <- lapply(roots, function(r) {
    # ONE filesystem pass, not three. `r` arrives already normalised from
    # .job_roots(), and list.files() prefixes every result with the root
    # exactly as given -- so these paths are already root-prefixed and
    # .job_placement_rel() can strip the prefix directly.
    #
    # The two passes removed were a per-file normalizePath() and a per-file
    # dir.exists(), each a stat syscall. On a local disk that is invisible;
    # over the SMB mount the corpus is actually read from, each stat is a
    # network round-trip and they dominated the walk.
    #
    # Removing normalizePath() also FIXES an attribution bug rather than
    # trading correctness for speed. It resolves symlinks, so a file under a
    # symlinked subdirectory came back as its real path -- and when that real
    # path lies outside the root, the prefix strip slices at the wrong offset
    # and yields a mangled `study` with no error. The walked path is the
    # right answer: a file found under a study belongs to that study.
    #
    # dir.exists() was belt-and-braces: list.files(recursive = TRUE) does not
    # return directories at all.
    paths <- list.files(r, recursive = TRUE, full.names = TRUE,
                        all.files = TRUE, no.. = TRUE)
    if (!length(paths)) return(NULL)

    base <- basename(paths)
    fields <- .job_name_fields(base)
    place <- .job_placement_rel(paths, r)

    # study "." means the taxonomy folder was the first component under the
    # root -- the root IS a study. Two study roots passed together both label
    # ".", merge into one row, and every prefix reports 1 distinct study: the
    # template gate falsely BLOCKED, which is as wrong as falsely unblocked.
    if (any(place$study %in% ".")) {
      warning("job_files(): root '", r, "' holds a taxonomy folder at its ",
              "top level, so files there cannot be attributed to a study ",
              "and are labelled study = \".\". A root must sit ABOVE the ",
              "studies it sweeps, not be one -- pass the directory that ",
              "CONTAINS the studies.", call. = FALSE)
    }

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
      # NA in, NA out. "The folder is wrong" and "there is no folder to
      # judge" are different claims, and collapsing them to FALSE made
      # README.md, notes.txt and Makefile all report as misfiled jobs.
      folder_ok = folder_expected == place$folder,
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

# The 13 columns job_files() promises. job_census() validates against this
# rather than trusting any data frame it is handed: a frame that is not
# job_files() output otherwise produced a valid-LOOKING census whose print
# emitted three confident zeros and then aborted with "invalid argument
# type", naming nothing.
.job_files_columns <- function() {
  c("path", "study", "folder", "status", "depth", "naming", "prefix",
    "is_template", "stem", "ext", "prefix_class", "folder_expected",
    "folder_ok")
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
#' \strong{A template is not a job, by either marker.} \code{is_template} is
#' strictly the legacy \code{tp.} prefix (spec section 4); a file written in
#' the \code{template} naming convention (section 4.2, e.g.
#' \code{03.01-ac.qmd}) is \emph{also} not a job, but with \code{is_template
#' = FALSE}. \code{is_template_naming} carries that second signal, and the
#' roll-up keys on both, so a template-convention file never shares a row
#' with a genuine job at the same \code{(study, prefix, folder)} -- if it
#' did, that row could outlive the genuine job and still read as an
#' attestation the distinct-studies gate (a prefix needs a second study
#' running the real job before it is templatable) would wrongly count.
#'
#' The \code{job_files()} rows are kept on the result as the \code{"files"}
#' attribute, so the accounting -- unplaced files, unknown prefixes, misfiled
#' jobs -- stays reachable from the summary rather than being computed and
#' thrown away.
#'
#' \strong{The roll-up cannot key every row}, and says so rather than
#' shrinking quietly: a file with no study or no prefix has nothing to group
#' by. Those rows are attached as the \code{"not_rolled_up"} attribute and
#' counted on the first line of the print, because what was dropped is the
#' \emph{union} of the unplaced and the unparsed and a reader cannot compute a
#' union from two separate totals.
#'
#' \strong{Subsetting.} A row subset (\code{x[i, ]}) keeps both attributes. A
#' \emph{column} subset (\code{x[, j]}) drops them while leaving the class in
#' place, so the result still dispatches to this print method with nothing to
#' print from; \code{print()} detects that and errors rather than reporting
#' zeros. The printed coverage line (\code{"Rolled up N of M files"}) always
#' describes the full original sweep, even from a row-subset \code{x}: its
#' totals are fixed as an attribute when \code{job_census()} builds \code{x},
#' not recomputed from \code{x$n_files} at print time.
#'
#' @param x Character roots to sweep -- see \code{\link{job_files}} for what a
#'   root must be -- or a data frame returned by \code{\link{job_files}}. A
#'   data frame missing any of that function's 13 columns is an error, not a
#'   silently empty census.
#'
#' @return A data frame of class \code{hvti_job_census} with one row per
#'   \code{(study, prefix, folder, is_template, is_template_naming)} and
#'   columns \code{n_jobs} and \code{n_files}. \code{is_template_naming} is
#'   \code{TRUE} when the row's files use the \code{template} naming
#'   convention (section 4.2) -- distinct from \code{is_template}, which is
#'   strictly the legacy \code{tp.} marker. The originating \code{job_files()}
#'   rows are attached as the \code{"files"} attribute, and the rows that
#'   could not be rolled up -- those with no study or no prefix -- as the
#'   \code{"not_rolled_up"} attribute.
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
  if (is.data.frame(x)) {
    absent <- setdiff(.job_files_columns(), names(x))
    if (length(absent)) {
      stop("job_census(): `x` is a data frame but is not job_files() output ",
           "-- missing column(s): ", paste(absent, collapse = ", "),
           ". Pass job_files() output, or the character roots to sweep.",
           call. = FALSE)
    }
    files <- x
  } else {
    files <- job_files(x)
  }

  keep <- !is.na(files$prefix) & !is.na(files$study)
  src <- files[keep, , drop = FALSE]
  dropped <- files[!keep, , drop = FALSE]
  rownames(dropped) <- NULL

  if (!nrow(src)) {
    out <- data.frame(
      study = character(0), prefix = character(0), folder = character(0),
      is_template = logical(0), is_template_naming = logical(0),
      n_jobs = integer(0), n_files = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    # naming == "template" is a SEPARATE key dimension from is_template (the
    # legacy tp. marker, spec section 4). Without this split, a
    # template-convention file (e.g. 03.01-ac.qmd) rolls up into the SAME row
    # as a genuine job at the same (study, prefix, folder) -- and once the
    # genuine job is gone, the row survives on the template alone, is_template
    # still FALSE, and it satisfies the distinct-studies gate as if a real job
    # had run there.
    template_naming <- src$naming %in% "template"
    key <- paste(src$study, src$prefix, src$folder, src$is_template,
                 template_naming, sep = "\r")
    split_src <- split(src, key)
    out <- do.call(rbind, lapply(split_src, function(g) {
      data.frame(
        study = g$study[[1]],
        prefix = g$prefix[[1]],
        folder = g$folder[[1]],
        is_template = g$is_template[[1]],
        is_template_naming = g$naming[[1]] %in% "template",
        n_jobs = length(unique(g$stem)),
        n_files = nrow(g),
        stringsAsFactors = FALSE
      )
    }))
    out <- out[order(out$prefix, out$study, out$is_template,
                      out$is_template_naming), , drop = FALSE]
  }

  rownames(out) <- NULL
  attr(out, "files") <- files
  attr(out, "not_rolled_up") <- dropped
  # Fixed at creation, so the coverage line print() prints stays correct even
  # after a row subset (x[i, ], which base R keeps these attributes across --
  # see @details). sum(x$n_files) recomputed from a subset x would only total
  # the rows still present, going incoherent against nrow(attr(x, "files")),
  # which is always the full sweep.
  attr(out, "n_files_total") <- sum(out$n_files)
  class(out) <- c("hvti_job_census", "data.frame")
  out
}

#' @param ... Ignored; present for S3 consistency with \code{print}.
#' @rdname job_census
#' @export
print.hvti_job_census <- function(x, ...) {
  files <- attr(x, "files")
  if (is.null(files)) {
    stop("`x` has no \"files\" attribute -- print.hvti_job_census() needs ",
         "the job_files() rows job_census() attaches to do its accounting. ",
         "Build `x` with job_census(), and don't subset its columns (e.g. ",
         "x[, c(...)]) before printing it -- that drops the attribute while ",
         "keeping the class.", call. = FALSE)
  }
  not_rolled <- attr(x, "not_rolled_up")
  if (is.null(not_rolled)) {
    # Recomputable from `files` by the same rule job_census() applies, so a
    # hand-built object still gets an honest coverage line.
    not_rolled <- files[is.na(files$prefix) | is.na(files$study), ,
                        drop = FALSE]
  }

  # One cap for every example list below. Uncapped, the unknown-prefix list
  # ran to hundreds of lines on a real corpus while placement examples were
  # capped at three; and a list that truncates without saying so is the same
  # defect class as a filter that drops without saying so.
  cap <- 5L
  say_more <- function(shown, total, noun = NULL) {
    if (total > shown) {
      extra <- total - shown
      label <- if (is.null(noun)) "" else {
        plural <- if (extra == 1L) {
          noun
        } else if (grepl("x$", noun)) {
          paste0(noun, "es")
        } else {
          paste0(noun, "s")
        }
        paste0(" ", plural)
      }
      cat("    ... and ", extra, " more", label, " not shown\n", sep = "")
    }
  }

  # Neither is_template (the legacy tp. marker) nor is_template_naming (the
  # `template` naming convention, section 4.2) is a job -- a template counted
  # here would satisfy the distinct-studies gate below on its own. Defaults
  # to FALSE if is_template_naming is absent (a hand-built object predating
  # this column), which recycles safely rather than silently emptying `jobs`.
  tpl_naming <- if ("is_template_naming" %in% names(x)) {
    x$is_template_naming
  } else {
    FALSE
  }
  jobs <- x[!x$is_template & !tpl_naming, , drop = FALSE]

  # The lookup that replaces the hand-count. A prefix present in one study
  # cannot be templated: a template extracted from a single example encodes
  # that study's choices as though they were general.
  cat("Jobs by prefix -- distinct studies is the column that says whether a\n")
  cat("template is unblocked (a prefix at 1 study is blocked).\n\n")
  if (nrow(jobs)) {
    by_prefix <- do.call(rbind, lapply(split(jobs, jobs$prefix), function(g) {
      data.frame(prefix = g$prefix[[1]],
                 distinct_studies = length(unique(g$study)),
                 n_jobs = sum(g$n_jobs),
                 n_files = sum(g$n_files),
                 stringsAsFactors = FALSE)
    }))
    by_prefix <- by_prefix[order(-by_prefix$distinct_studies,
                                 by_prefix$prefix), , drop = FALSE]
    rownames(by_prefix) <- NULL
    print.data.frame(by_prefix)
  } else {
    cat("  (none)\n")
  }

  tpl_files <- sum(x$n_files[x$is_template])
  cat("\nTemplates (tp.), counted separately from jobs: ", tpl_files,
      if (tpl_files == 1L) " file\n" else " files\n", sep = "")

  # Coverage first, because it is the number the two tallies below cannot be
  # combined into: what the roll-up dropped is the UNION of the files with no
  # study and the files with no prefix, and those two sets overlap.
  # n_files_total is fixed by job_census() at creation (see @details), so
  # this reads correctly even from a row-subset x -- sum(x$n_files) on a
  # subset would total only the rows still present, going incoherent against
  # n_all, which is always the full sweep. Falls back to sum(x$n_files) for a
  # hand-built object predating the attribute.
  n_all <- nrow(files)
  n_files_total <- attr(x, "n_files_total")
  if (is.null(n_files_total)) n_files_total <- sum(x$n_files)
  cat("\nRolled up ", n_files_total, " of ", n_all, " file",
      if (n_all == 1L) "" else "s", "; ", nrow(not_rolled),
      " not attributable to a study or a prefix.\n", sep = "")

  # Every bucket below prints whether or not it has contents. A bucket that
  # prints nothing cannot be told apart from one nobody computed.
  cat("\nPlacement:\n")
  for (s in c("placed", "nested", "unplaced")) {
    hit <- files$path[files$status == s]
    cat("  ", s, ": ", length(hit), "\n", sep = "")
    if (s != "placed" && length(hit)) {
      shown <- utils::head(hit, cap)
      cat("    e.g. ", paste(shown, collapse = "\n    "), "\n", sep = "")
      say_more(length(shown), length(hit))
    }
  }

  # The header counts FILES (nrow(unknown)); the list below and its
  # truncation remainder count PREFIXES (length(tab), a table keyed by
  # prefix). Both units are named explicitly so the two counts are never
  # mistaken for the same thing.
  unknown <- files[files$prefix_class %in% "unknown", , drop = FALSE]
  cat("\nUnknown prefixes (not in hvti_taxonomy(), not in ",
      "hvti_non_prefixes()): ", nrow(unknown), " file",
      if (nrow(unknown) == 1L) "" else "s", "\n", sep = "")
  if (nrow(unknown)) {
    tab <- sort(table(unknown$prefix), decreasing = TRUE)
    for (p in utils::head(names(tab), cap)) {
      cat("  ", p, ": ", tab[[p]], "  e.g. ",
          unknown$path[unknown$prefix == p][1], "\n", sep = "")
    }
    say_more(min(length(tab), cap), length(tab), "prefix")
  }

  # folder_ok is NA when there is no folder or no expected folder, so
  # which() -- which drops NA -- selects exactly the genuinely misfiled.
  mis <- files[which(!files$folder_ok), , drop = FALSE]
  cat("\nMisfiled (prefix outside its taxonomy folder): ", nrow(mis), "\n",
      sep = "")
  if (nrow(mis)) {
    for (i in seq_len(min(nrow(mis), cap))) {
      cat("  ", basename(mis$path[i]), " in ", mis$folder[i],
          ", expected ", mis$folder_expected[i], "\n", sep = "")
    }
    say_more(min(nrow(mis), cap), nrow(mis))
  }

  unparsed <- sum(is.na(files$naming))
  cat("\nUnparsed names (no convention matched): ", unparsed, "\n", sep = "")

  # A complete tally, not a sample, so the cap does not apply: `ext` is the
  # column an allowlist would have silently narrowed, and a truncated
  # extension list is how that narrowing would hide.
  cat("\nExtensions:\n")
  ext_tab <- sort(table(files$ext, useNA = "ifany"), decreasing = TRUE)
  if (!length(ext_tab)) {
    cat("  (none)\n")
  } else {
    labels <- names(ext_tab)
    labels[is.na(labels)] <- "(none)"
    for (i in seq_along(ext_tab)) {
      cat("  ", labels[i], ": ", ext_tab[[i]], "\n", sep = "")
    }
  }

  invisible(x)
}
