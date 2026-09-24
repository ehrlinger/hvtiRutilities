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

# Point an entry at its replayed commit, recording the old one as
# replayed_from. Pure, so it cannot fail between moving main and recording it.
.cp_apply_map <- function(entry, map) {
  old <- entry$git_commit
  if (is.null(old) || !old %in% names(map)) return(entry)
  entry$replayed_from <- old
  entry$git_commit <- map[[old]]
  entry
}

# TRUE when the remote holds the entry's tag on a different commit. A
# closure number is shared by every outcome (spec 6.2), so a closed-* tag
# also collides with any other remote closed-* tag carrying its number.
.cp_collides <- function(repo, entry) {
  remote <- .cp_commit_of(repo, paste0("refs/remote-tags/", entry$tag))
  if (!is.na(remote) && !identical(remote, entry$git_commit)) return(TRUE)
  if (!grepl("^closed-[a-z_]+-[0-9]+$", entry$tag)) return(FALSE)
  others <- .cp_remote_tags(repo)
  others <- others[grepl("^closed-[a-z_]+-[0-9]+$", others) &
                     others != entry$tag]
  any(.cp_seq_of(others) == .cp_seq_of(entry$tag))
}

# The entry as it should be once its local tag matches the log: renumbered
# when it collides with a remote tag. NULL when the local tag already names
# the entry's commit and nothing collides.
.cp_retag_plan <- function(entry, repo) {
  if (is.null(entry$tag) || is.null(entry$git_commit)) return(NULL)
  collides <- .cp_collides(repo, entry)
  local <- .cp_commit_of(repo, paste0("refs/tags/", entry$tag))
  if (!collides && identical(local, entry$git_commit)) return(NULL)
  if (collides) {
    entry$renumbered_from <- entry$tag
    entry$tag <- .cp_renumber(repo, entry$tag)
  }
  entry
}

# Replace the local tag `old_tag` with the entry's tag on the entry's commit,
# with a message regenerated from the entry so a renumbered tag names itself.
.cp_retag <- function(repo, old_tag, entry) {
  if (!is.na(.cp_commit_of(repo, paste0("refs/tags/", old_tag)))) {
    .cp_git_do(repo, c("tag", "-d", old_tag))
  }
  msg <- .cp_message_file(.cp_tag_message(entry))
  on.exit(unlink(msg), add = TRUE)
  .cp_git_do(repo, c("tag", "-a", entry$tag, "-F", msg, entry$git_commit))
}

# TRUE unless the entry names a commit that main does not contain: a tag on
# such a commit would carry an orphan to the remote.
.cp_on_main <- function(repo, entry) {
  if (is.null(entry$tag) || is.null(entry$git_commit)) return(TRUE)
  .cp_git(repo, c("merge-base", "--is-ancestor", entry$git_commit, "HEAD"))$ok
}

# Returns the entries as they stand against the local refs on success AND on
# failure, so the log never names a tag or commit the clone has moved away
# from. Every failure after the probe becomes a reason, never an error: the
# checkpoint is already saved locally. `persist` writes the entries to the
# log after the local ref moves and before the network push, so an
# interrupted push cannot lose them.
.cp_push <- function(repo, entries, persist) {
  probe <- .cp_remote_probe(repo)
  if (!probe$reachable) {
    return(list(reason = paste("remote unreachable:", .cp_last(probe$out)),
                entries = entries))
  }
  refspecs <- "+refs/tags/*:refs/remote-tags/*"
  if (probe$has_main) {
    refspecs <- c("+refs/heads/main:refs/remotes/origin/main", refspecs)
  }
  reason <- tryCatch({
    .cp_git_do(repo, c("fetch", "-q", "--no-tags", "origin", refspecs))
    map <- if (probe$has_main) .cp_replay(repo) else character(0)
    entries <- lapply(entries, .cp_apply_map, map = map)
    orphan <- NULL
    for (i in seq_along(entries)) {
      if (!.cp_on_main(repo, entries[[i]])) {
        orphan <- entries[[i]]
        break
      }
      planned <- .cp_retag_plan(entries[[i]], repo)
      if (is.null(planned)) next
      old_tag <- entries[[i]]$tag
      entries[[i]] <- planned
      .cp_retag(repo, old_tag, planned)
    }
    persist(entries)
    if (is.null(orphan)) {
      .cp_push_refs(repo, entries)
    } else {
      paste0("commit ", orphan$git_commit, " of ", orphan$tag,
             " is not on main")
    }
  }, error = function(e) conditionMessage(e))
  list(reason = reason, entries = entries)
}

.cp_push_refs <- function(repo, entries) {
  res <- .cp_git(repo, c("push", "-q", "origin", "refs/heads/main:refs/heads/main"))
  if (!res$ok) return(paste("push rejected:", .cp_last(res$out)))
  tags <- unique(unlist(lapply(entries, function(e) e$tag)))
  tags <- tags[vapply(tags, function(t) {
    !identical(.cp_commit_of(repo, paste0("refs/remote-tags/", t)),
               .cp_commit_of(repo, paste0("refs/tags/", t)))
  }, logical(1))]
  if (length(tags)) {
    res <- .cp_git(repo, c("push", "-q", "origin", paste0("refs/tags/", tags)))
    if (!res$ok) return(paste("tag push rejected:", .cp_last(res$out)))
  }
  NULL
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
    persist <- function(entries) {
      log[pending] <- entries
      .cp_log_write(root, log)
    }
    pushed <- tryCatch(.cp_push(.cp_repo_init(root, study$remote), log[pending],
                                persist),
                       error = function(e) {
                         list(reason = conditionMessage(e), entries = log[pending])
                       })
    reason <- pushed$reason
    log[pending] <- pushed$entries
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
    tags <- unlist(lapply(log[pending], function(e) e$tag))
    warning(length(pending), " checkpoint(s) saved locally, not pushed (",
            paste(tags, collapse = ", "), "): ", reason,
            ". Run study_checkpoint_push() to retry.", call. = FALSE)
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
