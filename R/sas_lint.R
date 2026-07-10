## =============================================================================
## Internal: strip SAS line comments before quote balancing.
## SAS comments take two forms: a statement starting with `*` and ending `;`,
## and /* ... */ blocks. Apostrophes inside comments are prose, not syntax.
.strip_comments <- function(lines) {
  lines <- gsub("/\\*.*?\\*/", "", lines)
  lines[grepl("^[[:space:]]*\\*", lines)] <- ""
  lines
}

## =============================================================================
## Internal: heuristic SAS validity check. Pure R, no SAS dependency.
##
## Returns list(valid = logical(1), failures = character()).
## Never throws: a broken file is data, and the caller records it as evidence.
.sas_lint <- function(file) {
  lines <- .read_sas_lines(file)
  lower <- tolower(lines)
  failures <- character(0)

  ## 1. At least one macro definition.
  n_macro <- sum(grepl("^[[:space:]]*%macro[[:space:]]+[a-z_]", lower))
  if (n_macro == 0L) {
    failures <- c(failures, "no %macro definition")
  }

  ## 2. %macro / %mend balance.
  n_mend <- sum(grepl("^[[:space:]]*%mend", lower))
  if (n_macro != n_mend) {
    failures <- c(
      failures,
      sprintf("%%macro/%%mend imbalance: %d open, %d close", n_macro, n_mend)
    )
  }

  ## 3. Single-quote balance, per line, comments removed.
  code <- .strip_comments(lines)
  odd <- which(vapply(
    gregexpr("'", code, fixed = TRUE),
    function(m) if (m[1L] == -1L) FALSE else (length(m) %% 2L == 1L),
    logical(1)
  ))
  if (length(odd) > 0L) {
    failures <- c(
      failures,
      sprintf("unbalanced quote at line(s): %s",
              paste(odd, collapse = ", "))
    )
  }

  ## 4. do / end balance across the file.
  n_do <- sum(vapply(
    gregexpr("\\bdo\\b", tolower(code)),
    function(m) if (m[1L] == -1L) 0L else length(m), integer(1)
  ))
  n_end <- sum(vapply(
    gregexpr("\\bend\\b", tolower(code)),
    function(m) if (m[1L] == -1L) 0L else length(m), integer(1)
  ))
  if (n_do != n_end) {
    failures <- c(
      failures,
      sprintf("do/end imbalance: %d do, %d end", n_do, n_end)
    )
  }

  list(valid = length(failures) == 0L, failures = failures)
}
