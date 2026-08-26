# Attributing a file to a study, and saying how confidently.
#
# The study is the directory holding the taxonomy folder -- `distributions`,
# `analyses`, `graphs` and the rest. Files nest below those folders in the
# real corpus (preserve_root has ten hp.* files in graphs/Training/ and its R
# jobs two levels down in analyses/R_hazard/qmd/), so the walk finds the
# NEAREST taxonomy ancestor rather than assuming the file's own parent.
#
# Nothing is discarded. A file with no taxonomy folder anywhere above it gets
# status "unplaced" and keeps its row: a sweep that reports only what it kept
# makes a missing job indistinguishable from a job that does not exist, and
# that is exactly how shape-census.R under-reported twice.

.job_placement <- function(paths, root) {
  folders <- unique(hvti_taxonomy()$folder)

  # Strip the root prefix BY POSITION, not with a regex anchor. A root path is
  # arbitrary input -- a directory named "study (copy)" or "v1.2+" carries
  # regex metacharacters -- and an unescaped anchor matches the wrong thing
  # while still looking like it worked, because `.` and `-` match themselves.
  # normalizePath() on both sides so a symlinked root (/var -> /private/var on
  # macOS) does not make the prefix fail to line up.
  nroot <- normalizePath(root, mustWork = FALSE)
  npaths <- normalizePath(paths, mustWork = FALSE)
  rel <- substring(npaths, nchar(nroot) + 2L)

  parts <- strsplit(rel, "/", fixed = TRUE)

  out <- lapply(parts, function(p) {
    # Drop the basename: only directory components can be a taxonomy folder.
    dirs <- utils::head(p, -1L)
    hits <- which(dirs %in% folders)
    if (!length(hits)) {
      return(list(study = NA_character_, folder = NA_character_,
                  status = "unplaced", depth = NA_integer_))
    }
    i <- max(hits)                       # nearest to the file
    depth <- length(dirs) - i
    list(
      study  = if (i == 1L) "." else paste(dirs[seq_len(i - 1L)], collapse = "/"),
      folder = dirs[[i]],
      status = if (depth == 0L) "placed" else "nested",
      depth  = as.integer(depth)
    )
  })

  data.frame(
    study  = vapply(out, `[[`, character(1), "study"),
    folder = vapply(out, `[[`, character(1), "folder"),
    status = vapply(out, `[[`, character(1), "status"),
    depth  = vapply(out, `[[`, integer(1), "depth"),
    stringsAsFactors = FALSE
  )
}
