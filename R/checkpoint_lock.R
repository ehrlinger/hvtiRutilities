# An exclusive lock on a study's .checkpoint/, so two sessions cannot
# interleave reconcile, snapshot and delivery on one outbox and one clone.
# dir.create() is atomic: of two sessions creating .checkpoint/lock at once,
# exactly one succeeds. The holder writes its user, pid and start time into
# the lock, so a refusal can name it. A lock older than the stale age was
# left by a crashed session and is taken over with a warning. study_status()
# only reads and takes no lock.

.cp_lock_stale_mins <- function() 30

.cp_lock_holder <- function(lock) {
  h <- tryCatch(yaml::read_yaml(file.path(lock, "holder.yml")),
                error = function(e) NULL, warning = function(w) NULL)
  if (is.list(h)) h else list()
}

.cp_utc <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Take the lock or stop. Returns the handle .cp_unlock() needs. When the
# lock is what creates .checkpoint/, the handle says so, and .cp_unlock()
# removes the directory again if nothing else was written to it: a call
# that fails validation leaves the study as it found it.
.cp_lock <- function(root, caller) {
  cp_dir <- file.path(root, ".checkpoint")
  created <- !dir.exists(cp_dir)
  if (created) dir.create(cp_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(cp_dir, "lock")
  if (!dir.create(lock, showWarnings = FALSE)) {
    h <- .cp_lock_holder(lock)
    since <- suppressWarnings(as.POSIXct(as.character(.cp_or(h$time, NA)),
                                         format = "%Y-%m-%dT%H:%M:%SZ",
                                         tz = "UTC"))
    if (is.na(since)) since <- file.mtime(lock)
    who <- paste0(.cp_or(h$user, "unknown user"), ", pid ",
                  .cp_or(h$pid, "unknown"), ", since ",
                  if (is.na(since)) "an unknown time" else .cp_utc(since))
    age <- as.numeric(difftime(Sys.time(), since, units = "mins"))
    if (is.na(age) || age < .cp_lock_stale_mins()) {
      stop(caller, "(): another session holds the checkpoint lock (", who,
           "); retry when it has finished", call. = FALSE)
    }
    warning(caller, "(): taking over a stale checkpoint lock (", who, ")",
            call. = FALSE)
    unlink(lock, recursive = TRUE, force = TRUE)
    if (!dir.create(lock, showWarnings = FALSE)) {
      stop(caller, "(): another session took the checkpoint lock first; ",
           "retry when it has finished", call. = FALSE)
    }
  }
  token <- uuid::UUIDgenerate()
  yaml::write_yaml(list(user = Sys.info()[["user"]], pid = Sys.getpid(),
                        time = .cp_utc(Sys.time()), token = token),
                   file.path(lock, "holder.yml"))
  list(lock = lock, token = token, created = created)
}

# Release only a lock this call still holds: a lock taken over as stale now
# belongs to another session.
.cp_unlock <- function(held) {
  if (identical(.cp_lock_holder(held$lock)$token, held$token)) {
    unlink(held$lock, recursive = TRUE, force = TRUE)
  }
  cp_dir <- dirname(held$lock)
  if (held$created && dir.exists(cp_dir) &&
        !length(list.files(cp_dir, all.files = TRUE, no.. = TRUE))) {
    unlink(cp_dir, recursive = TRUE)
  }
  invisible(NULL)
}
