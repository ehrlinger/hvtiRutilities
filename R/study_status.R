# The compliance auditor. One read-only function serves both ends of a study's
# life: study_init() calls it to report what a new study still lacks, and
# close-out will call it to grade a publication record. Two near-identical
# scanners would drift.
#
# Every check is reported, never raised. A study with no _study.yml is the
# finding, not a failure -- and the studies that most need describing are
# exactly the ones that would make a strict version error out.

# Directories excluded from every count. A study's renv/ holds a package
# library with thousands of .R files that say nothing about the study, and
# counting them would make the R-file count meaningless. Hidden directories
# (.git, .Rproj.user) are already skipped by list.files().
.status_excluded <- function() {
  c("renv", "packrat", "renv.cache")
}

# Files under `root` matching `pattern`, with excluded directories pruned at
# any depth -- a nested analyses/*/renv/ must be dropped too, not just a
# top-level one.
.status_files <- function(root, pattern) {
  hits <- list.files(root, pattern = pattern, recursive = TRUE,
                     full.names = TRUE)
  if (!length(hits)) return(character(0))
  parts <- strsplit(hits, .Platform$file.sep, fixed = TRUE)
  drop  <- vapply(parts, function(p) any(p %in% .status_excluded()),
                  logical(1))
  hits[!drop]
}

.status_row <- function(item, status, detail) {
  data.frame(item = item, status = status, detail = detail,
             stringsAsFactors = FALSE)
}

# verify_manifest(stop_on_error = FALSE) reports failures through warning()
# and returns the report invisibly. tryCatch() with a warning handler would
# capture the condition and discard the report, so the warning is muffled with
# a calling handler instead and the return value kept.
.status_manifest <- function(root) {
  path <- file.path(root, "manifest.yaml")
  if (!file.exists(path)) {
    return(.status_row("manifest.yaml", "MISSING",
                       "no manifest.yaml; study_init() seeds one"))
  }

  rep <- tryCatch(
    withCallingHandlers(
      verify_manifest(manifest_path = path,
                      data_dir      = file.path(root, "datasets"),
                      stop_on_error = FALSE,
                      verbose       = FALSE),
      warning = function(w) invokeRestart("muffleWarning")),
    error = function(e) e)

  if (inherits(rep, "error")) {
    return(.status_row("manifest.yaml", "FAIL", conditionMessage(rep)))
  }
  if (nrow(rep) == 0L) {
    return(.status_row("manifest.yaml", "MISSING",
                       "manifest.yaml lists no datasets"))
  }

  bad <- rep[rep$status == "FAIL", , drop = FALSE]

  # verify_manifest() compares the SHA-256 first and returns early on a
  # mismatch, so a row-count complaint means the checksum matched. For a
  # .sas7bdat it always complains: re-deriving the row count needs
  # options(manifest.allow_heavy_rowcount = TRUE), which loads the entire
  # dataset into memory. Reporting that as drift would put every real study
  # permanently in FAIL, on the strength of the weaker of the two checks.
  rowcount_only <- grepl("^Row count auto-detection failed", bad$message)
  drift         <- bad[!rowcount_only, , drop = FALSE]

  if (nrow(drift)) {
    .status_row("manifest.yaml", "FAIL",
                paste0(nrow(drift), " of ", nrow(rep), " entries failed: ",
                       paste(drift$file, collapse = ", ")))
  } else {
    detail <- paste0(nrow(rep), " dataset entr",
                     if (nrow(rep) == 1L) "y" else "ies",
                     " verified by checksum")
    if (any(rowcount_only)) {
      detail <- paste0(detail, " (row count not re-derived for ",
                       sum(rowcount_only), ")")
    }
    .status_row("manifest.yaml", "OK", detail)
  }
}

# The denominator is .qmd/.Rmd sources, not rendered outputs. A legacy study
# holds decades of .pdf and Word-exported documents that are not analysis
# outputs; counting them would report unrecorded results on every such study
# and teach the reader to ignore this check.
#
# Matching is by file name, not by path. record_provenance() writes the sidecar
# beside the *output*, and Quarto's output-dir means that is often not the
# source's directory, so a path comparison would report every rendered job as
# unrecorded. The cost is that two sources sharing a name cannot be told apart,
# which is a real gap rather than a cosmetic one -- a sidecar for one would
# otherwise vouch for the other -- so duplicated names are named in the detail.
.status_provenance <- function(root) {
  src   <- .status_files(root, "[.](qmd|Rmd)$")
  cars  <- .status_files(root, "[.]provenance[.]json$")
  stems <- sub("[.]provenance$", "",
               tools::file_path_sans_ext(basename(cars)))

  if (!length(src)) {
    return(.status_row("provenance", "MISSING",
                       paste0("no .qmd sources found; ", length(cars),
                              " sidecar",
                              if (length(cars) == 1L) "" else "s")))
  }

  # Names, deduplicated: the comparison is set-based, so the counts reported
  # must be over distinct names too, or a study with a repeated name yields an
  # arithmetically impossible "11 of 12".
  names_all <- tools::file_path_sans_ext(basename(src))
  want      <- unique(names_all)
  missing   <- setdiff(want, stems)

  dup     <- unique(names_all[duplicated(names_all)])
  dup_note <- if (length(dup)) {
    paste0(" (", length(dup), " name",
           if (length(dup) == 1L) "" else "s",
           " used by more than one source and so indistinguishable here: ",
           paste(dup, collapse = ", "), ")")
  } else {
    ""
  }

  if (!length(missing)) {
    .status_row("provenance", "OK",
                paste0("all ", length(want),
                       " .qmd source names have a provenance sidecar",
                       dup_note))
  } else {
    .status_row("provenance", "FAIL",
                paste0(length(missing), " of ", length(want),
                       " .qmd source names have no provenance sidecar: ",
                       paste(missing, collapse = ", "), dup_note))
  }
}

