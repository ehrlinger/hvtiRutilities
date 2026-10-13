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
  if (length(arg)) return(gsub("~+~", " ", sub("^--file=", "", arg[[1L]]), fixed = TRUE))
  NULL
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

.assert_working_stage <- function(cfg, built, caller = "read_built") {
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
  stop(caller, "(): ", who, " read registered data only. ", built,
       " has no dated version, or HVTI_DATA asks for the working file. Register it with register_data() ",
       "or update_manifest(), or unset HVTI_DATA.", call. = FALSE)
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
