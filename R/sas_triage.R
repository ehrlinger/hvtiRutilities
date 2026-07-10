## =============================================================================
## Internal: known variant markers observed in the legacy corpus.
## Ordered longest-first so that `_test_at` strips before `_test`.
.VARIANT_SUFFIXES <- c(
  "_test_at", "_testma", "_test", "_old", "_new", "_orig",
  "_wt", "_at", "_b", "ma"
)

## =============================================================================
## Internal: strip one trailing variant marker from a lowercased stem.
.strip_variant_suffix <- function(stem) {
  for (sfx in .VARIANT_SUFFIXES) {
    if (grepl(paste0(sfx, "$"), stem) && nchar(stem) > nchar(sfx)) {
      return(sub(paste0(sfx, "$"), "", stem))
    }
  }
  stem
}

## =============================================================================
## Internal: classify a macro definition as a public entry point or a private
## inline helper. Advisory only -- never used to drop a definition.
.classify_visibility <- function(macro, file) {
  stem <- tolower(sub("\\.sas~?$", "", basename(file), ignore.case = TRUE))
  macro <- tolower(macro)

  if (identical(stem, macro)) {
    return("public")
  }
  if (identical(.strip_variant_suffix(stem), macro)) {
    return("public?")
  }
  "private"
}

## =============================================================================
## Internal: NULL-coalescing operator. Base R gained `%||%` in 4.4.0; this
## package declares R (>= 4.1.0), so define it here rather than raise the floor.
`%||%` <- function(x, y) if (is.null(x)) y else x

## =============================================================================
## Internal: refuse to return a decision table with holes in it.
.assert_no_unclassified <- function(tbl) {
  n <- sum(tbl$decision == "unclassified")
  if (n > 0L) {
    stop(
      n, " definition(s) unclassified: ",
      paste(unique(tbl$macro[tbl$decision == "unclassified"]), collapse = ", "),
      ". Every definition must carry a decision.",
      call. = FALSE
    )
  }
  invisible(tbl)
}

