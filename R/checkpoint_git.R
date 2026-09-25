# Git plumbing for study checkpoints. Every call goes through the system git
# binary, so the user's own configuration (Git Credential Manager on the LRI
# server) handles authentication and the package holds no credentials.

.cp_or <- function(x, y) if (is.null(x)) y else x

# Run git in `repo`. Returns list(ok, out) and never raises, so callers can
# treat an unreachable remote as a state rather than an error.
.cp_git <- function(repo, args) {
  out <- suppressWarnings(system2(
    "git", shQuote(c("-C", repo, args)), stdout = TRUE, stderr = TRUE
  ))
  status <- attr(out, "status")
  list(ok = is.null(status) || identical(as.integer(status), 0L),
       out = as.character(out))
}

# Run git in `repo` and raise on failure, naming the command and git's output.
.cp_git_do <- function(repo, args) {
  res <- .cp_git(repo, args)
  if (!res$ok) {
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(res$out, collapse = "\n"), call. = FALSE)
  }
  res$out
}

.cp_require_git <- function(caller) {
  if (!nzchar(Sys.which("git"))) {
    stop(caller, "(): git is not installed or not on the PATH",
         call. = FALSE)
  }
  invisible(TRUE)
}

# The private clone. Its working tree only ever holds files that passed
# .cp_select(), which is what keeps data out of git: no tool can stage a file
# that is not there.
.cp_repo_path <- function(root) file.path(root, ".checkpoint", "repo")

# TRUE when `repo` holds a git repository, FALSE when it has no .git. A .git
# that git does not recognise (on Windows, what a failed delete leaves: git
# writes its objects read-only and unlink() cannot remove them) stops here
# rather than as a raw git error later. The git dir must be repo's own, not a
# parent repository's that git found by walking up.
.cp_has_repo <- function(repo) {
  if (!dir.exists(file.path(repo, ".git"))) return(FALSE)
  res <- .cp_git(repo, c("rev-parse", "--git-dir"))
  if (!res$ok || !identical(res$out[1], ".git")) {
    stop(".checkpoint/repo is not a valid git repository: its .git directory ",
         "is incomplete. Delete .checkpoint/repo and run again; the next ",
         "checkpoint recreates it, from the remote when one is set. On Windows, ",
         "clear the read-only attribute on its files first (git writes them ",
         "read-only), or the delete leaves them behind.", call. = FALSE)
  }
  TRUE
}

# Keep origin pointed at the remote _study.yml names, which qhsprograms may
# write after the first local checkpoint.
.cp_set_remote <- function(repo, remote) {
  if (is.null(remote)) return(invisible(FALSE))
  cur <- .cp_git(repo, c("remote", "get-url", "origin"))
  if (!cur$ok) {
    .cp_git_do(repo, c("remote", "add", "origin", remote))
  } else if (!identical(cur$out[1], remote)) {
    .cp_git_do(repo, c("remote", "set-url", "origin", remote))
  }
  invisible(TRUE)
}

.cp_remote_probe <- function(repo) {
  res <- .cp_git(repo, c("ls-remote", "--heads", "origin", "main"))
  list(reachable = res$ok,
       has_main = res$ok && any(grepl("refs/heads/main$", res$out)),
       out = res$out)
}

# Create the clone on first use. When the remote already has history (a
# re-cloned or second copy), start from it so tag numbers continue.
.cp_repo_init <- function(root, remote = NULL) {
  repo <- .cp_repo_path(root)
  if (.cp_has_repo(repo)) {
    .cp_set_remote(repo, remote)
    return(repo)
  }
  dir.create(repo, recursive = TRUE, showWarnings = FALSE)
  .cp_git_do(repo, c("init", "-q"))
  .cp_git_do(repo, c("symbolic-ref", "HEAD", "refs/heads/main"))
  .cp_set_remote(repo, remote)
  if (!is.null(remote) && .cp_remote_probe(repo)$has_main) {
    .cp_git_do(repo, c("fetch", "-q", "origin",
                       "+refs/heads/main:refs/remotes/origin/main",
                       "+refs/tags/*:refs/tags/*"))
    .cp_git_do(repo, c("reset", "-q", "--hard", "refs/remotes/origin/main"))
  }
  repo
}

