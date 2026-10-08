# Dataset shape: what kind of dataset a contract names, which columns make its
# rows unique, and, for a combined dataset, which registered datasets it was
# built from. Design: hvtiR dev/specs/2026-10-07-ancillary-datasets-design.md.

.study_kinds <- c("built", "subset", "ancillary", "combined")

.study_validate_shape <- function(contract, found, name, known, default) {
  bad <- function(what) {
    stop("study_config(): ", found, " ", what, " for dataset '", name, "'.", call. = FALSE)
  }
  kind <- contract$kind
  key <- contract$key
  parents <- contract$parents
  if (!is.null(kind)) {
    if (!(is.character(kind) && length(kind) == 1L && kind %in% .study_kinds)) {
      bad(paste0("has an invalid kind; expected one of ", toString(.study_kinds)))
    }
    if (default && !identical(kind, "built")) bad(paste0("has kind '", kind, "'; the study dataset is kind built"))
    if (!default && identical(kind, "built")) bad("has kind built, which only the study dataset may have")
  }
  if (!is.null(key) &&
        !(is.character(key) && length(key) >= 1L && !anyNA(key) && all(nzchar(key)) && !anyDuplicated(key))) {
    bad("has an invalid key; expected one or more distinct column names")
  }
  if (identical(kind, "combined")) {
    valid <- is.character(parents) && length(parents) >= 1L && !anyNA(parents) && !anyDuplicated(parents) &&
      all(parents %in% known) && !name %in% parents
    if (!valid) bad("needs parents naming other registered datasets")
  } else if (!is.null(parents)) {
    bad("has parents but is not kind combined")
  }
  invisible(TRUE)
}

.study_validate_shapes <- function(raw, found) {
  known <- c(if (!is.null(raw$built)) "study", names(raw$additional_datasets))
  .study_validate_shape(raw[c("kind", "key", "parents")], found, "study", known, default = TRUE)
  for (name in names(raw$additional_datasets)) {
    .study_validate_shape(raw$additional_datasets[[name]], found, name, known, default = FALSE)
  }
  .study_validate_no_cycle(raw, found)
  raw
}

# A dataset may not be, however indirectly, its own parent: the staleness walk
# recurses over parents. Names datasets, never values.
.study_validate_no_cycle <- function(raw, found) {
  edges <- lapply(raw$additional_datasets, function(x) x$parents)
  visit <- function(name, path) {
    if (name %in% path) {
      cycle <- c(path[match(name, path):length(path)], name)
      stop("study_config(): ", found, " has a cycle among dataset parents: ", paste(cycle, collapse = " -> "),
           ".", call. = FALSE)
    }
    for (p in edges[[name]]) visit(p, c(path, name))
  }
  for (name in names(edges)) visit(name, character())
  invisible(TRUE)
}

# Names are matched ignoring case, because read_built() lowercases them.
.check_registration_key <- function(d, key, file, caller) {
  if (is.null(key)) return(invisible(TRUE))
  hit <- match(tolower(key), tolower(names(d)))
  if (anyNA(hit)) {
    stop(caller, "(): key names a column ", file, " does not have: ", toString(key[is.na(hit)]),
         ". Nothing was written.", call. = FALSE)
  }
  repeats <- sum(duplicated(d[names(d)[hit]]))
  if (repeats) {
    stop(caller, "(): ", repeats, if (repeats == 1L) " row repeats" else " rows repeat",
         " a value of the key (", toString(key), ") in ", file,
         ". Each row must be unique on the key; add a column to it, such as a date. Nothing was written.",
         call. = FALSE)
  }
  invisible(TRUE)
}

# A registered dataset's version: its dated parquet (design 2), its pinned
# release, or, for an unconverted registration, its checksum.
.dataset_version <- function(cfg, name, manifest) {
  contract <- .study_dataset(cfg, name)
  if (!is.null(contract$release)) return(contract$release$release_id)
  hit <- Filter(function(e) identical(e$file, contract$built), manifest$datasets)
  if (!length(hit)) return(NA_character_)
  if (.is_versioned(hit[[1L]])) hit[[1L]]$parquet else hit[[1L]]$sha256
}

