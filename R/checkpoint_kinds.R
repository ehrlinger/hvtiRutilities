# The checkpoint vocabulary. The package ships the StudyTracker Workspace
# API's initial rows; qhsprograms caches the live, administrator-owned table
# in .checkpoint/kinds.yml. A live row overrides only the fields it names and
# the base row of the same kind supplies the rest; a live kind with no base
# row takes the defaults (manual, numbered, not retired). There are no
# study-level kinds: extension happens in the ST table.

.cp_kinds <- function(root) {
  base <- yaml::read_yaml(system.file("checkpoint-kinds.yml",
                                      package = "hvtiRutilities",
                                      mustWork = TRUE))
  live_path <- file.path(root, ".checkpoint", "kinds.yml")
  live <- if (file.exists(live_path)) yaml::read_yaml(live_path) else list()
  rows <- list()
  for (r in c(base, .cp_or(live, list()))) {
    # modifyList() deletes a key whose new value is NULL; dropping the NULLs
    # first makes a null field mean "not named" rather than "unset".
    r <- Filter(Negate(is.null), r)
    k <- as.character(r$kind)
    rows[[k]] <- if (is.null(rows[[k]])) r else utils::modifyList(rows[[k]], r)
  }
  rows <- unname(rows)
  data.frame(
    kind = vapply(rows, function(r) as.character(r$kind), character(1)),
    # A non-scalar trigger is kept as written, pasted, so .cp_kind_check()
    # can name it rather than vapply failing on its length.
    trigger = vapply(rows, function(r) paste(as.character(.cp_or(r$trigger, "manual")),
                                             collapse = ", "),
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
  # Anything but "manual" used to read as automatic, so a live row saying
  # trigger: Manual recorded the milestone with no commit and no tag. Checked
  # on the kind in use only, so one bad row in the administrator-owned table
  # does not stop every other kind.
  if (!row$trigger %in% c("manual", "auto")) {
    stop(caller, "(): checkpoint kind '", kind, "' has trigger \"", row$trigger,
         "\" in the live kinds table; it must be \"manual\" or \"auto\"",
         call. = FALSE)
  }
  if (row$retired) {
    stop(caller, "(): checkpoint kind '", kind, "' is retired and cannot ",
         "be used for a new checkpoint", call. = FALSE)
  }
  row
}
