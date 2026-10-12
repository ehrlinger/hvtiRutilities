# Study identity exists before study data. This function creates only the
# package-owned study structure and identity state; register_data() completes
# the data contract later.

.study_write_atomic <- function(value, path) {
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  yaml::write_yaml(value, tmp)
  if (!file.rename(tmp, path)) {
    stop("could not move the prepared file into place: ", path,
         call. = FALSE)
  }
  invisible(path)
}

.study_write_lines_if_missing <- function(lines, path) {
  if (file.exists(path)) return(invisible(FALSE))

  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeLines(lines, tmp)
  if (!file.rename(tmp, path)) {
    stop("could not move the prepared file into place: ", path,
         call. = FALSE)
  }
  invisible(TRUE)
}

.study_renvignore <- function() {
  c(
    ".checkpoint/",
    "00_datasets/",
    "datasets/",
    "40_graphs/",
    "graphs/",
    "50_documents/",
    "documents/",
    "90_estimates/",
    "estimates/",
    "templates/",
    "*.sas",
    "*.log",
    "*.lst",
    "*.doc*",
    "*.pp*"
  )
}

.study_scalar <- function(x, name, required = FALSE,
                          caller = "study_setup") {
  if (is.null(x) && !required) return(NULL)
  if (length(x) != 1L || is.na(x) || !nzchar(as.character(x))) {
    stop(caller, "(): ", name, " must be one non-empty value",
         call. = FALSE)
  }
  x
}

# The root study_setup() uses when none is given: the study enclosing the
# working directory, or the working directory itself when there is none. Only
# a missing _study.yml means "no study here"; any other study_config() error,
# such as a malformed _study.yml above, is passed on.
.study_setup_root <- function(start = getwd()) {
  tryCatch(
    study_config(start, require_data = FALSE)$root,
    error = function(e) {
      if (!grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) stop(e)
      normalizePath(start, mustWork = TRUE)
    }
  )
}

# Wrapped so tests can stand in for an interactive session.
.study_interactive <- function() interactive()

.study_ask_adopt <- function(root) {
  utils::askYesNo(paste0(root, " already has a _study.yml for this study. ",
                         "Adopt it, adding only what is missing?"),
                  default = FALSE)
}

# Template copies a legacy study carries: tp.* files, binder.summaries.doc and
# the other files of the template corpus are copied in at study creation,
# before any analysis, and are out of date from then on; the corpus they came
# from is kept centrally. renv
# scans them for dependencies, which is why a legacy renv::init() asked for
# hundreds of packages.
.study_cleanup_folder <- function(name) {
  name == "templates" || startsWith(name, "old_RF_templates")
}

.study_litter <- function(name) {
  tolower(name) %in% c(".ds_store", "thumbs.db", "desktop.ini") || startsWith(name, "._")
}

