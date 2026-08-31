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
#' body count and defining files. In SAS, \code{\%include}-ing two files that
#' define the same macro means the second silently shadows the first, so this
#' report is a prerequisite for building a trustworthy SAS harness.
#'
#' @details
#' The report ends with a \strong{Provenance} section derived from the scanned
#' corpus rather than from the clock: a fingerprint over every
#' (macro, file, body hash) triple and the excluded-directory list, the file,
#' definition and name counts, and the package version.
#'
#' A generated-on field would defeat the byte-for-byte reproducibility that
#' makes the artifact reviewable, which is why neither this report nor
#' \code{\link{write_macro_manifest}} carries one. An artifact with no identity
#' at all is the opposite failure: a committed report and a design's prose can
#' disagree with nothing to say which is stale. An input-derived stamp avoids
#' both, because it is identical on every re-run of the same corpus.
#'
#' The fingerprint follows content, not location. \code{\link{sas_triage}}
#' records file basenames, so re-scanning the same corpus from a different
#' mount point yields the same value and a share remount does not invalidate
#' every committed report.
#'
#' @param x A \code{data.frame} returned by \code{\link{sas_triage}}.
#' @param path Character. Destination \code{.md} path.
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

  ## Select on the number of *files*, which is what the report says it lists and
  ## what makes a name %include order-dependent. Counting definitions instead
  ## admitted macros redefined twice inside one file: they printed with
  ## `Files = 1`, contradicting the heading, and they are not an ordering
  ## hazard -- SAS just takes the later definition. sas_triage() decides those
  ## under rule 3, and the manifest carries the evidence.
  per_file <- tapply(defs$file, defs$macro, function(f) length(unique(f)))
  multi <- sort(names(per_file[per_file > 1L]))

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

  ex <- attr(x, "excluded_dirs")
  if (!is.null(ex) && nrow(ex) > 0L) {
    lines <- c(
      lines, "", "## Excluded subdirectories", "",
      "Not triaged. Counts recorded so the omission is visible.", "",
      "| Directory | `.sas` files |", "|---|---|",
      sprintf("| `%s` | %d |", ex$directory, ex$n_sas)
    )
  }

  lines <- c(lines, .report_provenance(defs, ex))

  writeLines(lines, path)
  invisible(path)
}

## Provenance derived from the inputs rather than the clock.
##
## A generated-on field would defeat byte-for-byte reproducibility, which is
## why the manifest carries none. But an artifact with no identity at all
## cannot be attributed to the run that produced it: a committed report and a
## design's prose can disagree with nothing to say which is stale. That is not
## hypothetical -- it happened to the `skip` figures.
##
## A stamp taken from the corpus is identical on every re-run of that corpus,
## so it costs nothing and settles the question. `file` is a basename, so the
## fingerprint follows the content scanned rather than where it was mounted --
## a share remount must not invalidate every committed report.
.report_provenance <- function(defs, ex) {
  ident <- sort(unique(paste(defs$macro, defs$file, defs$body_hash)))
  if (!is.null(ex) && nrow(ex) > 0L) {
    ident <- c(ident, sort(paste("!excluded", ex$directory, ex$n_sas)))
  }

  fp <- digest::digest(
    paste(ident, collapse = "\n"),
    algo = "sha256", serialize = FALSE
  )

  c(
    "", "## Provenance", "",
    "Derived from the scanned corpus, never from the clock, so the report",
    "reproduces byte-for-byte on any re-run of the same corpus. A report that",
    "disagrees with prose elsewhere can be settled by re-running and comparing",
    "the fingerprint.", "",
    "| Field | Value |", "|---|---|",
    sprintf("| corpus fingerprint | `%s` |", substr(fp, 1L, 16L)),
    sprintf("| files scanned | %d |", length(unique(defs$file))),
    sprintf("| macro definitions | %d |", nrow(defs)),
    sprintf("| distinct macro names | %d |", length(unique(defs$macro))),
    sprintf(
      "| excluded subdirectories | %d |",
      if (is.null(ex)) 0L else nrow(ex)
    ),
    sprintf(
      "| hvtiRutilities | %s |",
      as.character(utils::packageVersion("hvtiRutilities"))
    )
  )
}
