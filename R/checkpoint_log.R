# The outbox: .checkpoint/log.yml, one entry per checkpoint, closure or
# reopening, in the StudyTracker Workspace API's record shapes so qhsprograms
# can post an entry unchanged. The core marks git delivery; qhsprograms marks
# ST delivery. Entries are appended, and only their delivery fields change.

.cp_log_path <- function(root) file.path(root, ".checkpoint", "log.yml")

.cp_log_read <- function(root) {
  path <- .cp_log_path(root)
  if (!file.exists(path)) return(list())
  .cp_or(yaml::read_yaml(path), list())
}

.cp_log_write <- function(root, log) {
  path <- .cp_log_path(root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .atomic_write(path, function(tmp) yaml::write_yaml(log, tmp))
  invisible(log)
}

.cp_log_append <- function(root, entry) {
  .cp_log_write(root, c(.cp_log_read(root), list(entry)))
  invisible(entry)
}

.cp_entry_id <- function(entry) {
  .cp_or(entry$checkpoint_id, .cp_or(entry$closure_id, entry$reopening_id))
}

# One date, as a Date or a "YYYY-MM-DD" string. as.Date() alone read
# "01/02/2026" as year 1 and 20260101 as year 57440, and the result went into
# the tag message and to ST without a word.
.cp_date <- function(x, what = "date") {
  ok <- length(x) == 1L && !is.na(x) &&
    (inherits(x, "Date") ||
       (is.character(x) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) &&
          !is.na(as.Date(x, format = "%Y-%m-%d"))))
  if (!ok) {
    stop(what, " must be one Date or one \"YYYY-MM-DD\" string, not ",
         paste(format(x), collapse = ", "), call. = FALSE)
  }
  format(as.Date(x), "%Y-%m-%d")
}

# Set fields on the one entry with this id and rewrite the log atomically.
# Used for the committing -> committed / abandoned transitions; a NULL in
# `fields` would delete the key, so callers pass only values.
.cp_log_update <- function(root, id, fields) {
  log <- .cp_log_read(root)
  hit <- which(vapply(log, function(e) identical(.cp_entry_id(e), id),
                      logical(1)))
  if (length(hit) != 1L) {
    stop("no outbox entry with id ", id, call. = FALSE)
  }
  for (k in names(fields)) log[[hit]][[k]] <- fields[[k]]
  .cp_log_write(root, log)
  invisible(log[[hit]])
}