.cp_tags <- function(repo, pattern) {
  tags <- .cp_git_do(repo, c("tag", "-l"))
  tags[grepl(pattern, tags)]
}

.cp_seq_of <- function(tags) as.integer(sub("^.*-([0-9]+)$", "\\1", tags))

# Sequence numbers come from the tags themselves, never a counter file, so a
# re-cloned repository cannot hand out a number twice.
.cp_next_tag <- function(repo, prefix) {
  tags <- .cp_tags(repo, paste0("^", prefix, "-[0-9]+$"))
  n <- if (length(tags)) max(.cp_seq_of(tags)) + 1L else 1L
  paste0(prefix, "-", n)
}

# Replace the working tree with `files`, so a file deleted from the study
# shows as a deletion in the next snapshot.
.cp_sync_tree <- function(repo, root, files) {
  old <- setdiff(list.files(repo, all.files = TRUE, no.. = TRUE), ".git")
  unlink(file.path(repo, old), recursive = TRUE, force = TRUE)
  for (rel in files) {
    dest <- file.path(repo, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(root, rel), dest, overwrite = TRUE,
                   copy.date = TRUE)) {
      stop("could not copy ", rel, " into the checkpoint", call. = FALSE)
    }
  }
  invisible(files)
}

.cp_head <- function(repo) {
  res <- .cp_git(repo, c("rev-parse", "--verify", "-q", "HEAD"))
  if (res$ok) res$out[1] else NA_character_
}

.cp_message_file <- function(lines) {
  path <- tempfile("cp-msg-")
  writeLines(lines, path, useBytes = TRUE)
  path
}

.cp_commit_tag <- function(repo, tag, message) {
  msg <- .cp_message_file(message)
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("add", "-A"))
  .cp_git_do(repo, c("commit", "-q", "--allow-empty", "-F", msg))
  .cp_git_do(repo, c("tag", "-a", tag, "-F", msg))
  .cp_head(repo)
}

.cp_tag_head <- function(repo, tag, message) {
  msg <- .cp_message_file(message)
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("tag", "-a", tag, "-F", msg))
  .cp_head(repo)
}

# Undo a partial checkpoint: drop the tag and put main back where it was. An
# NA head means the repository had no commits before.
.cp_rollback <- function(repo, head_before, tag) {
  if (!is.null(tag)) {
    .cp_git(repo, c("tag", "-d", tag))
    # Check if the tag still exists (e.g. tag never existed in the first place)
    verify <- .cp_git(repo, c("rev-parse", "-q", "--verify",
                              paste0("refs/tags/", tag)))
    if (verify$ok) {
      last_line <- if (length(verify$out)) {
        verify$out[length(verify$out)]
      } else {
        "git output unavailable"
      }
      warning("checkpoint rollback did not complete: removing tag ", tag,
              " in ", repo, "\n", last_line,
              "\nCheck for a stale .git/index.lock in the checkpoint.",
              call. = FALSE)
    }
  }
  if (is.na(head_before)) {
    res <- .cp_git(repo, c("update-ref", "-d", "refs/heads/main"))
    if (!res$ok) {
      last_line <- if (length(res$out)) {
        res$out[length(res$out)]
      } else {
        "git output unavailable"
      }
      warning("checkpoint rollback did not complete: remove main in ", repo,
              "\n", last_line,
              "\nCheck for a stale .git/index.lock in the checkpoint.",
              call. = FALSE)
    }
  } else {
    res <- .cp_git(repo, c("reset", "-q", "--hard", head_before))
    if (!res$ok) {
      last_line <- if (length(res$out)) {
        res$out[length(res$out)]
      } else {
        "git output unavailable"
      }
      warning("checkpoint rollback did not complete: reset main to ",
              head_before, " in ", repo, "\n", last_line,
              "\nCheck for a stale .git/index.lock in the checkpoint.",
              call. = FALSE)
    }
  }
  invisible(NULL)
}
