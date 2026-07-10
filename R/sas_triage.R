## =============================================================================
## Internal: known variant markers observed in the legacy corpus.
## Ordered longest-first so that `_test_at` strips before `_test`.
.VARIANT_SUFFIXES <- c(
  "_test_at", "_testma", "_test", "_old", "_new", "_orig",
  "_wt", "_at", "_b", "ma"
)

## =============================================================================
## Internal: strip one trailing variant marker from a lowercased stem.
.strip_variant_suffix <- function(stem) {
  for (sfx in .VARIANT_SUFFIXES) {
    if (grepl(paste0(sfx, "$"), stem) && nchar(stem) > nchar(sfx)) {
      return(sub(paste0(sfx, "$"), "", stem))
    }
  }
  stem
}

## =============================================================================
## Internal: classify a macro definition as a public entry point or a private
## inline helper. Advisory only -- never used to drop a definition.
.classify_visibility <- function(macro, file) {
  stem <- tolower(sub("\\.sas~?$", "", basename(file), ignore.case = TRUE))
  macro <- tolower(macro)

  if (identical(stem, macro)) {
    return("public")
  }
  if (identical(.strip_variant_suffix(stem), macro)) {
    return("public?")
  }
  "private"
}