## =============================================================================
## Internal: read and validate the overrides file.
.read_overrides <- function(path) {
  if (is.null(path)) {
    return(list())
  }
  if (!file.exists(path)) {
    stop("Overrides file does not exist: ", path, call. = FALSE)
  }
  ov <- yaml::read_yaml(path)
  required <- c("macro", "canonical_file", "rationale", "decided_by", "decided_on")
  for (entry in ov) {
    missing <- setdiff(required, names(entry))
    if (length(missing) > 0L) {
      stop(
        "Override for '", entry$macro %||% "<unnamed>",
        "' is missing field(s): ", paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
  }
  stats::setNames(ov, vapply(ov, function(e) tolower(e$macro), character(1)))
}

## =============================================================================
#' Triage a directory of legacy SAS macro files
#'
#' @description
#' Applies an ordered rule ladder to every `.sas` file in \code{dir} and returns
#' one row per macro definition, each carrying a \code{decision} and the
#' \code{evidence} that justifies it.
#'
#' @details
#' Only the top level of \code{dir} is scanned; subdirectories are ignored.
#'
#' File-level rules, applied first, in order:
#' \enumerate{
#'   \item \code{Copy of *} -- drop, as a filename-prefix duplicate.
#'   \item \code{*.sas~} -- drop, as an editor backup superseded by construction.
#'   \item Fails \code{.sas_lint()} -- drop, citing the specific lint failure.
#' }
#'
#' Definition-level rules, applied per macro name across surviving files:
#' \enumerate{
#'   \item[4.] Defined in exactly one file -- canonical.
#'   \item[5.] Defined in several files, all bodies hashing identically --
#'     canonical, recording every defining file.
#'   \item[6.] Defined in several files with two or more distinct bodies --
#'     \strong{ambiguous}. No canonical file is chosen.
#' }
#'
#' Rule 6 never auto-resolves. Modification dates and visibility are attached as
#' evidence for a human, never consumed as a tiebreaker, because a tool that
#' silently picks a winner launders a coin-flip into a committed artifact.
#' Filesystem mtime is deliberately never consulted: the corpus froze in 2019
#' and lives on a network volume where timestamps do not survive copies.
#'
#' Ambiguity is resolved by a human writing an entry into \code{overrides} and
#' re-running. This makes the result reproducible and auditable.
#'
#' @param dir Character. Path to a directory of `.sas` files. Use a local clone;
#'   the canonical library lives on a network volume where file operations are
#'   slow.
#' @param overrides Character or \code{NULL}. Path to a `macro_overrides.yaml`
#'   recording human decisions. Each entry requires \code{macro},
#'   \code{canonical_file}, \code{rationale}, \code{decided_by}, and
#'   \code{decided_on}.
#'
#' @return A \code{data.frame} with one row per macro definition and columns
#'   \code{file}, \code{macro}, \code{params}, \code{body_hash},
#'   \code{line_start}, \code{line_end}, \code{visibility}, \code{decision},
#'   \code{rule}, and \code{evidence}. Rows are sorted by \code{macro} then
#'   \code{file}, so the result is deterministic.
#'
#' @export sas_triage
#'
#' @examples
#' \donttest{
#' d <- system.file("extdata", "macros", package = "hvtiRutilities")
#' if (nzchar(d)) sas_triage(d)
#' }
#'
#' @importFrom stats setNames
sas_triage <- function(dir, overrides = NULL) {
  files <- list.files(dir, pattern = "\\.sas~?$", ignore.case = TRUE,
                      full.names = TRUE)
  if (length(files) == 0L) {
    stop("no .sas files found in: ", dir, call. = FALSE)
  }
  ov <- .read_overrides(overrides)

  dropped <- list()
  kept <- character(0)

  ## --- file-level rules 1-3 -------------------------------------------------
  for (f in files) {
    b <- basename(f)

    if (grepl("^Copy of ", b)) {
      dropped[[b]] <- list(rule = 1L, evidence = "filename-prefix duplicate")
    } else if (grepl("~$", b)) {
      dropped[[b]] <- list(
        rule = 2L,
        evidence = "editor backup, superseded by construction"
      )
    } else {
      lint <- .sas_lint(f)
      if (!lint$valid) {
        dropped[[b]] <- list(
          rule = 3L,
          evidence = paste("lint:", paste(lint$failures, collapse = "; "))
        )
      } else {
        kept <- c(kept, f)
      }
    }
  }

  drop_rows <- if (length(dropped) == 0L) {
    NULL
  } else {
    do.call(rbind, lapply(names(dropped), function(b) {
      data.frame(
        file = b, macro = "", params = NA_character_,
        body_hash = NA_character_, line_start = NA_integer_,
        line_end = NA_integer_, visibility = NA_character_,
        decision = "drop", rule = dropped[[b]]$rule,
        evidence = dropped[[b]]$evidence, stringsAsFactors = FALSE
      )
    }))
  }

  ## --- extract definitions from surviving files -----------------------------
  defs <- do.call(rbind, lapply(kept, sas_macro_defs))
  defs$visibility <- mapply(.classify_visibility, defs$macro, defs$file,
                            USE.NAMES = FALSE)
  defs$decision <- "unclassified"
  defs$rule <- NA_integer_
  defs$evidence <- NA_character_

  ## --- definition-level rules 4-6 -------------------------------------------
  for (m in unique(defs$macro)) {
    idx <- which(defs$macro == m)
    n_files <- length(unique(defs$file[idx]))
    n_bodies <- length(unique(defs$body_hash[idx]))

    if (n_files == 1L) {
      defs$decision[idx] <- "canonical"
      defs$rule[idx] <- 4L
      defs$evidence[idx] <- "defined once"
    } else if (n_bodies == 1L) {
      defs$decision[idx] <- "canonical"
      defs$rule[idx] <- 5L
      defs$evidence[idx] <- sprintf("%d identical copies", n_files)
    } else {
      defs$decision[idx] <- "ambiguous"
      defs$rule[idx] <- 6L
      defs$evidence[idx] <- sprintf(
        "%d distinct bodies across %d files; human decision required",
        n_bodies, n_files
      )
    }
  }

  ## --- apply human overrides ------------------------------------------------
  for (m in names(ov)) {
    idx <- which(defs$macro == m)
    if (length(idx) == 0L) {
      stop("Override names unknown macro: ", m, call. = FALSE)
    }
    canon <- ov[[m]]$canonical_file
    if (!canon %in% defs$file[idx]) {
      stop(
        "Override for '", m, "' names canonical_file '", canon,
        "', which does not define it.", call. = FALSE
      )
    }
    win <- idx[defs$file[idx] == canon]
    lose <- setdiff(idx, win)

    defs$decision[win] <- "canonical"
    defs$evidence[win] <- paste0("override: ", ov[[m]]$rationale)
    defs$decision[lose] <- "drop"
    defs$evidence[lose] <- paste0("override: superseded by ", canon)
  }

  out <- rbind(defs, drop_rows)
  .assert_no_unclassified(out)

  out <- out[order(out$macro, out$file, na.last = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  out
}
