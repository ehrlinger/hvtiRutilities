## =============================================================================
## Internal: read a SAS source file tolerantly.
## Legacy CORR macros are Latin-1 / Windows-1252 encoded (Greek letters, micro
## signs, smart quotes in comments). Reading them in a UTF-8 session without an
## encoding leaves invalid multibyte sequences that later crash tolower()/grepl()
## with "invalid multibyte string". A latin1 connection maps every byte and
## marks the strings so downstream ASCII-range matching is safe.
.read_sas_lines <- function(file) {
  con <- file(file, open = "r", encoding = "latin1")
  on.exit(close(con))
  readLines(con, warn = FALSE)
}

## =============================================================================
## Internal: normalize a macro body prior to hashing.
## Case-folds and collapses all whitespace runs to a single space, so that
## cosmetic reformatting does not register as a semantic difference.
.normalize_body <- function(lines) {
  txt <- paste(lines, collapse = " ")
  txt <- tolower(txt)
  txt <- gsub("[[:space:]]+", " ", txt)
  trimws(txt)
}

## =============================================================================
## Internal: parse the parameter list from a %macro statement.
## "%macro foo(a, b=1, c);" -> "a,b,c"   |   "%macro foo;" -> ""
.parse_params <- function(stmt) {
  m <- regmatches(stmt, regexpr("\\(([^)]*)\\)", stmt))
  if (length(m) == 0L) {
    return("")
  }
  inner <- gsub("^\\(|\\)$", "", m)
  if (!nzchar(trimws(inner))) {
    return("")
  }
  parts <- strsplit(inner, ",", fixed = TRUE)[[1]]
  parts <- sub("=.*$", "", parts)
  paste(trimws(tolower(parts)), collapse = ",")
}

## =============================================================================
#' Extract every macro definition from a SAS file
#'
#' @description
#' Scans a `.sas` file and returns one row for each `%macro`...`%mend` pair it
#' contains. SAS files in the legacy CORR library are macro *collections*, not
#' single macros, so a file routinely defines several.
#'
#' @details
#' Matching is case-insensitive: SAS macro names are case-insensitive and the
#' legacy corpus mixes `%macro skip;` with `%MACRO MRG;` freely. Nested
#' definitions are handled by depth counting, so an inner `%mend` does not
#' terminate an outer macro.
#'
#' The body hash is a SHA-256 digest of the definition with case folded and
#' whitespace runs collapsed. Two definitions with the same hash are
#' semantically identical up to formatting.
#'
#' An unmatched `%macro` is an error, never a silently truncated body. A file
#' containing no `%macro` at all is likewise an error.
#'
#' @param file Character. Path to a `.sas` file.
#'
#' @return A \code{data.frame} with one row per macro definition and columns
#'   \code{file}, \code{macro}, \code{params}, \code{body_hash},
#'   \code{line_start}, and \code{line_end}. Macro and parameter names are
#'   lowercased.
#'
#' @export sas_macro_defs
#'
#' @examples
#' f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
#' if (nzchar(f)) sas_macro_defs(f)
#'
#' @importFrom digest digest
sas_macro_defs <- function(file) {
  if (!file.exists(file)) {
    stop("File does not exist: ", file, call. = FALSE)
  }

  lines <- .read_sas_lines(file)

  start_re <- "^[[:space:]]*%macro[[:space:]]+([a-z_][a-z0-9_]*)"
  mend_re <- "^[[:space:]]*%mend"

  lower <- tolower(lines)
  is_start <- grepl(start_re, lower)
  is_mend <- grepl(mend_re, lower)

  if (!any(is_start)) {
    stop("no %macro definition found in: ", basename(file), call. = FALSE)
  }

  open <- integer(0) # stack of open %macro line numbers
  defs <- list()

  for (i in seq_along(lines)) {
    if (is_start[i]) {
      open <- c(open, i)
    } else if (is_mend[i] && length(open) > 0L) {
      s <- open[length(open)]
      open <- open[-length(open)]

      stmt <- lower[s]
      name <- sub(paste0(start_re, ".*$"), "\\1", stmt)

      defs[[length(defs) + 1L]] <- data.frame(
        file       = basename(file),
        macro      = name,
        params     = .parse_params(stmt),
        body_hash  = digest::digest(
          .normalize_body(lines[s:i]),
          algo = "sha256", serialize = FALSE
        ),
        line_start = s,
        line_end   = i,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(open) > 0L) {
    s <- open[1L]
    name <- sub(paste0(start_re, ".*$"), "\\1", lower[s])
    stop(
      "unmatched '%macro ", name, "' at line ", s, " in ", basename(file),
      ". Refusing to hash a truncated body.",
      call. = FALSE
    )
  }

  out <- do.call(rbind, defs)
  out[order(out$line_start), , drop = FALSE]
}
