# Provenance of a registered version: how its data were produced. Design:
# dev/specs/2026-10-13-one-version-scheme-design.md, section 4.
#
# Kept in a top-level `provenance:` map keyed by parquet name, never on the
# version record. hvtiRutilities 1.5.1 and 1.5.2 copy every field they do not
# know onto the next version they write, so an origin on the entry would be
# inherited by a later rebuild; they rewrite only `datasets:` and keep other
# top-level keys, so a version they register has no row and reads as legacy.

.legacy_row <- function() list(origin = "legacy")

.version_provenance <- function(manifest, parquet) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  row <- rows[[parquet]]
  if (is.list(row) && is.character(row$origin) && length(row$origin) == 1L) row else .legacy_row()
}

.set_version_provenance <- function(manifest, parquet, row) {
  rows <- if (is.list(manifest$provenance)) manifest$provenance else list()
  rows[[parquet]] <- row
  manifest$provenance <- rows
  manifest
}
