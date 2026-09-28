## =============================================================================
## Study abbreviation lists: a group default, a study's own list in
## _study.yml, and a job's entries, merged in one place.
## Design: dev/specs/2026-09-25-study-abbreviations-design.md.

## The group default list, shipped as inst/extdata/abbreviations.yml, as the
## file holds it: a named list, phrase to abbreviation. Left uncoerced so that
## study_abbreviations() checks it and reports a bad entry beside its level.
.abbreviation_defaults <- function(path = system.file("extdata", "abbreviations.yml", package = "hvtiRutilities")) {
  raw <- if (nzchar(path)) yaml::read_yaml(path) else NULL
  if (!length(raw)) list() else raw
}

## One level's entries as a named list, NULL meaning "remove this phrase".
.abbreviation_entries <- function(x) {
  if (is.null(x) || !length(x)) {
    return(list())
  }
  # A single NA marks a removal in either shape: a character vector cannot
  # hold NULL, and list(x = NA) is how a list spells the same thing.
  lapply(as.list(x), function(v) if (length(v) == 1L && is.na(v)) NULL else v)
}

## Every problem with one level's entries, as messages naming the phrase and
## the level. `allow_null` is FALSE only for the group default, which has
## nothing below it to remove.
.abbreviation_problems <- function(entries, level, allow_null = TRUE) {
  phrases <- names(entries)
  if (length(entries) && (is.null(phrases) || anyNA(phrases) || !all(nzchar(phrases)))) {
    return(sprintf("an entry with no phrase (%s)", level))
  }
  out <- character()
  for (i in seq_along(entries)) {
    p <- phrases[i]
    v <- entries[[i]]
    if (is.null(v)) {
      if (!allow_null) out <- c(out, sprintf("'%s' (%s): the default list cannot remove a phrase", p, level))
      next
    }
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      out <- c(out, sprintf("'%s' (%s): the abbreviation must be one non-empty string, or null to remove it", p, level))
    } else if (nchar(v) > nchar(p)) {
      out <- c(out, sprintf("'%s' (%s): the abbreviation '%s' is longer than its phrase", p, level, v))
    }
  }
  twice <- unique(phrases[duplicated(tolower(phrases))])
  c(out, sprintf("'%s' (%s): listed more than once, ignoring case", twice, level))
}

