# The four shapes a _study.yml identity can take (spec 2026-11-09). An
# exploration of a registered study has derived_from (the parent's Study
# Tracker ID) and provisional_id but no study_tracker_id until
# study_promote() writes one; a promoted one keeps derived_from as lineage.
# A file with none of the three keys is legacy and keeps today's handling.
.study_identity_state <- function(raw) {
  has <- function(k) !is.null(raw[[k]])
  if (!has("derived_from") && !has("provisional_id")) {
    return(if (has("study_tracker_id")) "registered" else "legacy")
  }
  if (!has("derived_from") || !.study_whole_id(raw$derived_from)) {
    return(NA_character_)
  }
  if (has("provisional_id") && !has("study_tracker_id")) {
    id <- raw$provisional_id
    ok <- is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
    return(if (ok) "provisional" else NA_character_)
  }
  if (!has("provisional_id") && has("study_tracker_id")) return("promoted")
  NA_character_
}

# Written once by study_setup(); never recomputed from workspace_id later.
.study_provisional_id <- function(parent, workspace_id) {
  paste0("x", parent, "-", substr(workspace_id, 1L, 8L))
}

# One positive whole number, as an integer. .study_whole_id() is checked
# before coercion, which would truncate 4.2 to 4. A length-one string passes
# only when it is the canonical form of an integer ("42", not "042" or "4.2"),
# as study_setup() has always accepted from CLI callers.
.study_check_id <- function(x, name, caller) {
  if (is.character(x) && length(x) == 1L) {
    n <- suppressWarnings(as.integer(x))
    if (!is.na(n) && n >= 1L && identical(as.character(n), x)) {
      return(n)
    }
  } else if (.study_whole_id(x) && x <= .Machine$integer.max) {
    return(as.integer(x))
  }
  stop(caller, "(): ", name, " must be one positive integer", call. = FALSE)
}