#' Audit a study's reproducibility readiness
#'
#' @description
#' Reports, without writing anything, whether a study has the four things a
#' later result needs in order to be re-derivable: a valid \code{_study.yml},
#' an \code{renv.lock}, a \code{manifest.yaml} whose checksums still match the
#' data, and a provenance sidecar for every \code{.qmd} source.
#'
#' Every finding is reported rather than raised. A study with no
#' \code{_study.yml} is the thing this function exists to describe, so it must
#' not error on one. Checks that cannot run because an earlier one failed are
#' reported \code{"MISSING"}, never \code{"FAIL"} -- a check that could not run
#' is not a check that failed, and conflating the two makes the audit
#' unreadable on exactly the legacy studies it is most needed for.
#'
#' Unlike \code{\link{study_config}}, this function does \strong{not} walk up
#' the directory tree. It asks whether \code{root} itself is a study root, so
#' that a subdirectory of a study is never mistaken for one.
#'
#' The provenance check matches sidecars to sources \strong{by file name},
#' because \code{\link{record_provenance}} writes the sidecar beside the
#' rendered output and Quarto's output directory is usually not the source's
#' directory. Two sources sharing a name therefore cannot be distinguished; the
#' repeated names are reported in the check's detail so the gap is visible
#' rather than silent.
#'
#' @param root Character. The study root to audit. Defaults to \code{getwd()}.
#'
#' @return An object of class \code{"study_status"}: a list with \code{root},
#'   \code{checks} (a data frame of \code{item}, \code{status} --
#'   \code{"OK"}, \code{"MISSING"} or \code{"FAIL"} -- and \code{detail}, six
#'   rows), and \code{counts} (a list of \code{r_files}, \code{qmd},
#'   \code{sas_jobs} and \code{sidecars}).
#'
#' @seealso \code{\link{study_init}}, \code{\link{study_checklist}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-status-example")
#' dir.create(root, showWarnings = FALSE)
#' study_status(root)
#' unlink(root, recursive = TRUE)
study_status <- function(root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)

  # _study.yml. Checked at root by file.exists() rather than by calling
  # study_config() first, because study_config() walks up: on a subdirectory
  # of a real study it would succeed and report the parent's manifest as this
  # directory's.
  yml <- file.path(root, "_study.yml")
  cfg <- NULL
  if (!file.exists(yml)) {
    row_yml <- .status_row("_study.yml", "MISSING",
                           "no _study.yml at this root; run study_init()")
  } else {
    parsed <- tryCatch(study_config(root), error = function(e) e)
    if (inherits(parsed, "error")) {
      row_yml <- .status_row("_study.yml", "FAIL", conditionMessage(parsed))
    } else {
      cfg <- parsed
      row_yml <- .status_row("_study.yml", "OK",
                             paste0("study: ", cfg$study))
    }
  }

  row_lock <- if (file.exists(file.path(root, "renv.lock"))) {
    .status_row("renv.lock", "OK", "renv.lock present")
  } else {
    .status_row("renv.lock", "MISSING",
                "no renv.lock; run renv::init() in the study project")
  }

  row_man <- .status_manifest(root)

  if (is.null(cfg)) {
    row_data   <- .status_row("dataset", "MISSING",
                              "requires a valid _study.yml")
    row_cohort <- .status_row("cohort", "MISSING",
                              "requires a valid _study.yml")
  } else {
    p <- built_path(cfg)
    if (!file.exists(p)) {
      row_data   <- .status_row("dataset", "MISSING",
                                paste("not found:", p))
      row_cohort <- .status_row("cohort", "MISSING",
                                "requires the built dataset")
    } else {
      row_data <- .status_row("dataset", "OK", basename(p))
      gate <- tryCatch({
        assert_cohort(read_built(cfg), cfg)
        TRUE
      }, error = function(e) conditionMessage(e))
      row_cohort <- if (isTRUE(gate)) {
        .status_row("cohort", "OK",
                    paste0("N=", cfg$cohort$n,
                           " / events=", cfg$cohort$n_events,
                           " / censored=", cfg$cohort$n_censored))
      } else {
        .status_row("cohort", "FAIL", gate)
      }
    }
  }

  out <- list(
    root   = root,
    checks = rbind(row_yml, row_lock, row_man, row_data, row_cohort,
                   .status_provenance(root)),
    counts = list(
      r_files  = length(.status_files(root, "[.]R$")),
      qmd      = length(.status_files(root, "[.](qmd|Rmd)$")),
      sas_jobs = length(.status_files(root, "[.]sas$")),
      sidecars = length(.status_files(root, "[.]provenance[.]json$"))
    )
  )
  class(out) <- "study_status"
  out
}

#' @export
print.study_status <- function(x, ...) {
  mark <- c(OK = "[x]", MISSING = "[ ]", FAIL = "[!]")
  cat("Study: ", x$root, "\n\n", sep = "")
  for (i in seq_len(nrow(x$checks))) {
    cat(mark[[x$checks$status[i]]], " ", x$checks$item[i],
        " \u2014 ", x$checks$detail[i], "\n", sep = "")
  }
  cat("\n", x$counts$r_files, " .R  |  ", x$counts$qmd, " .qmd  |  ",
      x$counts$sas_jobs, " .sas  |  ", x$counts$sidecars,
      " provenance sidecars\n", sep = "")
  invisible(x)
}
