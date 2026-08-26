# Parsing a job filename into its prefix.
#
# Four naming conventions are live in the corpus at once, and they are not
# variations on one pattern -- see
# specs/2026-08-26-job-type-inventory-design.md section 4.2. Each gets its own
# anchored regex, and the parsers run most-specific-first.
#
# The order is load-bearing, not stylistic. `legacy` is permissive enough to
# match almost any dotted name -- it reads "03.01-ac.qmd" as prefix "03" --
# so it must run last or it shadows the three R-side patterns and every R job
# in the corpus is misclassified. test-job-names.R pins this.

# One row per input basename, in input order. `naming` and `prefix` are NA for
# a name no parser claims; the row still exists, because a file this sweep
# cannot classify must remain findable rather than vanish.
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

  data.frame(
    naming = naming,
    prefix = prefix,
    is_template = is_template,
    stringsAsFactors = FALSE
  )
}
