## =============================================================================
## Internal: pull the first capture group of `re` from `lines`, or NA.
.header_field <- function(lines, re, which = c("first", "last")) {
  which <- match.arg(which)
  hits <- grep(re, lines, ignore.case = TRUE, value = TRUE)
  if (length(hits) == 0L) {
    return(NA_character_)
  }
  hit <- if (which == "first") hits[1L] else hits[length(hits)]
  trimws(sub(paste0(".*", re, ".*$"), "\\1", hit, ignore.case = TRUE))
}

## =============================================================================
#' Parse the documentation header of a legacy SAS macro file
#'
#' @description
#' Legacy CORR macros carry a structured comment block naming the macro, its
#' purpose, its documented call signature, and a modification log. This function
#' extracts those fields. They are used as evidence during human review of
#' divergent macro redefinitions, and the documented call is a direct input to
#' the Phase 1 SAS harness.
#'
#' @details
#' All fields are optional. A file with no header block yields a row of
#' \code{NA}s rather than an error, because an undocumented macro is a normal
#' occurrence in this corpus and not a defect.
#'
#' When several \code{MODIFIED BY} lines are present, the \strong{last} date is
#' returned. Note that this date is advisory evidence only; \code{sas_triage()}
#' never uses it to choose between competing macro definitions.
#'
#' @param file Character. Path to a `.sas` file.
#'
#' @return A one-row \code{data.frame} with columns \code{file},
#'   \code{macro_name}, \code{short_desc}, \code{created_on},
#'   \code{modified_on}, and \code{documented_call}. Absent fields are
#'   \code{NA_character_}. \code{macro_name} is lowercased.
#'
#' @export sas_macro_signature
#'
#' @examples
#' f <- system.file("extdata", "example_macro.sas", package = "hvtiRutilities")
#' if (nzchar(f)) sas_macro_signature(f)
sas_macro_signature <- function(file) {
  if (!file.exists(file)) {
    stop("File does not exist: ", file, call. = FALSE)
  }

  lines <- .read_sas_lines(file)

  macro_name <- .header_field(lines, "MACRO NAME:[[:space:]]*([A-Za-z0-9_]+)")
  short_desc <- .header_field(lines, "SHORT DESC:[[:space:]]*(.*?)[[:space:]]*$")
  created_on <- .header_field(lines, "CREATED BY:.*?([0-9]{4}/[0-9]{2}/[0-9]{2})")
  modified_on <- .header_field(
    lines, "MODIFIED BY:.*?([0-9]{4}/[0-9]{2}/[0-9]{2})",
    which = "last"
  )

  call_hits <- grep("^\\*[[:space:]]*(%[A-Za-z0-9_]+\\(.*\\))", lines, value = TRUE)
  documented_call <- if (length(call_hits) == 0L) {
    NA_character_
  } else {
    trimws(sub("^\\*[[:space:]]*", "", call_hits[1L]))
  }

  data.frame(
    file            = basename(file),
    macro_name      = if (is.na(macro_name)) NA_character_ else tolower(macro_name),
    short_desc      = short_desc,
    created_on      = created_on,
    modified_on     = modified_on,
    documented_call = documented_call,
    stringsAsFactors = FALSE
  )
}
