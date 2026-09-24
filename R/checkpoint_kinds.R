# The checkpoint vocabulary. The package ships the StudyTracker Workspace
# API's initial rows; qhsprograms caches the live, administrator-owned table
# in .checkpoint/kinds.yml, and a live row replaces a base row of the same
# kind. There are no study-level kinds: extension happens in the ST table.

.cp_kinds <- function(root) {
  base <- yaml::read_yaml(system.file("checkpoint-kinds.yml",
                                      package = "hvtiRutilities",
                                      mustWork = TRUE))
  live_path <- file.path(root, ".checkpoint", "kinds.yml")
  live <- if (file.exists(live_path)) yaml::read_yaml(live_path) else list()
  rows <- c(base, .cp_or(live, list()))
  ids <- vapply(rows, function(r) as.character(r$kind), character(1))
  rows <- rows[!duplicated(ids, fromLast = TRUE)]
  data.frame(
    kind = vapply(rows, function(r) as.character(r$kind), character(1)),
    trigger = vapply(rows, function(r) as.character(.cp_or(r$trigger, "manual")),
                     character(1)),
    numbered = vapply(rows, function(r) !isFALSE(r$numbered), logical(1)),
    retired = vapply(rows, function(r) isTRUE(r$retired), logical(1)),
    stringsAsFactors = FALSE
  )
}

.cp_kind_check <- function(kinds, kind, caller) {
  if (length(kind) != 1L || is.na(kind) || !kind %in% kinds$kind) {
    stop(caller, "(): unknown checkpoint kind '", paste(kind, collapse = ", "),
         "'. Valid kinds: ",
         paste(kinds$kind[!kinds$retired], collapse = ", "),
         call. = FALSE)
  }
  row <- kinds[kinds$kind == kind, , drop = FALSE]
  if (row$retired) {
    stop(caller, "(): checkpoint kind '", kind, "' is retired and cannot ",
         "be used for a new checkpoint", call. = FALSE)
  }
  row
}