## Validate the abbreviations: block for study_config(). Only the study list's
## own rules; clashes with the default list are study_abbreviations()' job.
.study_validate_abbreviations <- function(value, found) {
  if (is.null(value)) {
    return(NULL)
  }
  if (!is.list(value) || (length(value) && is.null(names(value)))) {
    stop("study_config(): abbreviations: in ", found, " must be a mapping of phrase to abbreviation.",
         call. = FALSE)
  }
  problems <- .abbreviation_problems(value, "study")
  if (length(problems)) {
    stop("study_config(): abbreviations: in ", found, " has ", length(problems), " problem",
         if (length(problems) > 1L) "s" else "", ":\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  value
}

#' The abbreviation list a study's labels use
#'
#' @description
#' Merges the three abbreviation lists a job's labels can draw on, and checks
#' the result, so that \code{\link{label_map}} shortens labels the same way in
#' every job of a study:
#' \enumerate{
#'   \item \code{extra}, the job's own entries;
#'   \item the study's \code{abbreviations:} mapping in \code{_study.yml};
#'   \item the group default list shipped with this package.
#' }
#' A higher level replaces a lower level's entry for the same phrase, compared
#' ignoring case, and an entry of \code{null} (\code{NA} or \code{NULL} in
#' \code{extra}) removes it.
#'
#' @details
#' Every list is checked before anything is merged, and every problem is
#' reported in one error: an abbreviation must be one non-empty string no
#' longer than its phrase, and a phrase may appear only once in a list. After
#' merging, two phrases may not share an abbreviation, compared ignoring case,
#' because the shortened label could then mean either; the error names both
#' phrases and the level each came from.
#'
#' The list is a display input. It is never written into the stored labels.
#'
#' @param cfg A study configuration, as returned by \code{\link{study_config}}.
#' @param extra The job's own entries: a named character vector or list,
#'   phrase to abbreviation, with \code{NA} or \code{NULL} to remove a phrase
#'   a lower level supplies. \code{NULL} for none.
#' @param defaults \code{FALSE} leaves the group default list out.
#'
#' @return A named character vector, phrase to abbreviation, ready for
#'   \code{label_map(abbreviations = )}, with a \code{source} attribute of the
#'   same length naming each entry's level: \code{"job"}, \code{"study"} or
#'   \code{"default"}. Removed phrases do not appear.
#'
#' @seealso \code{\link{add_abbreviation}} to add to a study's list,
#'   \code{\link{label_map}}, which applies it.
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "abbrev-example")
#' study_setup(root, "Abbreviation example", 1L)
#' add_abbreviation("Surgical procedure", "SP", start = root)
#' study_abbreviations(study_config(root, require_data = FALSE),
#'                     extra = c("Left ventricular outflow tract" = "LVOT"))
#' unlink(root, recursive = TRUE)
study_abbreviations <- function(cfg = study_config(), extra = NULL, defaults = TRUE) {
  if (!is.logical(defaults) || length(defaults) != 1L || is.na(defaults)) {
    stop("'defaults' must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.null(extra) && (!(is.character(extra) || is.list(extra)) || (length(extra) && is.null(names(extra))))) {
    stop("'extra' must be NULL or a named character vector or list, phrase to abbreviation.", call. = FALSE)
  }
  levels <- list(
    default = if (defaults) .abbreviation_entries(.abbreviation_defaults()) else list(),
    study = .abbreviation_entries(cfg$abbreviations),
    job = .abbreviation_entries(extra)
  )
  problems <- unlist(Map(.abbreviation_problems, levels, names(levels), c(FALSE, TRUE, TRUE)))
  if (length(problems)) {
    stop("study_abbreviations(): ", length(problems), " problem", if (length(problems) > 1L) "s" else "",
         " in the abbreviation lists:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }

  phrase <- character()
  short <- character()
  source <- character()
  for (level in names(levels)) {
    entries <- levels[[level]]
    for (p in names(entries)) {
      keep <- tolower(phrase) != tolower(p)
      phrase <- phrase[keep]
      short <- short[keep]
      source <- source[keep]
      if (!is.null(entries[[p]])) {
        phrase <- c(phrase, p)
        short <- c(short, entries[[p]])
        source <- c(source, level)
      }
    }
  }

  shared <- unique(tolower(short[duplicated(tolower(short))]))
  if (length(shared)) {
    clashes <- vapply(shared, function(s) {
      i <- which(tolower(short) == s)
      sprintf("'%s' abbreviates %s", short[i[1L]], paste(sprintf("%s (%s)", phrase[i], source[i]), collapse = " and "))
    }, character(1L))
    stop("study_abbreviations(): two phrases share an abbreviation, so a shortened label could mean either:\n  ",
         paste(clashes, collapse = "\n  "), call. = FALSE)
  }

  out <- stats::setNames(short, phrase)
  attr(out, "source") <- source
  out
}

#' Add a phrase to a study's abbreviation list
#'
#' @description
#' Writes one entry to the \code{abbreviations:} mapping in the study's
#' \code{_study.yml}, replacing any entry for the same phrase, compared
#' ignoring case. \code{abbreviation = NULL} writes a removal: the study then
#' drops that phrase from the group default list.
#'
#' @details
#' The entry is checked against the whole merged list, as
#' \code{\link{study_abbreviations}} would check it, before anything is
#' written; a refused entry leaves the file as it was. The file is rewritten
#' whole, as \code{\link{register_data}} rewrites it, so comments in
#' \code{_study.yml} are not kept.
#'
#' @param phrase The phrase, as it appears in labels.
#' @param abbreviation Its abbreviation, or \code{NULL} to remove a default.
#' @param start A directory inside the study; the study is found as
#'   \code{\link{study_config}} finds it.
#'
#' @return The study's abbreviation list after the change, invisibly, as a
#'   named list.
#'
#' @seealso \code{\link{study_abbreviations}}.
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "add-abbrev-example")
#' study_setup(root, "Abbreviation example", 1L)
#' add_abbreviation("Surgical procedure", "SP", start = root)
#' add_abbreviation("Ejection fraction", NULL, start = root)
#' unlink(root, recursive = TRUE)
add_abbreviation <- function(phrase, abbreviation, start = getwd()) {
  if (!is.character(phrase) || length(phrase) != 1L || is.na(phrase) || !nzchar(phrase)) {
    stop("'phrase' must be one non-empty string.", call. = FALSE)
  }
  if (!is.null(abbreviation) && (!is.character(abbreviation) || length(abbreviation) != 1L)) {
    stop("'abbreviation' must be one string, or NULL to remove a default.", call. = FALSE)
  }
  cfg <- study_config(start, require_data = FALSE)
  raw <- yaml::read_yaml(cfg$file)
  entries <- raw$abbreviations
  if (is.null(entries)) entries <- list()
  entries <- entries[tolower(names(entries)) != tolower(phrase)]
  entries[phrase] <- list(abbreviation)

  problems <- .abbreviation_problems(entries, "study")
  if (length(problems)) {
    stop("add_abbreviation(): ", paste(problems, collapse = "; "), call. = FALSE)
  }
  cfg$abbreviations <- entries
  study_abbreviations(cfg)

  raw$abbreviations <- entries
  .study_write_atomic(raw, cfg$file)
  invisible(entries)
}