# The template corpus (the folder studies were copied from, minus its .git):
# name, size and MD5 of every file other than tp.* (deleted by name alone),
# desktop litter, and the .renvignore and .gitignore study_setup() relies on.
.study_template_index <- function(template_dir) {
  if (!dir.exists(template_dir)) {
    stop("study_setup(): template corpus not found at ", template_dir,
         "; pass template_dir", call. = FALSE)
  }
  rel <- list.files(template_dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  rel <- rel[!startsWith(rel, ".git/")]
  name <- basename(rel)
  keep <- !startsWith(name, "tp.") & !vapply(name, .study_litter, logical(1)) &
    !name %in% c(".renvignore", ".gitignore")
  full <- file.path(template_dir, rel[keep])
  data.frame(name = name[keep], size = file.size(full),
             md5 = unname(tools::md5sum(full)), stringsAsFactors = FALSE)
}

# TRUE when a study file has the name and exact content of a corpus file.
.study_template_copy <- function(full, name, index) {
  same <- index[index$name == name & index$size == file.size(full), , drop = FALSE]
  nrow(same) > 0L && unname(tools::md5sum(full)) %in% same$md5
}

# unlink(), as a seam the tests can blank to stand in for a permission failure.
.study_unlink <- function(paths, recursive = FALSE) unlink(paths, recursive = recursive)

# Relative paths of the template files to delete and the folders to check
# afterwards. Symbolic links are never followed or deleted; version control,
# checkpoint state and the renv library are never entered.
.study_cleanup_scan <- function(root, index, rel = character(0)) {
  dir <- if (length(rel)) file.path(root, rel) else root
  found <- list(files = character(0), folders = character(0))
  for (name in list.files(dir, all.files = TRUE, no.. = TRUE)) {
    child <- if (length(rel)) file.path(rel, name) else name
    full <- file.path(root, child)
    if (nzchar(Sys.readlink(full))) next
    if (dir.exists(full)) {
      if (name == ".git" || (!length(rel) && name %in% c(".checkpoint", "renv"))) next
      inner <- .study_cleanup_scan(root, index, child)
      found$files <- c(found$files, inner$files)
      found$folders <- c(found$folders, inner$folders,
                         if (.study_cleanup_folder(name)) child)
    } else if (startsWith(name, "tp.") || name == "binder.summaries.doc" ||
                 (name %in% index$name && .study_template_copy(full, name, index))) {
      found$files <- c(found$files, child)
    }
  }
  found
}

.study_cleanup <- function(root, template_dir) {
  found <- .study_cleanup_scan(root, .study_template_index(template_dir))
  .study_unlink(file.path(root, found$files))
  left <- found$files[file.exists(file.path(root, found$files))]
  if (length(left)) {
    stop("study_setup(): cleanup could not delete ", length(left), " file(s), first ",
         paste(utils::head(left, 5L), collapse = ", "), call. = FALSE)
  }
  # A folder the deletions emptied goes (Old-Rplots, tp_ggplot, archive, by
  # whatever name), and so does an empty templates or old_RF_templates folder;
  # a top-level study folder never does. Deepest first, so a parent emptied by
  # removing its children goes too. A folder goes only when nothing but
  # desktop litter is left in it.
  held <- unique(unlist(lapply(dirname(found$files), function(d) {
    parts <- strsplit(d, "/", fixed = TRUE)[[1]]
    vapply(seq_along(parts), function(i) paste(parts[seq_len(i)], collapse = "/"),
           character(1))
  })))
  folders <- unique(c(found$folders, held))
  folders <- folders[folders != "." & grepl("/", folders, fixed = TRUE)]
  folders <- folders[order(-lengths(strsplit(folders, "/", fixed = TRUE)), folders)]
  removed <- character(0)
  for (folder in folders) {
    full <- file.path(root, folder)
    if (!dir.exists(full)) next
    rest <- list.files(full, recursive = TRUE, all.files = TRUE, no.. = TRUE)
    if (all(vapply(basename(rest), .study_litter, logical(1)))) {
      .study_unlink(full, recursive = TRUE)
      if (dir.exists(full)) {
        stop("study_setup(): cleanup could not remove folder ", folder, call. = FALSE)
      }
      removed <- c(removed, folder)
    }
  }
  list(deleted = found$files, removed_dirs = removed)
}

# Runs one R expression in a fresh R process in the study, as a seam the tests
# replace. renv must run outside this session: init switches the library paths
# of the process it runs in. RENV_CONFIG_AUTOLOADER_ENABLED is cleared for the
# child only: a machine that disables renv autoloading for itself would
# otherwise stop renv::init() from writing the study's .Rprofile.
.study_rscript <- function(expr, root, flags) {
  out <- withr::with_envvar(c(RENV_CONFIG_AUTOLOADER_ENABLED = NA), withr::with_dir(root, suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c(flags, "-e", shQuote(expr)),
    stdout = TRUE, stderr = TRUE, timeout = 300
  ))))
  status <- attr(out, "status")
  list(status = if (is.null(status)) 0L else status, output = paste(out, collapse = "\n"))
}

