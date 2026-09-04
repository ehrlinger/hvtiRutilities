## =============================================================================
## Internal: the leading-code prefix rule.
## See dev/specs/2026-09-02-label-length-and-fallback-design.md section 6.1.

## A leading integer, then a separator, then optional whitespace. The
## separator is required: a bare digit-then-space rule matches "1 vessel
## disease", "2 vessel" and "3 vessel" and collapses three distinct levels
## into two identical strings.
.level_prefix_re <- "^[0-9]+[[:space:]]*[.:=)-][[:space:]]*"

## =============================================================================
#' Strip a leading code prefix from level text
#'
#' @description
#' Removes a leading integer code and its separator from the text of a
#' variable's levels, so \code{"1. Yes"} prints as \code{"Yes"}. It is a
#' display helper: it returns new text and \strong{never} rewrites the levels
#' of the object it was given.
#'
#' @details
#' \strong{A separator is required.} A leading integer is removed only when
#' one of \code{.} \code{:} \code{=} \code{)} \code{-} follows it, with
#' optional whitespace either side. A bare digit followed by a space is left
#' alone.
#'
#' That restraint is the point. A rule general enough to turn \code{"0 No"}
#' into \code{"No"} also turns \code{"1 vessel disease"}, \code{"2 vessel"} and
#' \code{"3 vessel"} into \code{"vessel disease"}, \code{"vessel"} and
#' \code{"vessel"} - three distinct levels becoming two identical strings.
#' Nothing errors; a downstream \code{table()} or model merges them and the
#' level count silently stops matching the data dictionary. The failure
#' presents as data rather than as a bug.
#'
#' So the rule is biased: \strong{a missed strip is visible in the output and
#' fixable by declaring the level text in \code{value_labels.yml} (see
#' \code{\link{apply_value_labels}}); a wrong strip is silent and corrupts the
#' level set.} Two consequences follow.
#' \itemize{
#'   \item Unpunctuated \code{"0 No"} and \code{"1 Yes"} are \strong{not}
#'     stripped and still print with their prefix.
#'   \item Text whose remainder begins with a digit is not stripped either,
#'     because \code{"1-2 vessels"} matches leading-integer-then-hyphen and
#'     would otherwise become \code{"2 vessels"}, colliding with a real
#'     \code{"2 vessels"} level. Ranges are ordinary in this domain.
#' }
#'
#' \strong{Collisions revert rather than merge.} If stripping would make two
#' entries identical - two codes carrying the same text, or a stripped entry
#' landing on one that was already bare - every entry involved keeps its
#' original text and a warning names the text they collided on. The level set
#' is preserved whatever the input, which is the guarantee this function is
#' worth having for.
#'
#' Stripping never produces an empty string: \code{"1."} is returned unchanged.
#'
#' @param x A character vector of level text, or a factor. Given a factor, the
#'   function reads \code{levels(x)} and returns one element per level - it
#'   does not return one element per observation, and it does not modify
#'   \code{x}.
#'
#' @return A character vector of display text: one element per input element,
#'   or one per level when \code{x} is a factor. \code{NA} is returned as
#'   \code{NA}.
#'
#' @seealso \code{\link{level_map}} to see what stripping would do across a
#'   dataset, \code{\link{apply_value_labels}} for declaring level text
#'   outright rather than tidying it afterwards.
#'
#' @export
#'
#' @examples
#' strip_level_prefix(c("1. Yes", "0 = No", "01 - home"))
#'
#' # A separator is required, so these survive intact
#' strip_level_prefix(c("1 vessel disease", "2 vessel", "3 vessel"))
#'
#' # And so does a range, whose remainder begins with a digit
#' strip_level_prefix("1-2 vessels")
#'
#' # A factor is read through its levels, and is not modified
#' f <- factor(c("1. Yes", "0. No"))
#' strip_level_prefix(f)
#' levels(f)
strip_level_prefix <- function(x) {
  if (is.factor(x)) {
    x <- levels(x)
  }
  if (!is.character(x)) {
    stop("'x' must be a character vector or a factor.", call. = FALSE)
  }
  if (length(x) == 0L) {
    return(x)
  }

  out <- sub(.level_prefix_re, "", x)
  changed <- !is.na(x) & out != x

  # Refuse a strip that empties the text, and one whose remainder starts with
  # a digit -- "1-2 vessels" would otherwise become "2 vessels".
  refuse <- changed & (!nzchar(out) | grepl("^[0-9]", out))
  out[refuse] <- x[refuse]
  changed[refuse] <- FALSE

  .revert_collisions(out, x, changed)
}

## Preserve the level set. A strip that makes two entries identical is the
## silent merge the separator rule exists to prevent, arriving by a different
## door, so both members go back to their original text.
.revert_collisions <- function(out, original, changed) {
  collided <- unique(out[!is.na(out) & duplicated(out)])
  if (length(collided) == 0L) {
    return(out)
  }

  hit <- changed & !is.na(out) & out %in% collided
  if (!any(hit)) {
    return(out)
  }

  warning(
    sprintf(
      paste0("Stripping would collide %d level(s) on: %s. Those levels keep ",
             "their prefix; declare the text in value_labels.yml to resolve ",
             "it."),
      sum(hit), paste(sQuote(collided, q = FALSE), collapse = ", ")
    ),
    call. = FALSE
  )

  out[hit] <- original[hit]
  out
}

