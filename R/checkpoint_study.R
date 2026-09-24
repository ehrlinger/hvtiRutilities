# The _study.yml keys a checkpoint needs. The key names are not settled (spec
# open item 1): read st_id, falling back to study_tracker_id, and treat an
# absent workspace_id as NULL. An absent identity_verified counts as verified,
# which is how every study written before PR #146 reads.

# An include pattern is matched against study-relative paths only, so one
# that is absolute or climbs out with ".." can only be a mistake. It is an
# error at validation rather than a silent skip (spec section 5).
.cp_check_include <- function(include, caller) {
  for (p in include) {
    absolute <- grepl("^(/|~|[A-Za-z]:)", p)
    climbs <- ".." %in% strsplit(p, "[/\\\\]")[[1]]
    if (absolute || climbs) {
      stop(caller, "(): checkpoint include pattern '", p, "' must be ",
           "relative to the study root and must not contain '..'",
           call. = FALSE)
    }
  }
  include
}

.cp_study <- function(root, caller) {
  yml <- file.path(root, "_study.yml")
  if (!file.exists(yml)) {
    stop(caller, "(): no _study.yml at ", root, "; run study_setup() first",
         call. = FALSE)
  }
  raw <- yaml::read_yaml(yml)
  st <- suppressWarnings(as.integer(.cp_or(raw$st_id, raw$study_tracker_id)))
  if (length(st) != 1L || is.na(st) || st < 1L) {
    stop(caller, "(): _study.yml has no valid st_id or study_tracker_id",
         call. = FALSE)
  }
  cp <- .cp_or(raw$checkpoint, list())
  list(
    root = root,
    st_id = st,
    workspace_id = raw$workspace_id,
    verified = !isFALSE(raw$identity_verified),
    remote = cp$remote,
    include = .cp_check_include(as.character(unlist(cp$include)), caller)
  )
}
