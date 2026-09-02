# Parsing a job filename into its prefix.
#
# Four naming conventions are live in the corpus at once, and they are not
# variations on one pattern -- see section 4.2 of
# dev/specs/2026-08-26-job-type-inventory-design.md. Each gets its own anchored
# regex, and the parsers run most-specific-first.
#
# The order is load-bearing, not stylistic. `legacy` is permissive enough to
# match almost any dotted name -- it reads "03.01-ac.qmd" as prefix "03" --
# so it must run last or it shadows the three R-side patterns and every R job
# in the corpus is misclassified. test-job-names.R pins this.

# One row per input basename, in input order. `naming` and `prefix` are NA for
# a name no parser claims; the row still exists, because a file this sweep
# cannot classify must remain findable rather than vanish.

# The legacy pattern captures the FIRST dot-field and, until 2026-09-02,
# discarded every field after it. That loses the part of the name carrying
# what the job actually does: `dp.trends`, `dp.gfup` and `dp.spaghetti.echo`
# all reduced to the single bucket "dp", and a bucket cannot be templated.
# `qualifier1`, `qualifiers` and `n_qualifiers` carry those fields through.
#
# They are named for their POSITION, not their meaning, and that is
# deliberate. A census over all 2,240,554 corpus rows on 2026-09-02 measured
# what the second field holds, and it is a different thing in each taxonomy
# folder: an outcome in `analyses` (hm.dead, 4,073 rows), a table type in
# `descriptive` (dc.tables 7,028, dc.general 6,161), a clinical VARIABLE in
# `distributions` (dp.afib 888, dp.pain_score 877) and a mix of plot types
# and variables in `graphs` (3,600 distinct values for dp alone). Calling the
# field "outcome" or "refinement" here would bake one folder's reading into
# every folder, which is the error this change exists to undo. Naming the
# fields is a separate, curated step that dispatches on `folder`; see
# hvtiRtemplates dev/specs/2026-09-02-per-folder-naming-parse-design.md.
.job_name_fields <- function(basenames) {
  n <- length(basenames)
  naming <- rep(NA_character_, n)
  prefix <- rep(NA_character_, n)

  # A leading `tp.` marks a template that is not meant to be run. Strip it
  # before any parser sees the name, so the real prefix is what gets matched.
  marked <- grepl("^tp[.]", basenames)
  stripped <- sub("^tp[.]", "", basenames)
  is_template <- marked

  patterns <- list(
    # <endpoint>-<type>-<NN>.<MM>-<prefix>[-parity].qmd
    set            = "^[A-Za-z0-9_]+-[A-Za-z0-9_]+-\\d{2}[.]\\d{2}-([A-Za-z0-9]+)(?:-parity)?[.]qmd$",
    # <NN>.<MM>-<prefix>.qmd
    template       = "^\\d{2}[.]\\d{2}-([A-Za-z0-9]+)[.]qmd$",
    # <NN>-<prefix>-<endpoint>[-parity].qmd
    r_transitional = "^\\d{2}-([A-Za-z0-9]+)-[A-Za-z0-9_]+(?:-parity)?[.]qmd$",
    # <prefix>.<anything>.<ext>
    legacy         = "^([A-Za-z0-9_]+)[.].+$"
  )

  for (nm in names(patterns)) {
    todo <- is.na(naming)
    if (!any(todo)) break
    hit <- todo & grepl(patterns[[nm]], stripped)
    if (!any(hit)) next
    naming[hit] <- nm
    prefix[hit] <- sub(patterns[[nm]], "\\1", stripped[hit])
  }

  # Only `legacy` has a qualifier slot. The other three conventions have a
  # fixed grammar in which every field is accounted for, so a qualifier there
  # would be an invention rather than a reading.
  quals <- rep(list(character(0)), n)
  leg <- !is.na(naming) & naming == "legacy"
  if (any(leg)) quals[leg] <- .legacy_qualifiers(stripped[leg])

  data.frame(
    naming = naming,
    prefix = prefix,
    is_template = is_template,
    qualifier1 = vapply(
      quals, function(q) if (length(q)) q[[1]] else NA_character_,
      character(1)
    ),
    qualifiers = vapply(
      quals,
      function(q) if (length(q)) paste(q, collapse = ".") else NA_character_,
      character(1)
    ),
    n_qualifiers = vapply(quals, length, integer(1)),
    stringsAsFactors = FALSE
  )
}

# The dot-fields of a legacy name between the prefix and the extension.
#
# The FIRST field is the prefix and the LAST is the extension, so a name with
# two fields (`hzdead.sas7bdat`) has no qualifier at all -- character(0), not
# "sas7bdat". Dropping the last field by position is what makes that true, and
# it is why this cannot be a `sub()` on the same regex that found the prefix:
# the extension separator and the field separator are the same character, so
# only counting from both ends tells them apart. `.template_fields()` in
# hvtiRtemplates reaches the same conclusion for the ordinal.
.legacy_qualifiers <- function(stripped) {
  lapply(strsplit(stripped, ".", fixed = TRUE), function(p) {
    if (length(p) < 3L) character(0) else p[-c(1L, length(p))]
  })
}
