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

.cp_date <- function(x) format(as.Date(x), "%Y-%m-%d")