# The study-setup command's renv step (qhsprograms study_setup/workflow.py):
# keep a complete environment, resume one interrupted after init, refuse any
# other partial one, otherwise init bare and snapshot.
.study_init_renv <- function(root) {
  core <- c("renv.lock", "renv", ".Rprofile")
  present <- file.exists(file.path(root, core))
  if (all(present)) return("retained")
  resumable <- setequal(core[present], c("renv", ".Rprofile"))
  if (any(present) && !resumable) {
    stop("study_setup(): partial renv environment; found ",
         paste(core[present], collapse = ", "), "; missing ",
         paste(core[!present], collapse = ", "), call. = FALSE)
  }
  run <- function(expr, flags, what) {
    result <- .study_rscript(expr, root, flags)
    if (result$status != 0L) {
      detail <- trimws(result$output)
      stop("study_setup(): ", what, " failed: ",
           if (nzchar(detail)) detail else "no output", call. = FALSE)
    }
  }
  if (!resumable) {
    run("renv::init(bare = TRUE, restart = FALSE)", "--vanilla", "renv initialization")
  }
  if (!file.exists(file.path(root, "renv.lock"))) {
    run("renv::snapshot(prompt = FALSE)", "--no-site-file", "renv snapshot")
  }
  if (!all(file.exists(file.path(root, core)))) {
    stop("study_setup(): renv initialization finished without a complete environment",
         call. = FALSE)
  }
  "initialized"
}

