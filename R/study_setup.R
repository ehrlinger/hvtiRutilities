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

# Append the lines of `lines` not already in the file, exactly; create it if
# absent. A user's own lines are never reordered or removed.
.study_append_lines_missing <- function(lines, path) {
  have <- if (file.exists(path)) readLines(path, warn = FALSE) else character(0)
  add <- setdiff(lines, have)
  if (!file.exists(path)) return(.study_write_lines_if_missing(lines, path))
  if (length(add)) {
    size <- file.size(path)
    unterminated <- size > 0 && !identical(readBin(path, "raw", size)[size], as.raw(10L))
    con <- file(path, "a")
    on.exit(close(con), add = TRUE)
    if (unterminated) writeLines("", con)
    writeLines(add, con)
  }
  invisible(length(add) > 0L)
}

.renv_installed <- function() requireNamespace("renv", quietly = TRUE)

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
    "old_RF_templates*/",
    "tp.*",
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
# working directory. With no study above there is no default, so a new study is
# never created in the working directory unasked. Only a missing _study.yml
# means "no study here"; any other study_config() error, such as a malformed
# _study.yml above, is passed on.
.study_setup_root <- function(start = getwd()) {
  tryCatch(
    study_config(start, require_data = FALSE)$root,
    error = function(e) {
      if (!grepl("no _study.yml found", conditionMessage(e), fixed = TRUE)) stop(e)
      stop("study_setup(): no study contains the working directory, so there is no ",
           "default root. Pass `root =` to name the study to create, or ",
           "`root = \".\", adopt = TRUE` to set up the current folder.", call. = FALSE)
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

# The template corpus (the folder studies were copied from, minus any .git):
# name, size and MD5 of every file other than tp.* (deleted by name alone),
# desktop litter, and the .renvignore and .gitignore study_setup() relies on.
.study_template_index <- function(template_dir) {
  if (!dir.exists(template_dir)) {
    stop("study_setup(): template corpus not found at ", template_dir,
         "; pass template_dir", call. = FALSE)
  }
  rel <- list.files(template_dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  rel <- rel[!vapply(strsplit(rel, "/", fixed = TRUE), function(p) ".git" %in% p, logical(1))]
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

# The real path of a file or folder that may not exist yet: the nearest
# existing ancestor resolved, the rest appended.
.study_real_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  tail <- character(0)
  while (!file.exists(path) && dirname(path) != path) {
    tail <- c(basename(path), tail)
    path <- dirname(path)
  }
  do.call(file.path, as.list(c(normalizePath(path, winslash = "/"), tail)))
}

# TRUE when one path is the other or lies inside it.
.study_paths_overlap <- function(a, b) {
  a <- .study_real_path(a)
  b <- .study_real_path(b)
  identical(a, b) || startsWith(a, paste0(b, "/")) || startsWith(b, paste0(a, "/"))
}

# unlink(), as a seam the tests can blank to stand in for a permission failure.
.study_unlink <- function(paths, recursive = FALSE) unlink(paths, recursive = recursive)

# Folders cleanup never enters or removes, at any depth: version control,
# checkpoint state and renv libraries.
.study_protected <- function(name) name %in% c(".git", ".checkpoint", "renv")

# Relative paths of the template files to delete and the folders to check
# afterwards. Symbolic links are never followed or deleted, and protected
# folders are never entered.
.study_cleanup_scan <- function(root, index, rel = character(0)) {
  dir <- if (length(rel)) file.path(root, rel) else root
  found <- list(files = character(0), folders = character(0))
  for (name in list.files(dir, all.files = TRUE, no.. = TRUE)) {
    child <- if (length(rel)) file.path(rel, name) else name
    full <- file.path(root, child)
    if (nzchar(Sys.readlink(full))) next
    if (dir.exists(full)) {
      if (.study_protected(name)) next
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
  # removing its children goes too. A folder goes only when its own entries
  # are desktop litter files: any folder left in it (one the cleanup did not
  # empty, a protected one) or any symbolic link keeps it.
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
    entries <- list.files(full, all.files = TRUE, no.. = TRUE)
    litter_only <- all(vapply(entries, function(name) {
      entry <- file.path(full, name)
      .study_litter(name) && !nzchar(Sys.readlink(entry)) && !dir.exists(entry)
    }, logical(1)))
    if (litter_only) {
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

# Which of the three pieces of a renv environment are present and sound: a
# renv/ folder holding activate.R, a .Rprofile that sources it, and a
# renv.lock that parses as a lockfile. A path that merely exists is not enough.
.study_renv_parts <- function(root) {
  lock <- file.path(root, "renv.lock")
  profile <- file.path(root, ".Rprofile")
  lock_ok <- !dir.exists(lock) && file.exists(lock) && isTRUE(tryCatch(
    is.list(jsonlite::read_json(lock)$R), error = function(e) FALSE
  ))
  profile_ok <- !dir.exists(profile) && file.exists(profile) && .sources_renv_activate(profile)
  c(renv = file.exists(file.path(root, "renv", "activate.R")),
    .Rprofile = profile_ok, renv.lock = lock_ok)
}

# Whether a .Rprofile calls source() on activate.R. A study's own profile may
# build the path, as in source(file.path(root, "renv", "activate.R")), possibly
# across lines or through a variable assigned that path, so the file is parsed
# rather than matched line by line: comments and strings then never count, and
# neither does a path built but not sourced. A profile that does not parse
# cannot run, so it is unsound.
.sources_renv_activate <- function(profile) {
  exprs <- tryCatch(parse(profile, keep.source = FALSE), error = function(e) NULL)
  if (is.null(exprs)) return(FALSE)
  calls <- list()
  collect <- function(e) {
    if (is.call(e)) {
      calls[[length(calls) + 1L]] <<- e
      lapply(as.list(e), collect)
    }
    invisible()
  }
  lapply(exprs, collect)
  unqualify <- function(e) {
    if (is.call(e) && identical(e[[1L]], as.name("::"))) e[[3L]] else e
  }
  mentions <- function(e, vars) {
    if (is.character(e)) return(any(grepl("(^|/)activate\\.R$", e)))
    if (is.symbol(e)) return(as.character(e) %in% vars)
    is.call(e) && any(vapply(as.list(e)[-1L], mentions, logical(1L), vars = vars))
  }
  assigned <- Filter(function(e) {
    as.character(unqualify(e[[1L]]))[1L] %in% c("<-", "=", "<<-") && is.symbol(e[[2L]]) &&
      mentions(e[[3L]], character())
  }, calls)
  vars <- vapply(assigned, function(e) as.character(e[[2L]]), character(1L))
  any(vapply(calls, function(e) {
    fn <- unqualify(e[[1L]])
    if (!is.symbol(fn) || !as.character(fn) %in% c("source", "sys.source")) return(FALSE)
    file <- tryCatch(match.call(match.fun(as.character(fn)), e)$file, error = function(err) NULL)
    !is.null(file) && mentions(file, vars)
  }, logical(1L)))
}

# The study-setup command's renv step (qhsprograms study_setup/workflow.py):
# keep a complete environment, resume one interrupted after init, refuse any
# other partial one, otherwise init bare and snapshot.
.study_init_renv <- function(root, r_upgrade = FALSE) {
  core <- c("renv", ".Rprofile", "renv.lock")
  sound <- .study_renv_parts(root)
  if (all(sound)) return("retained")
  present <- file.exists(file.path(root, core))
  resumable <- all(sound[c("renv", ".Rprofile")]) && !present[3L]
  if (any(present) && !resumable) {
    stop("study_setup(): partial renv environment; sound: ",
         if (any(sound)) paste(core[sound], collapse = ", ") else "none",
         "; missing or invalid: ", paste(core[!sound], collapse = ", "), call. = FALSE)
  }
  run <- function(expr, what) {
    result <- .study_rscript(expr, root, "--vanilla")
    if (result$status != 0L) {
      detail <- trimws(result$output)
      stop("study_setup(): ", what, " failed: ",
           if (nzchar(detail)) detail else "no output", call. = FALSE)
    }
  }
  if (!resumable) {
    run("renv::init(bare = TRUE, restart = FALSE)", "renv initialization")
  }
  # Declared before init or resume alike: a study interrupted by an older
  # version has no DESCRIPTION yet, and study_declare() is idempotent.
  study_declare(root = root)
  # Explicit mode: renv.lock is built from DESCRIPTION, never by scanning the
  # study's code, so a template copy cleanup missed cannot reach the lockfile.
  # Load and snapshot this project explicitly: a child that relied on its
  # startup loading .Rprofile could run with no project and the global
  # library, and snapshot the wrong thing.
  # The child below is Rscript from this session's R.home(), so this check
  # sees the same R the snapshot would run under.
  guard_snapshot(root, r_upgrade)
  project <- deparse(normalizePath(root, winslash = "/"))
  run(paste0("renv::load(", project, "); renv::settings$use.cache(FALSE, project = ", project,
             "); renv::settings$snapshot.type('explicit', project = ",
             project, "); renv::snapshot(project = ", project, ", prompt = FALSE)"), "renv snapshot")
  if (!all(.study_renv_parts(root))) {
    stop("study_setup(): renv initialization finished without a complete environment",
         call. = FALSE)
  }
  "initialized"
}

#' Set up study identity and directories
#'
#' @description
#' The usual entry point is \code{hvtiR::setup()}. Creates the numbered directory structure for a new study and writes an
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
#' corpus they came from is kept centrally, so no backup is made. A folder
#' the deletions leave holding nothing (desktop litter such as
#' \code{Thumbs.db} aside) is removed, whatever its name, as is an empty
#' \code{templates} or \code{old_RF_templates*} folder; a folder still holding
#' other files stays, as does one holding any folder the cleanup did not
#' empty, and a top-level study folder is never removed. Symbolic links are
#' neither followed nor deleted, and folders named \code{.git},
#' \code{.checkpoint} or \code{renv} are never entered, at any depth. The
#' root and \code{template_dir} must not overlap. A file that cannot be
#' deleted stops the setup with an error.
#'
#' With \code{renv = TRUE}, the study's \code{renv} environment is set up
#' after any cleanup, in a separate R process. A complete environment is
#' kept: a \code{renv/} folder holding \code{activate.R}, a \code{.Rprofile}
#' that sources it, and a \code{renv.lock} that parses as a lockfile. One
#' interrupted after initialization (no lockfile yet) is resumed at the
#' snapshot; any other partial or invalid environment stops with an error.
#' Otherwise the study \code{DESCRIPTION} is written (see
#' \code{\link{study_declare}}), \code{renv::init(bare = TRUE)} creates the
#' environment, and the project is loaded and snapshotted explicitly in
#' explicit mode, so \code{renv.lock} comes from the \code{DESCRIPTION} and
#' not from a scan of the study's code. The study's \code{renv} does not use
#' a per-user package cache (\code{use.cache} is \code{FALSE} in
#' \code{renv/settings.json}), because the library is shared by the team and
#' links into one person's cache that others cannot read break their installs.
#' The renv package must be installed.
#'
#' @param root Character. Study root to create or adopt. When omitted, the
#'   study enclosing the working directory (found as \code{\link{study_root}}
#'   finds it) is used. Outside a study there is no default:
#'   \code{study_setup()} stops and writes nothing, so a new study always names
#'   its directory. Use \code{root = "."} with \code{adopt = TRUE} to set up
#'   the current folder.
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
#'   empty. See Details. Defaults to \code{adopt}: adopting a study cleans it,
#'   including an adoption accepted at the prompt. Pass \code{FALSE} to adopt
#'   without cleaning.
#' @param template_dir Character(1). The template corpus studies were copied
#'   from, read when \code{cleanup = TRUE}. Setup stops with an error when it
#'   does not exist.
#' @param renv Logical. Initialize and snapshot the study's \code{renv}
#'   environment. See Details. Defaults to \code{TRUE}; test suites that build
#'   temporary studies should pass \code{FALSE}.
#' @param r_upgrade Logical(1). Leave \code{FALSE}. The renv snapshot is
#'   refused from an R whose major.minor differs from the R recorded in the
#'   study's \code{renv.lock} (see \code{\link{guard_snapshot}}), because it
#'   would rewrite the lock's R and drop packages. Set \code{TRUE} only when
#'   you are deliberately moving the study to this session's R.
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
#' @examples
#' root <- file.path(tempdir(), "study-setup-example")
#' study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE)
#' list.files(root)
#'
#' # Running it again on an existing study needs adopt = TRUE; nothing that
#' # exists is overwritten.
#' invisible(study_setup(root, study = "Example", study_tracker_id = 1L,
#'                       adopt = TRUE, renv = FALSE, cleanup = FALSE))
#'
#' # cleanup = TRUE deletes the template copies a legacy study carries: tp.*
#' # files, and files identical to one in the template corpus.
#' corpus <- file.path(tempdir(), "template-corpus")
#' dir.create(corpus)
#' writeLines("# template", file.path(corpus, "readme.R"))
#' invisible(file.copy(file.path(corpus, "readme.R"),
#'                     file.path(root, "30_analyses")))
#' writeLines("# template", file.path(root, "30_analyses", "tp.hazard.R"))
#' done <- study_setup(root, study = "Example", study_tracker_id = 1L,
#'                     adopt = TRUE, cleanup = TRUE, renv = FALSE,
#'                     template_dir = corpus)
#' attr(done, "cleanup")
#'
#' unlink(c(root, corpus), recursive = TRUE)
#'
#' @export
study_setup <- function(root = NULL, study, study_tracker_id,
                        umbrella = NULL, owner = NULL,
                        irb_number = NULL, cvir_no = NULL,
                        study_creation_date = NULL, adopt = FALSE,
                        identity_source = c("tracker", "manual"),
                        cleanup = adopt, renv = TRUE,
                        template_dir = "/programs/development/template",
                        r_upgrade = FALSE) {
  # cleanup defaults to the FINAL adopt, which the interactive prompt below may
  # set. Validating it here would force the default with the caller's adopt.
  cleanup_given <- !missing(cleanup)
  # Exact values only: match.arg() would accept an abbreviation such as
  # "man", and a provenance field should record what the caller meant.
  sources <- c("tracker", "manual")
  if (identical(identity_source, sources)) identity_source <- "tracker"
  if (!is.character(identity_source) || length(identity_source) != 1L ||
        !identity_source %in% sources) {
    stop("study_setup(): identity_source must be \"tracker\" or ",
         "\"manual\"", call. = FALSE)
  }
  root <- if (is.null(root)) .study_setup_root() else .study_scalar(root, "root", required = TRUE)
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
  for (flag in c("adopt", if (cleanup_given) "cleanup", "renv")) {
    value <- get(flag)
    if (length(value) != 1L || is.na(value) || !is.logical(value)) {
      stop("study_setup(): ", flag, " must be TRUE or FALSE", call. = FALSE)
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
  if (existed && !length(entries) && !adopt) {
    stop("study_setup(): root already exists; use adopt = TRUE",
         call. = FALSE)
  }
  if (identity_exists) {
    existing <- .read_study_yml(yml, "study_setup")
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

  if (!cleanup_given) cleanup <- adopt
  if (cleanup) {
    template_dir <- .study_scalar(template_dir, "template_dir", required = TRUE)
    if (!dir.exists(template_dir)) {
      stop("study_setup(): template corpus not found at ", template_dir,
           "; pass template_dir, or cleanup = FALSE", call. = FALSE)
    }
    if (.study_paths_overlap(root, template_dir)) {
      stop("study_setup(): the study root and template_dir overlap; cleanup would ",
           "delete the corpus or the study", call. = FALSE)
    }
  }

  if (renv && !all(.study_renv_parts(root))) {
    if (!.renv_installed()) {
      stop("study_setup(): the renv package is not installed; install it, or pass renv = FALSE",
           call. = FALSE)
    }
    desc <- file.path(root, "DESCRIPTION")
    if (file.exists(desc)) {
      dcf <- read.dcf(desc)
      if (!"Type" %in% colnames(dcf) || !identical(unname(dcf[1L, "Type"]), "Project")) {
        stop("study_setup(): ", desc, " is a package DESCRIPTION, not a study project's; ",
             "pass renv = FALSE", call. = FALSE)
      }
    }
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
  .study_append_lines_missing(
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
  renv_state <- if (renv) .study_init_renv(root, r_upgrade)

  status <- study_status(root)
  attr(status, "cleanup") <- cleaned
  attr(status, "renv") <- renv_state
  status
}
