## =============================================================================
## Internal: scan SAS source, returning the code with comments, string literals
## and macro-quoted characters removed.
##
## Counting quotes with a per-line pattern cannot work on this library. Six
## distinct constructs defeat it, each of which is ordinary SAS:
##
##   /* ... */ spanning lines        boxed `| Purpose : |` headers
##   * ... ;   spanning lines        gmatch.sas's eight-line header
##   * ... ;   mid-line              `data y; run; * transform X's here;`
##   '...' spanning lines            `title '... by` / `&&group' ;`
##   '  inside "..."                 `put "WARN''ING: ... didn't ...";`
##   %STR(%')                        SAS/IML transpose, deliberately unbalanced
##
## Patching one construct at a time kept trading one class of false positive for
## another, so the state is tracked explicitly instead. Newlines are always
## retained, so line numbering survives for the failure report.
##
## Returns list(code, open_state, open_line): `code` has one element per input
## line; `open_state` is the state at end of input, and `open_line` the line
## where an unterminated literal began.
.sas_scan <- function(lines) {
  if (length(lines) == 0L) {
    return(list(code = character(0), open_state = "code",
                open_line = NA_integer_))
  }

  ch <- strsplit(paste(lines, collapse = "\n"), "", fixed = TRUE)[[1]]
  m <- length(ch)
  keep <- logical(m)

  state <- "code"
  open_line <- NA_integer_
  line <- 1L
  ## TRUE when the next significant character would begin a statement, which is
  ## the only position where `*` opens a comment rather than multiplying.
  stmt_start <- TRUE
  i <- 1L

  while (i <= m) {
    c1 <- ch[i]
    c2 <- if (i < m) ch[i + 1L] else ""

    if (c1 == "\n") {
      keep[i] <- TRUE
      line <- line + 1L
      i <- i + 1L
      next
    }

    if (state == "code") {
      if (c1 == "%" && (c2 == "'" || c2 == "\"")) {
        i <- i + 2L                      # macro-quoted char, never a delimiter
      } else if (c1 == "/" && c2 == "*") {
        state <- "block"
        i <- i + 2L
      } else if (c1 == "*" && stmt_start) {
        state <- "star"
        i <- i + 1L
      } else if (c1 == "'") {
        state <- "squote"
        open_line <- line
        i <- i + 1L
      } else if (c1 == "\"") {
        state <- "dquote"
        open_line <- line
        i <- i + 1L
      } else {
        keep[i] <- TRUE
        if (!grepl("[[:space:]]", c1)) {
          stmt_start <- (c1 == ";")
        }
        i <- i + 1L
      }
    } else if (state == "block") {
      if (c1 == "*" && c2 == "/") {
        state <- "code"
        i <- i + 2L
      } else {
        i <- i + 1L
      }
    } else if (state == "star") {
      if (c1 == ";") {
        state <- "code"
        keep[i] <- TRUE                  # keep the terminator as a separator
        stmt_start <- TRUE
      }
      i <- i + 1L
    } else {                             # squote or dquote
      q <- if (state == "squote") "'" else "\""
      if (c1 == q && c2 == q) {
        i <- i + 2L                      # doubled quote escapes itself
      } else if (c1 == q) {
        state <- "code"
        open_line <- NA_integer_
        stmt_start <- FALSE
        i <- i + 1L
      } else {
        i <- i + 1L
      }
    }
  }

  code <- strsplit(paste(ch[keep], collapse = ""), "\n", fixed = TRUE)[[1]]
  length(code) <- length(lines)          # pad if trailing lines were all noise
  code[is.na(code)] <- ""

  list(code = code, open_state = state, open_line = open_line)
}

## =============================================================================
## Internal: strip SAS comments and literals, keeping one element per line.
## Retained as the scanner's code output for callers that only need the text.
## SAS comments take two forms: a statement starting with `*` and ending `;`,
## and /* ... */ blocks, and literals in '...' or "...". All are removed by
## .sas_scan(); this is the text-only view of its result.
.strip_comments <- function(lines) {
  .sas_scan(lines)$code
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

  ## 3. Every string literal is terminated.
  ##
  ## Per-line quote counting is not a validity test: literals legally span lines,
  ## and quotes appear inside comments, inside the other quote character, and
  ## macro-quoted as %'. The scanner tracks that context, so the only thing left
  ## to check is whether the file ends inside a literal.
  scan <- .sas_scan(lines)
  if (scan$open_state %in% c("squote", "dquote")) {
    failures <- c(
      failures,
      sprintf("unterminated string literal opened at line %d", scan$open_line)
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
