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
