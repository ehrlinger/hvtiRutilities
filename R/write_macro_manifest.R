## =============================================================================
#' Write the canonical macro manifest
#'
#' @description
#' Serialises a \code{sas_triage()} decision table to YAML, one entry per macro
#' name, recording its status and every file that defines it.
#'
#' @details
#' The manifest deliberately contains \strong{no timestamp}. It describes a
#' frozen 2019 corpus, and a generated-on field would defeat the byte-for-byte
#' reproducibility that makes the manifest trustworthy as a reviewed artifact.
#' Run metadata belongs in the report, not here. This diverges from
#' \code{\link{update_manifest}}, whose \code{extract_date} is meaningful
#' because the datasets it tracks genuinely change over time.
#'
#' @param x A \code{data.frame} returned by \code{\link{sas_triage}}.
#' @param path Character. Destination `.yaml` path.
#'
#' @return Invisibly, \code{path}.
#'
#' @export write_macro_manifest
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) {
#'   write_macro_manifest(sas_triage(d), tempfile(fileext = ".yaml"))
#' }
#' }
write_macro_manifest <- function(x, path) {
  # File-level drop rows (rules 1-3) carry macro = "" so that base-R
  # `df[df$macro == name, ]` subsetting in the tests does not inject phantom
  # NA rows. Real macro definitions always have a non-empty name, so nzchar()
  # cleanly separates definitions from whole-file drops.
  defs <- x[!is.na(x$macro) & nzchar(x$macro), , drop = FALSE]
  macros <- sort(unique(defs$macro))

  entries <- lapply(macros, function(m) {
    rows <- defs[defs$macro == m, , drop = FALSE]
    rows <- rows[order(rows$file), , drop = FALSE]

    status <- if (any(rows$decision == "ambiguous")) {
      "ambiguous"
    } else {
      "canonical"
    }

    list(
      macro      = m,
      status     = status,
      rule       = as.integer(rows$rule[1L]),
      visibility = rows$visibility[1L],
      params     = rows$params[1L],
      candidates = lapply(seq_len(nrow(rows)), function(i) {
        list(
          file      = rows$file[i],
          body_hash = substr(rows$body_hash[i], 1L, 16L),
          decision  = rows$decision[i],
          evidence  = rows$evidence[i]
        )
      })
    )
  })

  yaml::write_yaml(list(macros = entries), path)
  invisible(path)
}

## =============================================================================
#' Write the macro name-collision report
#'
#' @description
#' Reports every macro name defined in more than one file, with its distinct
#' body count and defining files. In SAS, `%include`-ing two files that define
#' the same macro means the second silently shadows the first, so this report
#' is a prerequisite for building a trustworthy SAS harness.
#'
#' @param x A \code{data.frame} returned by \code{\link{sas_triage}}.
#' @param path Character. Destination `.md` path.
#'
#' @return Invisibly, \code{path}.
#'
#' @export write_collision_report
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) {
#'   write_collision_report(sas_triage(d), tempfile(fileext = ".md"))
#' }
#' }
write_collision_report <- function(x, path) {
  # nzchar() excludes file-level drop rows (macro = ""); see write_macro_manifest.
  defs <- x[!is.na(x$macro) & nzchar(x$macro), , drop = FALSE]

  counts <- table(defs$macro)
  multi <- sort(names(counts[counts > 1L]))

  lines <- c(
    "# SAS macro name-collision report",
    "",
    "Macro names defined in more than one file. In SAS, `%include`-ing two",
    "such files means the second definition silently shadows the first.",
    "",
    "| Macro | Files | Distinct bodies | Visibility | Status |",
    "|---|---|---|---|---|"
  )

  for (m in multi) {
    rows <- defs[defs$macro == m, , drop = FALSE]
    status <- if (any(rows$decision == "ambiguous")) "**ambiguous**" else "canonical"
    lines <- c(lines, sprintf(
      "| `%s` | %d | %d | %s | %s |",
      m, length(unique(rows$file)), length(unique(rows$body_hash)),
      rows$visibility[1L], status
    ))
  }

  lines <- c(lines, "", sprintf("Total colliding names: %d", length(multi)))
  writeLines(lines, path)
  invisible(path)
}