## =============================================================================
#' Report what stripping a code prefix would do to a dataset's levels
#'
#' @description
#' One row per level of each discrete variable, giving the text as stored and
#' the text that would be displayed once a leading code prefix is removed.
#' Like \code{\link{strip_level_prefix}} it reports; it changes nothing.
#'
#' @details
#' The shape deliberately mirrors \code{\link{label_map}} one level down:
#' \code{level}, \code{level_full} and \code{stripped} read the same way as
#' \code{label}, \code{label_full} and \code{truncated}. So
#' \code{subset(level_map(data), stripped)} answers "which levels will print
#' differently", exactly as \code{subset(label_map(data), truncated)} answers
#' the question for labels.
#'
#' Where the codes come from depends on what the column carries:
#' \itemize{
#'   \item a column with value labels - from \code{value_labels.yml} via
#'     \code{\link{apply_value_labels}}, or from a SAS format catalog - gives
#'     the declared codes;
#'   \item a factor gives its integer level positions, which is what the
#'     column actually stores;
#'   \item a character column has no codes, and \code{code} is \code{NA}.
#' }
#'
#' Plain numeric and logical columns contribute no rows: they have no level
#' text for a prefix to sit in front of.
#'
#' \strong{High-cardinality columns are skipped, not expanded.} A character
#' column of identifiers would otherwise contribute thousands of rows to a
#' report meant to be read. Columns with more than \code{max_levels} distinct
#' values are omitted and named in a warning, so a skip is never silent.
#'
#' @param data A data frame.
#' @param vars Optional character vector of column names to report. Defaults
#'   to every discrete column - factor, value-labelled, or character. Naming a
#'   column that is not in \code{data} is an error.
#' @param max_levels Maximum distinct values a column may have before it is
#'   skipped. A single positive whole number; defaults to 20.
#'
#' @return A data frame with one row per reported level and the columns
#' \describe{
#'   \item{key}{The variable name}
#'   \item{code}{The code the level maps to, as character, or \code{NA}}
#'   \item{level}{The text to display, with a prefix stripped where the rule
#'     in \code{\link{strip_level_prefix}} allows it}
#'   \item{level_full}{The level text as stored, never modified}
#'   \item{stripped}{Logical: \code{TRUE} where \code{level} differs from
#'     \code{level_full}}
#' }
#' Zero rows, with those columns, when nothing is reportable.
#'
#' @seealso \code{\link{strip_level_prefix}} for the rule itself,
#'   \code{\link{label_map}} for the same idea applied to variable labels,
#'   \code{\link{apply_value_labels}} for declaring level text outright.
#'
#' @export
#'
#' @examples
#' dta <- data.frame(
#'   disp = factor(c("1. Home", "2. Rehab", "1. Home")),
#'   vess = factor(c("1 vessel", "2 vessel", "1 vessel"))
#' )
#' level_map(dta)
#'
#' # Which levels will print differently
#' subset(level_map(dta), stripped)
level_map <- function(data, vars = NULL, max_levels = 20L) {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame.", call. = FALSE)
  }
  ok <- length(max_levels) == 1L &&
    is.numeric(max_levels) &&
    !is.na(max_levels) &&
    max_levels >= 1
  if (!ok) {
    stop("'max_levels' must be a single positive number.", call. = FALSE)
  }

  if (is.null(vars)) {
    vars <- names(data)[vapply(data, .has_level_text, logical(1))]
  } else {
    missing_vars <- setdiff(vars, names(data))
    if (length(missing_vars) > 0) {
      stop(
        sprintf("Variable(s) not found in data: %s.",
                paste(missing_vars, collapse = ", ")),
        call. = FALSE
      )
    }
  }

  pieces <- list()
  skipped <- character(0)

  for (v in vars) {
    lv <- .level_text(data[[v]])
    if (length(lv$level_full) == 0L) {
      next
    }
    if (length(lv$level_full) > max_levels) {
      skipped <- c(skipped, v)
      next
    }
    display <- strip_level_prefix(lv$level_full)
    pieces[[v]] <- data.frame(
      key        = rep(v, length(lv$level_full)),
      code       = lv$code,
      level      = display,
      level_full = lv$level_full,
      stripped   = display != lv$level_full,
      stringsAsFactors = FALSE
    )
  }

  if (length(skipped) > 0) {
    warning(
      sprintf(
        "%d column(s) skipped for having more than %d distinct values: %s.",
        length(skipped), as.integer(max_levels),
        paste(skipped, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (length(pieces) == 0L) {
    return(.empty_level_map())
  }

  result <- do.call(rbind, unname(pieces))
  rownames(result) <- NULL
  result
}

## A column has level text when it stores text for its distinct values:
## a factor, a value-labelled column, or a character vector. A plain numeric
## or logical column has none, so a prefix cannot sit in front of anything.
.has_level_text <- function(x) {
  is.factor(x) || is.character(x) ||
    length(labelled::val_labels(x)) > 0L
}

## The level text and the codes it maps to, in the order the column implies.
.level_text <- function(x) {
  vl <- labelled::val_labels(x)
  if (length(vl) > 0L) {
    return(list(level_full = names(vl), code = as.character(unname(vl))))
  }
  if (is.factor(x)) {
    lv <- levels(x)
    return(list(level_full = lv, code = as.character(seq_along(lv))))
  }
  if (is.character(x)) {
    lv <- sort(unique(x[!is.na(x)]))
    return(list(level_full = lv, code = rep(NA_character_, length(lv))))
  }
  list(level_full = character(0), code = character(0))
}

.empty_level_map <- function() {
  data.frame(
    key        = character(0),
    code       = character(0),
    level      = character(0),
    level_full = character(0),
    stripped   = logical(0),
    stringsAsFactors = FALSE
  )
}