#' Set up study identity and directories
#'
#' @description
#' Creates the numbered directory structure for a new study and writes an
#' identity-only \code{_study.yml}. With \code{adopt = TRUE}, an existing
#' study keeps its legacy or numbered directory layout and every existing
#' initialization file.
#'
#' Data are deliberately not required. Call \code{\link{register_data}} after
#' the default or a named dataset exists.
#'
#' When the root holds no \code{.Rproj} file, one named for the root
#' directory is written, so that opening the project and
#' \code{\link{study_root}} agree on the study root. An existing project is
#' left unchanged.
#'
#' With \code{cleanup = TRUE}, the template copies a legacy study carries are
#' deleted before anything else reads the study, anywhere in it: every file
#' whose name starts with \code{tp.}, every \code{binder.summaries.doc}, and
#' every other file whose name and exact content match a file in the template
#' corpus at \code{template_dir}. A study's own file that shares a name with a
#' corpus file but differs from it (an edited \code{references.bib}, say) is
#' kept, as are \code{.renvignore} and \code{.gitignore}. These files are
#' copied in when a study is created, months before any analysis, and the
#' corpus they came from is kept centrally, so no backup is made. A folder the deletions leave holding nothing (desktop litter
#' such as \code{Thumbs.db} aside) is removed, whatever its name, as is an empty
#' \code{templates} or \code{old_RF_templates*} folder; a folder still holding
#' other files stays, and a top-level study folder is never removed. Symbolic links are not followed, and
#' \code{.git}, \code{.checkpoint} and the \code{renv} library are not
#' entered. A file that cannot be deleted stops the setup with an error.
#'
#' With \code{renv = TRUE}, the study's \code{renv} environment is set up
#' after any cleanup, in a separate R process: a complete environment
#' (\code{renv.lock}, \code{renv/} and \code{.Rprofile}) is kept, one
#' interrupted after initialization is resumed at the snapshot, any other
#' partial environment stops with an error, and otherwise
#' \code{renv::init(bare = TRUE)} and \code{renv::snapshot()} create it. The
#' renv package must be installed.
#'
#' @param root Character. Study root to create or adopt. When omitted, the
#'   study enclosing the working directory (found as \code{\link{study_root}}
#'   finds it) is used, or the working directory itself when no
#'   \code{_study.yml} lies above it. An empty working directory is set up as a
#'   new study.
#' @param study Character(1). Study title.
#' @param study_tracker_id Integer(1). Study Tracker topic ID.
#' @param umbrella,owner,irb_number,cvir_no Optional identity values.
#' @param study_creation_date Optional Study Tracker creation date.
#' @param adopt Logical. Permit additive setup in an existing root. When the
#'   root already holds a \code{_study.yml} for the same Study Tracker ID and
#'   the session is interactive, \code{study_setup()} asks whether to adopt it
#'   instead of stopping.
#' @param identity_source Character(1). Where the identity values came
#'   from: \code{"tracker"} (the default), for a Study Tracker record, or
#'   \code{"manual"}, for values typed by hand while the Tracker was
#'   unavailable. A new \code{_study.yml} records it as
#'   \code{identity_source}, with \code{identity_verified} set to
#'   \code{TRUE} for \code{"tracker"} and \code{FALSE} for
#'   \code{"manual"}. An existing \code{_study.yml} is not rewritten, so
#'   adoption keeps the recorded source.
#' @param cleanup Logical. Delete the study's \code{tp.*} template copies and
#'   \code{binder.summaries.doc}, and remove the template folders they leave
#'   empty. See Details.
#' @param template_dir Character(1). The template corpus studies were copied
#'   from, read when \code{cleanup = TRUE}. Setup stops with an error when it
#'   does not exist.
#' @param renv Logical. Initialize and snapshot the study's \code{renv}
#'   environment. See Details.
#'
#' @return An object of class \code{"study_status"}, returned visibly. With
#'   \code{cleanup = TRUE} it carries a \code{"cleanup"} attribute, a list of
#'   the \code{deleted} files and \code{removed_dirs} folders, relative to the
#'   root. With \code{renv = TRUE} it carries a \code{"renv"} attribute,
#'   \code{"initialized"} or \code{"retained"}.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_config}},
#'   \code{\link{study_dir}}
#'
#' @export
study_setup <- function(root = NULL, study, study_tracker_id,
                        umbrella = NULL, owner = NULL,
                        irb_number = NULL, cvir_no = NULL,
                        study_creation_date = NULL, adopt = FALSE,
                        identity_source = c("tracker", "manual"),
                        cleanup = FALSE, renv = FALSE,
                        template_dir = "/programs/development/template") {
  # Exact values only: match.arg() would accept an abbreviation such as
  # "man", and a provenance field should record what the caller meant.
  sources <- c("tracker", "manual")
  if (identical(identity_source, sources)) identity_source <- "tracker"
  if (!is.character(identity_source) || length(identity_source) != 1L ||
        !identity_source %in% sources) {
    stop("study_setup(): identity_source must be \"tracker\" or ",
         "\"manual\"", call. = FALSE)
  }
  inferred <- is.null(root)
  root <- if (inferred) .study_setup_root() else .study_scalar(root, "root", required = TRUE)
  study <- .study_scalar(study, "study", required = TRUE)
  tracker <- suppressWarnings(as.integer(study_tracker_id))
  if (length(tracker) != 1L || is.na(tracker) || tracker < 1L ||
        !identical(as.character(tracker), as.character(study_tracker_id))) {
    stop("study_setup(): study_tracker_id must be one positive integer",
         call. = FALSE)
  }
  umbrella <- .study_scalar(umbrella, "umbrella")
  owner <- .study_scalar(owner, "owner")
  irb_number <- .study_scalar(irb_number, "irb_number")
  cvir_no <- .study_scalar(cvir_no, "cvir_no")
  if (!is.null(study_creation_date)) {
    study_creation_date <- .study_scalar(
      as.character(study_creation_date),
      "study_creation_date"
    )
  }
  for (flag in c("adopt", "cleanup", "renv")) {
    value <- get(flag)
    if (length(value) != 1L || is.na(value) || !is.logical(value)) {
      stop("study_setup(): ", flag, " must be TRUE or FALSE", call. = FALSE)
    }
  }
  if (cleanup) {
    template_dir <- .study_scalar(template_dir, "template_dir", required = TRUE)
    if (!dir.exists(template_dir)) {
      stop("study_setup(): template corpus not found at ", template_dir,
           "; pass template_dir", call. = FALSE)
    }
  }

  existed <- file.exists(root) || dir.exists(root)
  if (file.exists(root) && !dir.exists(root)) {
    stop("study_setup(): root is a file, not a directory: ", root,
         call. = FALSE)
  }

  entries <- if (dir.exists(root)) {
    setdiff(list.files(root, all.files = TRUE, no.. = TRUE), "")
  } else {
    character(0)
  }
  yml <- file.path(root, "_study.yml")
  identity_exists <- file.exists(yml)
  if (existed && length(entries) && !adopt && !identity_exists) {
    stop("study_setup(): root already contains files; use adopt = TRUE",
         call. = FALSE)
  }
  # An empty working directory the caller is standing in is the study they
  # mean to create; an empty root named explicitly still needs adopt = TRUE.
  if (existed && !length(entries) && !adopt && !inferred) {
    stop("study_setup(): root already exists; use adopt = TRUE",
         call. = FALSE)
  }
  if (identity_exists) {
    existing <- yaml::read_yaml(yml)
    existing_tracker <- suppressWarnings(
      as.integer(existing$study_tracker_id)
    )
    if (length(existing_tracker) != 1L || is.na(existing_tracker)) {
      stop("study_setup(): existing _study.yml has no Study Tracker ID",
           call. = FALSE)
    }
    if (!identical(existing_tracker, tracker)) {
      stop("study_setup(): _study.yml already exists for Study Tracker ID ",
           existing_tracker, call. = FALSE)
    }
    if (!adopt && !(.study_interactive() && isTRUE(.study_ask_adopt(root)))) {
      stop("study_setup(): ", root, " is already set up as a study; use adopt = TRUE ",
           "to fill in what it is missing", call. = FALSE)
    }
    adopt <- TRUE
  }

  layout <- if (!existed || !length(entries)) {
    "numbered"
  } else {
    .study_layout(root)
  }

  if (!dir.exists(root) && !dir.create(root, recursive = TRUE)) {
    stop("study_setup(): could not create root: ", root, call. = FALSE)
  }
  root <- normalizePath(root, mustWork = TRUE)

  folders <- .study_folders()
  leaves <- if (layout == "numbered") unname(folders) else names(folders)
  for (leaf in leaves) {
    path <- file.path(root, leaf)
    if (!dir.exists(path) && !dir.create(path)) {
      stop("study_setup(): could not create directory: ", path,
           call. = FALSE)
    }
  }

  identity <- list(
    study = study,
    study_tracker_id = tracker,
    umbrella = umbrella,
    owner = owner,
    irb_number = irb_number,
    cvir_no = cvir_no,
    study_creation_date = study_creation_date,
    identity_source = identity_source,
    identity_verified = identical(identity_source, "tracker"),
    population = NULL,
    built = NULL,
    citation = NULL
  )
  if (!identity_exists) {
    .study_write_atomic(identity, yml)
  }
  .study_write_lines_if_missing(
    "RENV_CONFIG_CACHE_SYMLINKS=FALSE",
    file.path(root, ".Renviron")
  )
  .study_write_lines_if_missing(
    .study_renvignore(),
    file.path(root, ".renvignore")
  )

  # An R project beside _study.yml means opening the project, here::here()
  # and study_root() all name the same directory. An existing project, of
  # any name, is the author's and is left alone.
  if (!length(list.files(root, pattern = "[.]Rproj$", all.files = TRUE))) {
    .study_write_lines_if_missing(
      c("Version: 1.0", "", "RestoreWorkspace: No", "SaveWorkspace: No",
        "AlwaysSaveHistory: No", "", "EnableCodeIndexing: Yes",
        "Encoding: UTF-8"),
      file.path(root, paste0(basename(root), ".Rproj"))
    )
  }

  # Cleanup before renv: renv discovers dependencies by scanning the study.
  cleaned <- if (cleanup) .study_cleanup(root, template_dir)
  renv_state <- if (renv) .study_init_renv(root)

  status <- study_status(root)
  attr(status, "cleanup") <- cleaned
  attr(status, "renv") <- renv_state
  status
}
