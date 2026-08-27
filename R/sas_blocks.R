#' Read a variable list out of a SAS job
#'
#' @description
#' The SAS jobs this package's callers reproduce specify their variables as
#' blocks in the `.sas`: a phase name on its own line, then comma-separated
#' names, terminated by a bare `;`.
#'
#' Reading them rather than transcribing them is the point. A transcribed list
#' drifts from the job it claims to reproduce, and nothing catches it.
#'
#' @details
#' **Comment handling is the whole difficulty, and getting it wrong is silent
#' in both directions.** Measured on a real screen (`bh.dead_s3_JR.sas`):
#'
#' * Stripping `/*...*/` line by line leaves banner comments intact, because
#'   `/***** Patient Variables *****/` contains `*` and so does not match a
#'   `[^*]*` body. The banner text then glues onto the **first** name on the
#'   next line and that name vanishes: `female`, `afib_pr`, `plvidd` and `size`
#'   were all lost this way.
#' * A `/* ... */` spanning two lines is never stripped at all, so a
#'   commented-**out** variable is read as live: `avet_con` entered a screen
#'   that way.
#'
#' Collapsing the block first and stripping lazily handles both, and that is
#' what this function does.
#'
#' Three name forms are normalised. `name=value` appears where a job carries
#' starting or converged estimates; only the name is taken, because a job's
#' converged values are its answer for its own study and must not be inherited
#' by a copy of it. `name/I` marks a variable forced into the model, and the
#' suffix is an option on the name rather than part of it. Names are lowercased,
#' because SAS variable names are case-insensitive and [read_clinical_data()]
#' lowercases them.
#'
#' @param lines Character vector: the `.sas` file, as from `readLines()`.
#' @param marker Regular expression matching the line that opens the block,
#'   e.g. `"^\\s*early\\s*$"`.
#' @param after Optional regular expression. When given, the search starts at
#'   the first line matching it, so a block can be located inside one particular
#'   macro rather than the first one in the file.
#' @param what Character label for the block, used in error messages.
#'
#' @return A character vector of unique variable names, lowercased, in the
#'   order they appear in the block.
#'
#' @seealso [sas_path()], [covariate_audit()]
#'
#' @export
#'
#' @examples
#' sas <- c("%macro final;", "  early", "    age, ln_age, /* dropped */",
#'          "    bsa=0.31", "  ;", "%mend;")
#' sas_variable_block(sas, "^\\s*early\\s*$", after = "^\\s*%macro\\s+final")
sas_variable_block <- function(lines, marker, after = NULL, what = "block") {
  start <- 1L
  if (!is.null(after)) {
    i <- grep(after, lines)[1]
    if (is.na(i)) {
      stop("sas_variable_block(): no line matching ", after,
           ", so the ", what, " cannot be located.", call. = FALSE)
    }
    start <- i
  }
  region <- lines[start:length(lines)]

  i <- grep(marker, region)[1]
  if (is.na(i)) {
    stop("sas_variable_block(): no line matching ", marker, " for the ", what,
         ". An empty variable list would be read as a result.", call. = FALSE)
  }
  ends <- grep("^\\s*;\\s*$", region)
  ends <- ends[ends > i]
  if (!length(ends)) {
    stop("sas_variable_block(): the ", what, " at line ", i,
         " is not terminated by a bare `;`, so its extent is unknown.",
         call. = FALSE)
  }

  x <- region[(i + 1L):(min(ends) - 1L)]
  x <- x[!grepl("^\\s*\\*", x)]                       # SAS statement comments
  s <- paste(x, collapse = " ")
  s <- gsub("/\\*.*?\\*/", " ", s, perl = TRUE)       # /* ... */, across lines
  # SAS variable names are case-insensitive and read_clinical_data() lowercases
  # them, so fold case here too: an upper-case name in the job would otherwise
  # be dropped.
  x <- unlist(strsplit(tolower(s), ","))
  # `name=value` appears where a job carries starting or converged estimates.
  # Only the name is wanted: a job's converged values are its answer for its own
  # study and must not be inherited by a copy of it.
  x <- sub("=.*$", "", x)
  # `name/I` marks a variable forced into the model. The suffix is an option on
  # the name, not part of it, and leaving it attached would silently drop
  # exactly the variables the job selected.
  x <- sub("/.*$", "", x)
  x <- gsub("[;[:space:]]", "", x)

  out <- unique(x[grepl("^[a-z_][a-z0-9_]*$", x)])
  if (!length(out)) {
    stop("sas_variable_block(): the ", what, " parsed to zero variables.",
         call. = FALSE)
  }
  out
}
