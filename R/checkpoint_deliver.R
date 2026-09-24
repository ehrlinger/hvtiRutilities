# Delivery: replicate local checkpoints to the remote. Nothing here undoes a
# local checkpoint. When another copy of the study pushed first, unpushed
# snapshots are replayed on top of the remote main with git commit-tree: a
# snapshot's content never depends on its parent, so a replay cannot
# conflict. A pushed tag is never moved and nothing is ever force-pushed.

.cp_last <- function(out) if (length(out)) out[length(out)] else "no output"

.cp_replay <- function(repo) {
  if (.cp_git(repo, c("merge-base", "--is-ancestor",
                      "refs/remotes/origin/main", "HEAD"))$ok) {
    return(character(0))
  }
  commits <- .cp_git_do(repo, c("rev-list", "--reverse", "HEAD",
                                "^refs/remotes/origin/main"))
  base <- .cp_git_do(repo, c("rev-parse", "refs/remotes/origin/main"))[1]
  map <- character(0)
  for (old in commits) {
    tree <- .cp_git_do(repo, c("rev-parse", paste0(old, "^{tree}")))[1]
    msg <- .cp_message_file(.cp_git_do(repo, c("log", "-1", "--format=%B", old)))
    new <- .cp_git_do(repo, c("commit-tree", tree, "-p", base, "-F", msg))[1]
    unlink(msg)
    map[[old]] <- new
    base <- new
  }
  .cp_git_do(repo, c("reset", "-q", "--hard", base))
  map
}

.cp_remote_tags <- function(repo) {
  .cp_git_do(repo, c("for-each-ref", "--format=%(refname:strip=2)",
                     "refs/remote-tags"))
}

.cp_renumber <- function(repo, tag) {
  prefix <- sub("-[0-9]+$", "", tag)
  family <- if (startsWith(tag, "closed-")) "closed-[a-z_]+" else prefix
  all <- c(.cp_git_do(repo, c("tag", "-l")), .cp_remote_tags(repo))
  seqs <- .cp_seq_of(all[grepl(paste0("^", family, "-[0-9]+$"), all)])
  paste0(prefix, "-", max(c(0L, seqs)) + 1L)
}

# Move an unpushed tag to its replayed commit, recording the old commit as
# replayed_from, and renumber it when the remote already holds the same name
# on a different commit.
.cp_retarget <- function(entry, repo, map) {
  if (is.null(entry$tag)) return(entry)
  old <- entry$git_commit
  new <- if (!is.null(old) && old %in% names(map)) map[[old]] else old
  remote <- .cp_commit_of(repo, paste0("refs/remote-tags/", entry$tag))
  collides <- !is.na(remote) && !identical(remote, new)
  if (!collides && identical(new, old)) return(entry)
  msg <- .cp_message_file(.cp_git_do(repo, c("tag", "-l", "--format=%(contents)",
                                             entry$tag)))
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("tag", "-d", entry$tag))
  if (collides) {
    entry$renumbered_from <- entry$tag
    entry$tag <- .cp_renumber(repo, entry$tag)
  }
  .cp_git_do(repo, c("tag", "-a", entry$tag, "-F", msg, new))
  if (!identical(new, old)) {
    entry$replayed_from <- old
    entry$git_commit <- new
  }
  entry
}

.cp_push <- function(repo, entries) {
  probe <- .cp_remote_probe(repo)
  if (!probe$reachable) {
    return(list(reason = paste("remote unreachable:", .cp_last(probe$out))))
  }
  refspecs <- "+refs/tags/*:refs/remote-tags/*"
  if (probe$has_main) {
    refspecs <- c("+refs/heads/main:refs/remotes/origin/main", refspecs)
  }
  .cp_git_do(repo, c("fetch", "-q", "origin", refspecs))
  map <- if (probe$has_main) .cp_replay(repo) else character(0)
  entries <- lapply(entries, .cp_retarget, repo = repo, map = map)
  res <- .cp_git(repo, c("push", "-q", "origin", "refs/heads/main:refs/heads/main"))
  if (!res$ok) return(list(reason = paste("push rejected:", .cp_last(res$out))))
  tags <- unique(unlist(lapply(entries, function(e) e$tag)))
  tags <- tags[vapply(tags, function(t) {
    !identical(.cp_commit_of(repo, paste0("refs/remote-tags/", t)),
               .cp_commit_of(repo, t))
  }, logical(1))]
  if (length(tags)) {
    res <- .cp_git(repo, c("push", "-q", "origin", paste0("refs/tags/", tags)))
    if (!res$ok) {
      return(list(reason = paste("tag push rejected:", .cp_last(res$out))))
    }
  }
  list(reason = NULL, entries = entries)
}

# Deliver every committed entry whose git delivery is pending. Committing and
# abandoned entries are never pushed; .cp_reconcile() settles the first kind
# before any delivery runs. An unverified identity is never pushed (the
# manual-identity rule); no remote is a normal state for a study that has not
# been given one yet.
.cp_deliver <- function(root, study) {
  log <- .cp_log_read(root)
  pending <- which(vapply(log, function(e) {
    identical(e$state, "committed") && identical(e$delivery$git, "pending")
  }, logical(1)))
  if (!length(pending)) return(invisible(log))
  reason <- if (!study$verified) {
    "identity unverified"
  } else if (is.null(study$remote)) {
    "no remote configured"
  } else {
    NULL
  }
  if (is.null(reason)) {
    pushed <- .cp_push(.cp_repo_init(root, study$remote), log[pending])
    reason <- pushed$reason
    if (is.null(reason)) log[pending] <- pushed$entries
  }
  for (i in pending) {
    if (is.null(reason)) log[[i]]$delivery$git <- "delivered"
    log[[i]]$delivery$reason <- reason
  }
  .cp_log_write(root, log)
  if (identical(reason, "identity unverified")) {
    message(length(pending), " checkpoint(s) saved locally and not pushed: ",
            "identity unverified. Run study-setup --verify, then ",
            "study_checkpoint_push().")
  } else if (!is.null(reason) && reason != "no remote configured") {
    warning(length(pending), " checkpoint(s) saved locally, not pushed: ",
            reason, ". Run study_checkpoint_push() to retry.", call. = FALSE)
  }
  invisible(log)
}

.cp_log_frame <- function(log) {
  pick <- function(f) {
    vapply(log, function(e) as.character(.cp_or(f(e), NA)), character(1))
  }
  data.frame(type = pick(function(e) e$type), tag = pick(function(e) e$tag),
             state = pick(function(e) e$state),
             git = pick(function(e) e$delivery$git),
             st = pick(function(e) e$delivery$st),
             reason = pick(function(e) e$delivery$reason),
             stringsAsFactors = FALSE)
}
