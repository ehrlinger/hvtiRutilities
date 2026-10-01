# An exclusive lock on a study's .checkpoint/, so two sessions cannot
# interleave reconcile, snapshot and delivery on one outbox and one clone.
# dir.create() is atomic: of two sessions creating .checkpoint/lock at once,
# exactly one succeeds. The holder writes its user, pid and start time into
# the lock, so a refusal can name it. The holder refreshes that time between
# phases (.cp_lock_touch()), so a lock whose time is older than the stale age
# was left by a crashed session and is taken over with a warning, by an
# atomic rename (.cp_lock_take_stale()) rather than a delete.
# study_status() only reads and takes no lock. Checkpoints run on the
# server's local filesystem, never over an SMB mount, so dir.create() and
# file.rename() are atomic here.

.cp_lock_stale_mins <- function() 6 * 60

.cp_lock_holder <- function(lock) {
  h <- tryCatch(yaml::read_yaml(file.path(lock, "holder.yml")),
                error = function(e) NULL, warning = function(w) NULL)
  if (is.list(h)) h else list()
}

# Write holder.yml whole or not at all: write a file beside it, then rename
# it over the old one, so a reader never sees a half-written holder. The
# temporary file is in the lock directory, so the rename stays on one
# filesystem; file.rename() replaces an existing file on Windows too.
.cp_lock_write_holder <- function(lock, h) {
  tmp <- tempfile("holder-", tmpdir = lock, fileext = ".yml")
  yaml::write_yaml(h, tmp)
  if (!file.rename(tmp, file.path(lock, "holder.yml"))) {
    unlink(tmp)
    stop("could not write the checkpoint lock's holder file", call. = FALSE)
  }
  invisible(NULL)
}

# Take over a lock judged stale, holder `judged`. Returns TRUE when this
# session took it over and `lock` is now free for dir.create(), FALSE when
# another session got there first.
#
# The lock is renamed aside, not deleted. A rename is atomic: of two sessions
# renaming the same directory, exactly one succeeds and the other finds its
# source gone. The new name is unique to this attempt (pid and a fresh UUID),
# so the rename never lands on an existing path, which POSIX and Windows
# treat differently.
#
# The rename moves whatever directory is at `lock` at that instant, and that
# need not be the one judged: another session may have taken the stale lock
# over in the gap and hold a live lock there now. So the holder is read again
# from the renamed directory, and anything other than the judged holder is a
# live lock taken by mistake. It is put back and this session reports that
# another session took the lock first. Putting it back claims the name with
# dir.create(), which is atomic, and then moves the holder file in. Renaming
# the directory back is not used: on POSIX a rename silently replaces an
# empty directory, which could be a lock a third session has just created.
# If a third session claims the name first, the lock cannot be put back; it
# is discarded, the third session holds the lock, and the session whose lock
# was moved finds its token gone at its next .cp_lock_touch(). That needs
# three sessions inside one gap of milliseconds on a lock six hours stale.
# A judged holder that could not be read (the time came from the
# directory's mtime) cannot be told apart from a lock whose holder is not
# written yet; both read as empty.
.cp_lock_take_stale <- function(lock, judged) {
  aside <- paste0(lock, ".stale-", Sys.getpid(), "-", uuid::UUIDgenerate())
  if (!suppressWarnings(file.rename(lock, aside))) return(FALSE)
  on.exit(unlink(aside, recursive = TRUE, force = TRUE), add = TRUE)
  if (identical(.cp_lock_holder(aside), judged)) return(TRUE)
  if (dir.create(lock, showWarnings = FALSE)) {
    moved <- list.files(aside, all.files = TRUE, no.. = TRUE)
    file.rename(file.path(aside, moved), file.path(lock, moved))
  }
  FALSE
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
    if (!.cp_lock_take_stale(lock, h) || !dir.create(lock, showWarnings = FALSE)) {
      stop(caller, "(): another session took the checkpoint lock first; ",
           "retry when it has finished", call. = FALSE)
    }
  }
  token <- uuid::UUIDgenerate()
  .cp_lock_write_holder(lock, list(user = Sys.info()[["user"]], pid = Sys.getpid(),
                                   time = .cp_utc(Sys.time()), token = token))
  list(lock = lock, token = token, created = created)
}

# Refresh the holder's time, so a long call is not judged stale while it is
# still working. Only a lock this call still holds is touched: one taken over
# as stale belongs to another session. Called between phases, not from a
# timer, so one phase must finish within the stale age. The token check and
# the write are two steps, so a takeover in between could still be
# overwritten; the write itself is atomic (.cp_lock_write_holder()), so the
# holder file is never seen half-written.
.cp_lock_touch <- function(held) {
  if (is.null(held)) return(invisible(FALSE))
  h <- .cp_lock_holder(held$lock)
  if (!identical(h$token, held$token)) return(invisible(FALSE))
  h$time <- .cp_utc(Sys.time())
  .cp_lock_write_holder(held$lock, h)
  invisible(TRUE)
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
