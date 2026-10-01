# An exclusive lock on a study's .checkpoint/, so two sessions cannot
# interleave reconcile, snapshot and delivery on one outbox and one clone.
# dir.create() is atomic: of two sessions creating .checkpoint/lock at once,
# exactly one succeeds. The holder writes its user, pid, start time and a
# token into the lock's holder.yml once, so a refusal can name it, and
# creates a lease file named for the token, lease-<token>. The lease time is
# that file's mtime. The holder refreshes it between phases
# (.cp_lock_touch()), so a lock whose lease is older than the stale age was
# left by a crashed session and is taken over with a warning, by an atomic
# rename (.cp_lock_take_stale()) rather than a delete. A lock with no lease
# file, written before leases existed, is judged by holder.yml's time.
# study_status() only reads and takes no lock. Checkpoints run on the
# server's local filesystem, never over an SMB mount, so dir.create() and
# file.rename() are atomic here.

.cp_lock_stale_mins <- function() 6 * 60

.cp_lock_holder <- function(lock) {
  h <- tryCatch(yaml::read_yaml(file.path(lock, "holder.yml")),
                error = function(e) NULL, warning = function(w) NULL)
  if (is.list(h)) h else list()
}

.cp_lock_lease <- function(lock, token) file.path(lock, paste0("lease-", token))

# What a session judges when it finds a lock: the holder record and the
# mtime of every lease file, as numbers so identical() compares them exactly.
# A rename keeps file mtimes, so the same lock reads the same after one.
.cp_lock_state <- function(lock) {
  leases <- list.files(lock, pattern = "^lease-", full.names = TRUE)
  mtimes <- as.numeric(file.mtime(leases))
  names(mtimes) <- basename(leases)
  list(holder = .cp_lock_holder(lock), leases = mtimes)
}

# When the lock was last known alive: its newest lease or, for a lock with
# no lease file, holder.yml's time, or failing both the directory's mtime.
.cp_lock_since <- function(lock, state) {
  if (length(state$leases)) {
    return(as.POSIXct(max(state$leases), origin = "1970-01-01", tz = "UTC"))
  }
  since <- suppressWarnings(as.POSIXct(as.character(.cp_or(state$holder$time, NA)),
                                       format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (is.na(since)) since <- file.mtime(lock)
  since
}

# Write holder.yml whole or not at all: write a file beside it, then rename
# it into place, so a reader never sees a half-written holder. The temporary
# file is in the lock directory, so the rename stays on one filesystem.
.cp_lock_write_holder <- function(lock, h) {
  tmp <- tempfile("holder-", tmpdir = lock, fileext = ".yml")
  yaml::write_yaml(h, tmp)
  if (!file.rename(tmp, file.path(lock, "holder.yml"))) {
    unlink(tmp)
    stop("could not write the checkpoint lock's holder file", call. = FALSE)
  }
  invisible(NULL)
}

# Take over a lock judged stale, state `judged` (.cp_lock_state()). Returns
# TRUE when this session took it over and `lock` is now free for
# dir.create(), FALSE when another session got there first.
#
# The lock is renamed aside, not deleted. A rename is atomic: of two sessions
# renaming the same directory, exactly one succeeds and the other finds its
# source gone. The new name is unique to this attempt (pid and a fresh UUID),
# so the rename never lands on an existing path, which POSIX and Windows
# treat differently.
#
# The rename moves whatever directory is at `lock` at that instant, and that
# need not be the one judged: another session may have taken the stale lock
# over in the gap and hold a live lock there now, or the holder may have
# refreshed its lease in the gap. So the state is read again from the renamed
# directory, and a holder or lease time other than the judged one is a live
# lock taken by mistake. It is put back and this session reports that
# another session took the lock first. Putting it back claims the name with
# dir.create(), which is atomic, and then moves the holder and lease in.
# Renaming the directory back is not used: on POSIX a rename silently
# replaces an empty directory, which could be a lock a third session has just
# created. If a third session claims the name first, the lock cannot be put
# back; it is discarded, the third session holds the lock, and the session
# whose lock was moved stops with the lost-lock error at its next
# .cp_lock_touch(). That needs three sessions inside one gap of milliseconds
# on a lock six hours stale. A judged lock with no lease and an unreadable
# holder (its time came from the directory's mtime) cannot be told apart from
# a lock whose holder and lease are not written yet; both read as empty.
.cp_lock_take_stale <- function(lock, judged) {
  aside <- paste0(lock, ".stale-", Sys.getpid(), "-", uuid::UUIDgenerate())
  if (!suppressWarnings(file.rename(lock, aside))) return(FALSE)
  on.exit(unlink(aside, recursive = TRUE, force = TRUE), add = TRUE)
  if (identical(.cp_lock_state(aside), judged)) return(TRUE)
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
    state <- .cp_lock_state(lock)
    h <- state$holder
    since <- .cp_lock_since(lock, state)
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
    if (!.cp_lock_take_stale(lock, state) || !dir.create(lock, showWarnings = FALSE)) {
      stop(caller, "(): another session took the checkpoint lock first; ",
           "retry when it has finished", call. = FALSE)
    }
  }
  token <- uuid::UUIDgenerate()
  .cp_lock_write_holder(lock, list(user = Sys.info()[["user"]], pid = Sys.getpid(),
                                   time = .cp_utc(Sys.time()), token = token))
  if (!file.create(.cp_lock_lease(lock, token), showWarnings = FALSE)) {
    unlink(lock, recursive = TRUE, force = TRUE)
    stop(caller, "(): could not create the checkpoint lock's lease file",
         call. = FALSE)
  }
  list(lock = lock, token = token, created = created, caller = caller)
}

# Refresh the lease, so a long call is not judged stale while it is still
# working. Called between phases, not from a timer, so one phase must finish
# within the stale age. The refresh is one call on a path named for this
# session's token, with no read before it: Sys.setFileTime() sets the mtime
# of lease-<token> or, when that file does not exist, returns FALSE without
# creating it (checked on R 4.6.1). A takeover renames the whole lock
# directory away and creates a new one, so afterwards the path is either
# gone or inside the new holder's directory, which has no lease with this
# token, and the call fails. It never writes over the new holder.
#
# A failed refresh stops the caller with the lost-lock error rather than
# returning FALSE, because the lock now belongs to another session. Stopping
# is safe at every call site: the work done before a touch is either local
# (selection, the clone's working tree) or already committed and logged, and
# delivery runs again on the next call. The one place where an error would
# undo shared state is .cp_snapshot(), which skips its rollback for this
# error.
.cp_lock_touch <- function(held) {
  if (is.null(held)) return(invisible(FALSE))
  if (!isTRUE(Sys.setFileTime(.cp_lock_lease(held$lock, held$token), Sys.time()))) {
    stop(structure(
      class = c("hvti_cp_lock_lost", "error", "condition"),
      list(message = paste0(.cp_or(held$caller, "checkpoint"), "(): the checkpoint ",
                            "lock was taken over by another session; retry when it ",
                            "has finished"),
           call = NULL)
    ))
  }
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
