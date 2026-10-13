# Reading the working dataset before it is registered. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 5.1.
#
# Any read that is not of a dated version serves the working file, so the
# gate applies to the data read, not to the `working` argument. It is honoured
# in the interactive console and in jobs in the study's datasets or descriptive
# folder; everywhere else the job must read registered data.

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
  allowed <- vapply(c("datasets", "descriptive"), function(k) basename(study_dir(k, cfg$root)), character(1))
  stage <- NULL
  if (!is.null(job)) {
    job <- .real_path(job)
    root <- .real_path(cfg$root)
    if (startsWith(job, paste0(root, "/")) || startsWith(job, paste0(root, "\\"))) {
      stage <- strsplit(substring(job, nchar(root) + 2L), "[/\\\\]")[[1L]][[1L]]
    }
  }
  if (!is.null(stage) && stage %in% allowed) return(invisible(TRUE))
  who <- if (is.null(job)) {
    "A non-interactive session with no job file can"
  } else if (is.null(stage)) {
    paste0(basename(job), " is outside the study, so it can")
  } else {
    paste0(stage, " jobs")
  }
  why <- if (unregistered) {
    paste0(built, " has no dated version")
  } else {
    c(if (explicit) "working = TRUE asks for the working file", if (env) "HVTI_DATA asks for the working file")
  }
  # With a dated version the request is the only reason this is a working read, so the exits are to drop it.
  # Without one, dropping the request still serves the working file: registering is the only way out.
  fix <- if (unregistered) {
    "register it with register_data() or update_manifest()"
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