.parent_versions <- function(cfg, parents, manifest) {
  stats::setNames(lapply(parents, function(p) .dataset_version(cfg, p, manifest)), parents)
}

# Order datasets so each comes after every parent it was combined from (a
# post-order walk over parents; study_config() has already refused a cycle).
# A parent outside `targets` is not added: it is not being updated.
.parents_first <- function(cfg, targets) {
  visit <- function(out, name) {
    if (name %in% out) return(out)
    for (p in .study_dataset(cfg, name)$parents) if (p %in% targets) out <- visit(out, p)
    c(out, name)
  }
  Reduce(visit, targets, character())
}

# A parent registered before dated versions is recorded by its source's
# checksum. Migrating it unchanged converts that same source, so its current
# version, whose source_sha256 is the recorded checksum, holds the same data.
.migrated_unchanged <- function(cfg, name, manifest, recorded) {
  built <- .study_dataset(cfg, name)$built
  hit <- Filter(function(e) identical(e$file, built), manifest$datasets)
  length(hit) > 0L && .is_versioned(hit[[1L]]) && identical(hit[[1L]]$source_sha256, recorded)
}

# The parents of a combined dataset whose version now differs from the one
# recorded in its manifest entry. A parent recorded or found without a version
# (NA), or an entry that records no parent versions at all, is never current:
# it reads as "unrecorded", so update_manifest() has something to clear.
.stale_parents <- function(cfg, name, entry, manifest) {
  contract <- .study_dataset(cfg, name)
  empty <- data.frame(parent = character(), recorded = character(), current = character())
  if (!identical(contract$kind, "combined")) return(empty)
  rows <- lapply(contract$parents, function(p) {
    recorded <- as.character(entry$parent_versions[[p]] %||% NA_character_)
    current <- as.character(.dataset_version(cfg, p, manifest))
    if (!is.na(recorded) && !is.na(current) &&
          (identical(recorded, current) || .migrated_unchanged(cfg, p, manifest, recorded))) {
      return(NULL)
    }
    data.frame(parent = p, recorded = if (is.na(recorded)) "unrecorded" else recorded,
               current = if (is.na(current)) "unregistered" else current)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) empty else do.call(rbind, rows)
}

# The words for one context, built from parts so each reads naturally:
# "read" is a job that has just used the older data, "status" an audit line,
# "update" a line in update_manifest()'s report. Each ends with the fix, which
# for a release-aware dataset is the release commands rather than update_manifest().
.parent_changed_text <- function(contract, stale, context = c("read", "status", "update")) {
  context <- match.arg(context)
  was <- paste0(stale$parent, " was ", stale$recorded, " and is now ", stale$current, collapse = "; ")
  # update_manifest() skips a release-aware dataset: its versions come from adopted releases.
  fix <- if (is.null(contract$release)) {
    paste0("rebuild ", contract$built, " with the job or script that writes it, then run ",
           "hvtiRutilities::update_manifest().")
  } else {
    paste0("publish a release rebuilt from the current parents, then review and adopt it with ",
           "hvtiRutilities::review_data_update() and hvtiRutilities::adopt_data_update().")
  }
  switch(context,
    read = paste0(contract$dataset, " (", contract$built, ") was built from older versions of its parents: ", was,
                  ". This job used the older combined data. To update it, ", fix),
    status = paste0("built from older versions of its parents: ", was, ". To update it, ", fix),
    update = paste0(contract$dataset, " is out of date (", contract$built, "): built from older versions of its ",
                    "parents: ", was, ". To update it, ", fix)
  )
}

.parent_changed_condition <- function(contract, stale) {
  structure(
    class = c("hvtiRutilities_parent_changed", "hvtiRutilities_out_of_date", "message", "condition"),
    list(message = paste0(.parent_changed_text(contract, stale, "read"), "\n"), call = NULL)
  )
}
