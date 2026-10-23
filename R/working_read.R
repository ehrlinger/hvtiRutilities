# Reading the working dataset before it is registered. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 5.1, and
# dev/specs/2026-10-23-working-read-gate-design.md.
#
# Any read that is not of a dated version serves the working file, so the
# gate applies to the data read, not to the `working` argument. It is honoured
# in the interactive console and in draft renders of jobs in any stage folder;
# a final render or an Rscript job must read registered data.

.hvti_working_default <- function() {
  value <- Sys.getenv("HVTI_DATA", "")
  if (!nzchar(value)) return(FALSE)
  if (identical(value, "working")) return(TRUE)
  stop("HVTI_DATA is \"", value, "\". The only accepted value is \"working\", which reads the working ",
       "dataset; unset HVTI_DATA to read registered data.", call. = FALSE)
}

# Bindings over base and knitr so tests can stand in for a render or Rscript.
.is_interactive <- function() interactive()
.command_args <- function() commandArgs(trailingOnly = FALSE)
.knitr_input <- function() {
  if (!requireNamespace("knitr", quietly = TRUE)) return(NULL)
  knitr::current_input(dir = TRUE)
}

# A final render, as hvtiRtemplates' render_job(final = TRUE) marks one. Read with
# .strict_render()'s parsing there, so the two packages cannot disagree on a value.
.final_render <- function() !tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")

# The job being run: the document knitr is rendering, else the script Rscript was given.
.job_file <- function() {
  input <- .knitr_input()
  if (!is.null(input)) return(input)
  arg <- grep("^--file=", .command_args(), value = TRUE)
  # R writes a space in the script's path as "~+~" (measured 2026-10-13).
  if (!length(arg)) return(NULL)
  file <- gsub("~+~", " ", sub("^--file=", "", arg[[1L]]), fixed = TRUE)
  if (grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", file)) return(file)
  # A relative path is relative to where the script was launched, which setwd() cannot change. PWD is
  # that directory; without it the job cannot be placed, and the caller refuses it.
  launch <- Sys.getenv("PWD", "")
  if (!nzchar(launch)) return(NULL)
  file.path(launch, file)
}

# Resolve symlinks (macOS /var -> /private/var, a symlinked mount) the same way
# for a path whether or not it exists: normalise its deepest existing ancestor
# and re-append the rest. normalizePath() alone leaves a missing path as given.
.real_path <- function(path) {
  path <- path.expand(path)
  rest <- character()
  while (!file.exists(path) && !identical(dirname(path), path)) {
    rest <- c(basename(path), rest)
    path <- dirname(path)
  }
  do.call(file.path, as.list(c(normalizePath(path, mustWork = FALSE), rest)))
}

# `unregistered`: the dataset has no dated version. `explicit`: the caller passed working = TRUE.
# `env`: HVTI_DATA made the read a working read. The message names only the causes and exits that apply.
.assert_working_stage <- function(cfg, built, caller = "read_built", unregistered = TRUE, explicit = FALSE, env = FALSE) {
  job <- .job_file()
  if (is.null(job) && .is_interactive()) return(invisible(TRUE))
  rendering <- !is.null(.knitr_input())
  where <- NULL
  if (!is.null(job)) {
    job <- .real_path(job)
    root <- .real_path(cfg$root)
    if (startsWith(job, paste0(root, "/")) || startsWith(job, paste0(root, "\\"))) {
      parts <- strsplit(substring(job, nchar(root) + 2L), "[/\\\\]")[[1L]]
      where <- if (length(parts) > 1L) "stage" else "root"
    }
  }
  # A draft render of a job in any folder below the study root may read the working file; nothing else may.
  if (identical(where, "stage") && rendering && !.final_render()) return(invisible(TRUE))
  final <- identical(where, "stage") && rendering
  who <- if (is.null(job)) {
    "A non-interactive session with no job file can"
  } else if (is.null(where)) {
    paste0(basename(job), " is outside the study, so it can")
  } else if (identical(where, "root")) {
    paste0(basename(job), " is at the study root, outside any stage folder, so it can")
  } else if (final) {
    paste0(basename(job), " is a final render, so it can")
  } else {
    paste0(basename(job), " runs under Rscript, so it can")
  }
  why <- if (unregistered) {
    paste0(built, " has no dated version")
  } else {
    c(if (explicit) "working = TRUE asks for the working file", if (env) "HVTI_DATA asks for the working file")
  }
  # With a dated version the request is the only reason this is a working read, so the exits are to drop it.
  # Without one, dropping the request still serves the working file: registering is the only way out.
  fix <- if (unregistered) {
    c("register it with update_manifest()", if (final) "render a draft")
  } else {
    c(if (explicit) "call read_built() without working = TRUE", if (env) "unset HVTI_DATA")
  }
  stop(caller, "(): ", who, " read registered data only. ", paste(why, collapse = " and "), ". ",
       sub("^(.)", "\\U\\1", paste(fix, collapse = ", or "), perl = TRUE), ".", call. = FALSE)
}

.working_read_condition <- function(file) {
  structure(
    class = c("hvtiRutilities_working_read", "message", "condition"),
    list(message = paste0("Read the working ", file, ", not a registered version. Results from it are a draft.\n"),
         call = NULL)
  )
}

# The one place the message is signalled, so the test suite can stand in for it.
.signal_working_read <- function(file) message(.working_read_condition(file))
