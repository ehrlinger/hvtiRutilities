## =============================================================================
## Internal: strip SAS comments before quote balancing.
## SAS comments take two forms: a statement starting with `*` and ending `;`,
## and /* ... */ blocks. Apostrophes inside comments are prose, not syntax.
##
## Block comments routinely span lines in this library -- the boxed `| Purpose :
## ... |` headers run for dozens of lines -- so they are tracked with a state
## flag rather than matched per line. Blanking in place preserves line numbering
## for the quote check's line report.
.strip_comments <- function(lines) {
  out <- character(length(lines))
  in_block <- FALSE

  for (i in seq_along(lines)) {
    s <- lines[i]
    kept <- ""
    repeat {
      if (in_block) {
        p <- regexpr("*/", s, fixed = TRUE)
        if (p == -1L) {
          break
        }
        s <- substring(s, p + 2L)
        in_block <- FALSE
      } else {
        p <- regexpr("/*", s, fixed = TRUE)
        if (p == -1L) {
          kept <- paste0(kept, s)
          break
        }
        kept <- paste0(kept, substring(s, 1L, p - 1L))
        s <- substring(s, p + 2L)
        in_block <- TRUE
      }
    }
    out[i] <- kept
  }

  out[grepl("^[[:space:]]*\\*", out)] <- ""
  out
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

  ## There is deliberately no do/end balance check. Textual balance is not a
  ## validity property of SAS macro source: `end` appears in the `end=` data set
  ## option, in PROC SQL `CASE ... END`, and in DATA step `SELECT ... END`, while
  ## `%do`-guarded blocks emit DO and END from separate branches so the source
  ## text need not balance even when every generated program does. Measured on
  ## the library, the check flagged 55 of 72 macro-bearing files it examined, and
  ## every refinement traded one class of false positive for another. The
  ## %macro/%mend check already catches the truncation this was meant to detect.

  list(valid = length(failures) == 0L, failures = failures)
}
