## =============================================================================
## Internal: label_max validation and word-boundary truncation.
## See dev/specs/2026-09-02-label-length-and-fallback-design.md section 4.

.label_marker <- "..."

## The smallest cap that can hold the marker plus one character of label.
.label_marker_min <- nchar(.label_marker) + 1L

.validate_label_max <- function(label_max) {
  # NA is admitted because it disables truncation, and bare NA is logical.
  # TRUE and FALSE are not: as.numeric(TRUE) is 1, so TRUE would silently
  # mean "cap at one character" rather than being rejected.
  ok <- length(label_max) == 1L &&
    (is.numeric(label_max) ||
       (is.logical(label_max) && is.na(label_max)))
  if (!ok) {
    stop("'label_max' must be a single number, Inf or NA.", call. = FALSE)
  }
  if (is.na(label_max) || !is.finite(label_max)) {
    return(Inf)
  }
  # A cap with no room for the marker plus a character of label cannot
  # produce a marked cut, and an unmarked cut is what the marker exists to
  # prevent. Refuse it rather than quietly dropping the guarantee.
  if (label_max < .label_marker_min) {
    stop(
      sprintf(
        paste0("'label_max' must be at least %d, or Inf/NA to disable ",
               "truncation."),
        .label_marker_min
      ),
      call. = FALSE
    )
  }
  as.numeric(label_max)
}

## Cut on a word boundary and mark the cut. substr() alone produces
## "Ascending aorta only versus ascending plu", which reads as a short label
## rather than a cut one; the marker is what makes the parameter usable. The
## marker counts against the budget, so the result is never longer than
## label_max.
.truncate_labels <- function(text, label_max) {
  if (!length(text) || !is.finite(label_max)) {
    return(text)
  }

  # Guaranteed >= 1 by .validate_label_max(), so every cut is marked.
  budget <- label_max - nchar(.label_marker)
  out <- text

  for (i in which(!is.na(text) & nchar(text) > label_max)) {
    s <- text[i]
    head <- substr(s, 1, budget)
    # Keep the whole head when the cut already lands between words;
    # otherwise drop the partial word at the end.
    if (grepl("[[:space:]]", substr(s, budget + 1L, budget + 1L))) {
      stem <- head
    } else {
      trimmed <- sub("[[:space:]][^[:space:]]*$", "", head)
      stem <- if (nzchar(trimmed)) trimmed else head
    }
    # A marker hanging off a comma or a dash reads as a typo.
    stem <- sub("[[:space:][:punct:]]+$", "", stem)
    if (!nzchar(stem)) {
      stem <- head
    }
    out[i] <- paste0(stem, .label_marker)
  }

  out
}

## =============================================================================
## Internal: distinct labels stay distinct. Section 4.2 of the design above.
## Within one map, labels that differ in label_full differ in label.

## Words the initials rule skips: "History of heart failure" is HHF, not HOHF.
.label_small_words <- c("of", "and", "the", "in", "for", "to", "at", "on", "with", "by", "or")

.validate_abbreviations <- function(abbreviations) {
  if (is.null(abbreviations)) {
    return(stats::setNames(character(), character()))
  }
  phrases <- names(abbreviations)
  if (!is.character(abbreviations) || is.null(phrases) || anyNA(abbreviations) || anyNA(phrases) ||
        !all(nzchar(abbreviations)) || !all(nzchar(phrases)) || anyDuplicated(tolower(phrases))) {
    stop("'abbreviations' must be NULL or a named character vector, phrase = abbreviation, ",
         "with no missing, empty or repeated phrases.", call. = FALSE)
  }
  abbreviations
}

## Escape a phrase for use inside a regular expression.
.regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)

## The supplied abbreviation for a phrase, matched whole and case-insensitively,
## or NA.
.supplied_for <- function(phrase, abbreviations) {
  hit <- match(tolower(phrase), tolower(names(abbreviations)))
  if (is.na(hit)) NA_character_ else unname(abbreviations[[hit]])
}

## Initials of a heading's content words, or NA for a heading of fewer than two
## content words, because "P:" says less than "Procedure:". Splitting on
## whitespace only is what makes a hyphenated word count once.
.heading_initials <- function(heading) {
  words <- strsplit(heading, "[[:space:]]+")[[1L]]
  words <- words[nzchar(words) & !(tolower(words) %in% .label_small_words)]
  first <- toupper(substr(gsub("[^[:alnum:]]", "", words), 1L, 1L))
  first <- first[nzchar(first)]
  if (length(first) < 2L) NA_character_ else paste(first, collapse = "")
}

## Keep the head and the tail with the marker between them, so the end that
## tells two labels apart survives: "Ascending aorta ... plus arch".
.truncate_both_ends <- function(text, label_max) {
  mid <- paste0(" ", .label_marker, " ")
  budget <- label_max - nchar(mid)
  words <- strsplit(text, " ", fixed = TRUE)[[1L]]
  tail <- character()
  for (w in rev(words)) {
    candidate <- paste(c(w, tail), collapse = " ")
    if (nchar(candidate) > budget %/% 2L) break
    tail <- c(w, tail)
  }
  if (!length(tail) || length(tail) == length(words)) {
    return(text)
  }
  head_words <- words[seq_len(length(words) - length(tail))]
  head <- character()
  for (w in head_words) {
    candidate <- paste(c(head, w), collapse = " ")
    if (nchar(candidate) > budget - nchar(paste(tail, collapse = " "))) break
    head <- c(head, w)
  }
  if (!length(head)) {
    return(text)
  }
  paste0(sub("[[:space:][:punct:]]+$", "", paste(head, collapse = " ")), mid, paste(tail, collapse = " "))
}

## The display labels for a whole map. `full` is every row's label_full,
## `filled` marks rows where the variable name stands in for a missing label:
## those pass through whole (section 4.1) and take part only as text a label
## must not equal. Returns the label, truncated and over_cap columns and the
## abbreviations actually shown.
.display_labels <- function(full, filled, label_max, abbreviations) {
  n <- length(full)
  label <- full
  cut <- rep(FALSE, n)
  used <- vector("list", n)
  none <- data.frame(abbreviation = character(), expansion = character(), stringsAsFactors = FALSE)
  if (!n || !is.finite(label_max)) {
    return(list(label = label, truncated = cut, over_cap = cut, abbreviations = none))
  }
  own <- which(!filled)
  over <- function(i) nchar(label[i]) > label_max

  # Step 1: a heading shared by two or more labels, one of them over the cap,
  # is abbreviated in every label that carries it.
  sep_at <- regexpr(": | - |; ", full)
  has_heading <- !filled & sep_at > 0L
  heading <- ifelse(has_heading, substr(full, 1L, sep_at - 1L), NA_character_)
  groups <- split(which(has_heading), heading[has_heading])
  groups <- groups[vapply(groups, function(g) length(g) >= 2L && any(nchar(full[g]) > label_max), logical(1L))]
  if (length(groups)) {
    supplied <- vapply(names(groups), .supplied_for, character(1L), abbreviations = abbreviations)
    # A supplied heading keys the term its entry stands for, so spellings of
    # one term never give the key two rows.
    listed <- attr(abbreviations, "expansion")
    heading_expansion <- vapply(names(groups), function(h) {
      k <- match(tolower(h), tolower(names(abbreviations)))
      if (!is.na(supplied[[h]]) && length(listed) == length(abbreviations) && !is.na(k)) listed[[k]] else h
    }, character(1L))
    short <- vapply(names(groups), function(h) {
      if (is.na(supplied[[h]])) .heading_initials(h) else supplied[[h]]
    }, character(1L))
    # Initials that equal an abbreviation the list gives another phrase would
    # make one abbreviation mean two things in one key ("Aortic valve
    # reoperation" and the list's AVR): such a heading is not abbreviated.
    short[is.na(supplied) & short %in% unname(abbreviations)] <- NA_character_
    # Two distinct headings giving the same abbreviation: neither is used.
    short[short %in% short[duplicated(short)]] <- NA_character_
    for (h in names(groups)[!is.na(short)]) {
      for (i in groups[[h]]) {
        label[i] <- paste0(short[[h]], substring(full[i], sep_at[i]))
        used[[i]] <- rbind(used[[i]], data.frame(abbreviation = short[[h]], expansion = heading_expansion[[h]]))
      }
    }
  }

  # The supplied list also shortens any label still over the cap, whole words
  # only; a label that fits is left as written. Longer phrases go first so
  # "Left ventricular ejection fraction" wins over "Left ventricular".
  if (length(abbreviations)) {
    patterns <- paste0("(?<![[:alnum:]])", .regex_escape(names(abbreviations)), "(?![[:alnum:]])")
    # Spellings of one term share an abbreviation; the key names the term once,
    # by the expansion study_abbreviations() records, or else by the phrase.
    expansions <- attr(abbreviations, "expansion")
    if (length(expansions) != length(abbreviations)) expansions <- names(abbreviations)
    for (i in own[vapply(own, over, logical(1L))]) {
      # Replace one match at a time, leftmost first and the longest phrase at
      # that position, so overlapping phrases read the way the label does:
      # "Right coronary artery bypass graft" is "RCA bypass graft", not
      # "Right CABG". Search resumes after each replacement, so it ends.
      from <- 1L
      repeat {
        # Stop once the label fits: a fitting label is never abbreviated here.
        if (!over(i)) break
        best <- NULL
        for (k in seq_along(patterns)) {
          m <- gregexpr(patterns[k], label[i], ignore.case = TRUE, perl = TRUE)[[1L]]
          ok <- which(m >= from)
          if (!length(ok)) next
          start <- m[ok[1L]]
          len <- attr(m, "match.length")[ok[1L]]
          if (is.null(best) || start < best$start || (start == best$start && len > best$len)) {
            best <- list(start = start, len = len, k = k)
          }
        }
        if (is.null(best)) break
        short_form <- unname(abbreviations[[best$k]])
        # A word-like abbreviation (Preop) follows the case of the text it
        # replaces, so mid-sentence "preoperative" reads "preop"; initialisms
        # (LV, AVr, LVIDd) are written as the list spells them.
        if (grepl("^[A-Z][a-z]", short_form) && grepl("^[a-z]", substr(label[i], best$start, best$start))) {
          short_form <- paste0(tolower(substr(short_form, 1L, 1L)), substring(short_form, 2L))
        }
        label[i] <- paste0(substr(label[i], 1L, best$start - 1L), short_form,
                           substring(label[i], best$start + best$len))
        used[[i]] <- rbind(used[[i]], data.frame(abbreviation = short_form, expansion = expansions[best$k]))
        from <- best$start + nchar(short_form)
      }
    }
  }

  # Step 2: cut at a word boundary and mark the cut. Keep the uncut form: step
  # 3 works from it, so a heading abbreviated in step 1 stays abbreviated.
  uncut <- label
  long <- own[vapply(own, over, logical(1L))]
  label[long] <- .truncate_labels(label[long], label_max)
  cut[long] <- TRUE

  # A row collides when its label equals another row's while the full labels
  # differ; rows sharing one full label may share a display label.
  colliding <- function() {
    dup_label <- label %in% label[duplicated(label)]
    vapply(seq_len(n), function(i) dup_label[i] && any(label == label[i] & full != full[i]), logical(1L))
  }

  # Step 3: cut labels that collide keep both ends.
  again <- intersect(which(colliding()), which(cut))
  for (i in again) {
    # No shorter two-ended form: keep the cut, and let step 4 decide.
    both <- .truncate_both_ends(uncut[i], label_max)
    if (both != uncut[i] && nchar(both) <= label_max) label[i] <- both
  }

  # Step 4: give up the cap rather than the distinction. Restoring one label
  # can collide with another's shortened form, so repeat until none collide;
  # full labels are distinct, so this ends.
  over_cap <- rep(FALSE, n)
  repeat {
    hit <- intersect(which(colliding()), own)
    hit <- hit[label[hit] != full[hit]]
    if (!length(hit)) break
    label[hit] <- full[hit]
    cut[hit] <- FALSE
    used[hit] <- list(NULL)
    over_cap[hit] <- nchar(full[hit]) > label_max
  }

  # Keep only abbreviations the final label still shows: a two-ended cut can
  # drop the middle an abbreviation sat in.
  for (i in which(!vapply(used, is.null, logical(1L)))) {
    visible <- vapply(used[[i]]$abbreviation, function(a) {
      grepl(paste0("(?<![[:alnum:]])", .regex_escape(a), "(?![[:alnum:]])"), label[i], perl = TRUE)
    }, logical(1L))
    used[[i]] <- if (any(visible)) unique(used[[i]][visible, , drop = FALSE]) else NULL
  }
  shown <- do.call(rbind, c(list(none), used))
  shown <- unique(shown)
  rownames(shown) <- NULL
  list(label = label, truncated = cut & label != full, over_cap = over_cap, abbreviations = shown, by_row = used)
}

## Per-variable provenance: which abbreviations each key's label shows.
.abbreviations_by_key <- function(keys, by_row) {
  rows <- lapply(seq_along(by_row), function(i) {
    if (is.null(by_row[[i]])) NULL else data.frame(key = keys[i], by_row[[i]], stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, c(list(data.frame(key = character(), abbreviation = character(), expansion = character(),
                                          stringsAsFactors = FALSE)), rows))
  rownames(out) <- NULL
  out
}

## Keep label_full, truncated and the distinctness guarantee honest after an
## override. Without this the new label lands in `label`, uncapped, while
## `label_full` still shows the text it replaced -- a column that lies is worse
## than no column. The whole map is rebuilt, not just the changed rows,
## because whether a label collides depends on every other label.
.refresh_truncation <- function(map, keys) {
  if (!all(c("label_full", "truncated") %in% names(map))) {
    return(map)
  }
  label_max <- attr(map, "label_max")
  if (is.null(label_max)) {
    # A hand-built map carrying these columns; assume the documented default.
    label_max <- 40
  }
  idx <- which(map$key %in% keys)
  if (!length(idx)) {
    return(map)
  }
  map$label_full[idx] <- map$label[idx]
  # A row whose full text is its own key is a filled name, exempt from the cap.
  shown <- .display_labels(map$label_full, map$label_full == map$key, label_max,
                           .validate_abbreviations(attr(map, "abbreviation_list")))
  map$label <- shown$label
  map$truncated <- shown$truncated
  if ("over_cap" %in% names(map)) map$over_cap <- shown$over_cap
  attr(map, "abbreviations") <- shown$abbreviations
  attr(map, "abbreviations_by_key") <- .abbreviations_by_key(map$key, shown$by_row)
  map
}

## =============================================================================
#' Build a lookup map of data labels
#'
#' @description
#' Extracts variable labels from a labeled dataset and returns them as a
#' data frame with variable names (keys) and their corresponding labels.
#' This is particularly useful when working with SAS datasets that include
#' variable labels, or any dataset labeled with the \code{labelled} package.
#'
#' A warning is issued when more than 50\% of columns carry no label at all.
#' This typically indicates the data was imported from a source without labels
#' (e.g., plain CSV) and labels should be supplied via
#' \code{\link{add_labels}} or a \code{labels_overrides.yml} file (see
#' \code{\link{apply_label_overrides}}). A variable whose real label happens
#' to equal its own name does \strong{not} count towards the threshold: the
#' absent label is read as \code{NA} rather than filled, so the two cases are
#' distinguishable here even though \code{\link{proc_contents}} cannot tell
#' them apart.
#'
#' Labels longer than \code{label_max} are cut for display. The cut breaks on
#' a word boundary and is marked with \code{...}, and the source text is kept
#' in \code{label_full} - truncation is a view, not a change to the data.
#' \code{\link{dataset_schema}} deliberately has no such parameter: it records
#' the label as the source carried it, because a schema sidecar outlives the
#' source dataset.
#'
#' The variable-name fallback is \strong{exempt} from the cap. A name standing
#' in for a missing label passes through whole, however long, and
#' \code{truncated} is \code{FALSE}. A truncated name would match nothing in
#' the data and would read as a deliberately short label rather than as a
#' missing one, destroying the signal the fallback exists to give.
#'
#' \strong{Labels that differ stay different.} Cutting each label on its own
#' can make two labels identical once their distinguishing ends are cut off.
#' Within one map, labels that differ in \code{label_full} always differ in
#' \code{label}. Each step below runs only on labels still over the cap or
#' still colliding:
#' \enumerate{
#'   \item A heading, the text before the first \code{": "}, \code{" - "} or
#'     \code{"; "}, shared by two or more labels, one of them over the cap, is
#'     abbreviated in every label that carries it: to its entry in
#'     \code{abbreviations}, or else to the initials of its words, skipping
#'     small words such as "of" and "and". \code{"Surgical procedure"} becomes
#'     \code{"SP"}. A one-word heading is left alone, and two headings with the
#'     same initials are neither abbreviated.
#'   \item Any phrase in \code{abbreviations} is applied, whole words and
#'     ignoring case, to a label still over the cap. A label that fits is never
#'     abbreviated this way.
#'   \item The label is cut on a word boundary and marked.
#'   \item Cut labels that still collide keep both ends, \code{"Ascending aorta
#'     ... plus arch"}.
#'   \item A label that still collides is shown whole, over the cap, and
#'     \code{over_cap} marks it: a long label is a layout problem a reader can
#'     see, two identical labels a wrong figure nobody can.
#' }
#' The abbreviations actually shown come back as the \code{abbreviations}
#' attribute, to print as a key beneath a figure or table, and per variable as
#' the \code{abbreviations_by_key} attribute (\code{key}, \code{abbreviation},
#' \code{expansion}), so a key under one section can list only what that
#' section's labels use.
#'
#' @param data A data frame, tibble, or similar object with variable labels
#'   (typically created using the \code{labelled} package or imported from SAS).
#' @param label_max Maximum length of a displayed label, in characters,
#'   including the \code{...} marker. Defaults to 40, the historical
#'   convention. Must be at least 4, so that a cut always has room to be
#'   marked; use \code{Inf} or \code{NA} to disable truncation. Does not
#'   apply to a variable name filled in for a missing label.
#' @param abbreviations \code{NULL}, or a named character vector in which
#'   each name is a phrase and each value is that phrase's abbreviation:
#'   \code{c("Left ventricular" = "LV")}. Used only on labels over the cap, and
#'   for a shared heading in place of its initials. An \code{expansion}
#'   attribute, as \code{\link{study_abbreviations}} returns, names the term
#'   each abbreviation stands for in the key. A word-like abbreviation such as
#'   \code{"Preop"} takes the case of the text it replaces.
#'
#' @return A data frame with five columns, and an \code{abbreviations}
#'   attribute: a data frame of \code{abbreviation} and \code{expansion} for
#'   every abbreviation the labels show, with no rows when there are none.
#' \describe{
#'   \item{key}{Character vector of variable names from the input dataset}
#'   \item{label}{Character vector of labels fit to print: the variable label
#'     cut to \code{label_max}, or the variable's own name where the source
#'     carries no label}
#'   \item{label_full}{The label as the source carried it, never truncated,
#'     or the variable name where there is none}
#'   \item{truncated}{Logical: \code{TRUE} where \code{label} was cut from
#'     \code{label_full}. Always \code{FALSE} for a filled variable name.
#'     \code{subset(x, truncated)} is the report of what was cut}
#'   \item{over_cap}{Logical: \code{TRUE} where \code{label} is longer than
#'     \code{label_max} because every shorter form collided with another
#'     label. \code{subset(x, over_cap)} is the report}
#' }
#'
#' @seealso \code{\link{get_label}} for looking up a single label,
#'   \code{\link{add_labels}} for registering labels for derived variables,
#'   \code{\link{apply_label_overrides}} for applying study-specific overrides
#'   from a YAML file.
#'
#' @export
#'
#' @examples
#' # Generate labeled survival data
#' dta <- generate_survival_data(n = 50, seed = 42)
#' lmap <- label_map(dta)
#' head(lmap)
#'
#' # Use for publication-ready tables
#' summary_vars <- c("age", "bmi", "hgb_bs")
#' tbl <- data.frame(
#'   variable = summary_vars,
#'   description = lmap$label[match(summary_vars, lmap$key)],
#'   mean = sapply(dta[summary_vars], mean)
#' )
#' print(tbl)
#'
#' # With sample data (has labels)
#' dta <- sample_data(n = 20)
#' label_map(dta)
#'
#' # Which labels were cut, and what they were
#' subset(label_map(dta, label_max = 20), truncated)
#'
#' # Keep the source text
#' label_map(dta, label_max = Inf)
#'
#' # Labels sharing a heading keep what tells them apart, and the key says why
#' procs <- data.frame(avr = 1, mvr = 1)
#' attr(procs$avr, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
#' attr(procs$mvr, "label") <- "Surgical procedure: mitral valve repair"
#' lmap <- label_map(procs)
#' lmap$label
#' attr(lmap, "abbreviations")
label_map <- function(data, label_max = 40, abbreviations = NULL) {
  label_max <- .validate_label_max(label_max)
  abbreviations <- .validate_abbreviations(abbreviations)

  # null_action = "na" distinguishes a variable with no label from one whose
  # label happens to equal its name. "fill" cannot: both come back as the
  # name, and the fallback then has no way to exempt itself from the cap.
  declared <- as.character(
    labelled::var_label(data, unlist = TRUE, null_action = "na")
  )
  filled <- is.na(declared)
  full <- ifelse(filled, names(data), declared)

  shown <- .display_labels(full, filled, label_max, abbreviations)

  result <- data.frame(
    key = names(data),
    label = shown$label,
    label_full = full,
    truncated = shown$truncated,
    over_cap = shown$over_cap,
    stringsAsFactors = FALSE
  )
  rownames(result) <- NULL
  attr(result, "label_max") <- label_max
  attr(result, "abbreviation_list") <- abbreviations
  attr(result, "abbreviations") <- shown$abbreviations
  attr(result, "abbreviations_by_key") <- .abbreviations_by_key(result$key, shown$by_row)

  # Warn when most columns lack real labels
  if (nrow(result) > 0) {
    n_missing <- sum(filled)
    pct_missing <- n_missing / nrow(result)
    if (pct_missing > 0.5) {
      warning(
        sprintf(
          "%d of %d variables (%.0f%%) lack descriptive labels. ",
          n_missing, nrow(result), pct_missing * 100
        ),
        "Consider adding a labels_overrides.yml or using add_labels().",
        call. = FALSE
      )
    }
  }

  result
}

## =============================================================================
#' Look up the label for a single variable
#'
#' @description
#' Returns the descriptive label for one variable name from a label map.
#' This is a safer alternative to the manual \code{match()} pattern,
#' providing clear errors on typos and missing variables.
#'
#' @param label_map_df A data frame with \code{key} and \code{label} columns,
#'   as returned by \code{\link{label_map}}.
#' @param variable A single character string: the variable name to look up.
#'
#' @return A single character string: the label for the requested variable.
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 50, seed = 42)
#' lmap <- label_map(dta)
#'
#' get_label(lmap, "age")
#' get_label(lmap, "hgb_bs")
#'
#' # Use in plot titles
#' var <- "lvefvs_b"
#' plot(dta[[var]], main = get_label(lmap, var), ylab = get_label(lmap, var))
get_label <- function(label_map_df, variable) {
  if (!is.data.frame(label_map_df) ||
        !all(c("key", "label") %in% names(label_map_df))) {
    stop("label_map_df must be a data frame with 'key' and 'label' columns.",
         call. = FALSE)
  }
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string.", call. = FALSE)
  }

  idx <- match(variable, label_map_df$key)
  if (is.na(idx)) {
    stop(
      sprintf("Variable '%s' not found in label map.", variable),
      call. = FALSE
    )
  }
  label_map_df$label[idx]
}

## =============================================================================
#' Look up labels for multiple variables at once
#'
#' @description
#' A vectorized companion to \code{\link{get_label}}. Returns a named character
#' vector of labels for one or more variable names, making it convenient to
#' label axes, table columns, or multi-panel plots in a single call.
#'
#' Variables not found in the label map cause an error (just like
#' \code{get_label}), so typos are caught immediately.
#'
#' @param label_map_df A data frame with \code{key} and \code{label} columns,
#'   as returned by \code{\link{label_map}}.
#' @param variables A character vector of variable names to look up.
#'
#' @return A named character vector with names equal to \code{variables}
#'   and values equal to the corresponding labels.
#'
#' @seealso \code{\link{get_label}} for single-variable lookup,
#'   \code{\link{label_map}} to extract a label map from data.
#'
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 50, seed = 42)
#' lmap <- label_map(dta)
#'
#' # Look up several labels at once
#' get_labels(lmap, c("age", "bmi", "hgb_bs"))
#'
#' # Useful for table column headers
#' vars <- c("age", "bmi", "lvefvs_b")
#' headers <- get_labels(lmap, vars)
#' print(headers)
get_labels <- function(label_map_df, variables) {
  if (!is.data.frame(label_map_df) ||
        !all(c("key", "label") %in% names(label_map_df))) {
    stop("label_map_df must be a data frame with 'key' and 'label' columns.",
         call. = FALSE)
  }
  if (!is.character(variables) || length(variables) == 0L) {
    stop("'variables' must be a character vector with at least one element.",
         call. = FALSE)
  }

  idx <- match(variables, label_map_df$key)
  missing <- variables[is.na(idx)]
  if (length(missing) > 0L) {
    stop(
      sprintf(
        "Variable%s not found in label map: %s",
        if (length(missing) > 1L) "s" else "",
        paste0("'", missing, "'", collapse = ", ")
      ),
      call. = FALSE
    )
  }
  result <- label_map_df$label[idx]
  names(result) <- variables
  result
}

## =============================================================================
#' Add or update labels in a label map
#'
#' @description
#' Registers new labels in an existing label map, or applies labels directly
#' to a data frame's variable attributes. This is the recommended way to label
#' derived variables (e.g., ratios, binned groups, computed indices) that were
#' not present in the original imported dataset.
#'
#' When \code{label_map_df} is a label map (a data frame with \code{key} and
#' \code{label} columns), the map is updated and returned. When
#' \code{label_map_df} is a regular data frame (any data frame without the
#' label map structure), labels are applied directly to the data using
#' \code{labelled::var_label()}, which is the preferred approach because labels
#' travel with the data through \code{dplyr} operations.
#'
#' @param label_map_df A data frame with \code{key} and \code{label} columns
#'   (as returned by \code{\link{label_map}}), \strong{or} any data frame
#'   to which labels should be applied directly.
#' @param new_labels A named character vector where names are variable names
#'   and values are descriptive labels.
#'
#' @return When given a label map: the updated label map data frame.
#'   When given a data frame: the data frame with labels applied via
#'   \code{labelled::var_label()}.
#'
#' @seealso \code{\link{label_map}} to extract a label map from data,
#'   \code{\link{apply_label_overrides}} for bulk overrides from YAML.
#'
#' @export
#'
#' @examples
#' # --- Method 1: Update a label map (for reporting) ---
#' dta <- generate_survival_data(n = 50, seed = 42)
#' lmap <- label_map(dta)
#'
#' # Add labels for derived variables
#' lmap <- add_labels(lmap, c(
#'   age_group  = "Age Group (<40, 40-60, >60)",
#'   bsa_ratio  = "BSA Ratio",
#'   risk_score = "Composite Risk Score"
#' ))
#' tail(lmap, 4)
#'
#' # --- Method 2: Label a data frame directly (preferred) ---
#' dta$age_group <- cut(dta$age, breaks = c(0, 40, 60, Inf),
#'                      labels = c("<40", "40-60", ">60"))
#' dta <- add_labels(dta, c(age_group = "Age Group (<40, 40-60, >60)"))
#' labelled::var_label(dta$age_group)
add_labels <- function(label_map_df, new_labels) {
  if (!is.data.frame(label_map_df)) {
    stop("label_map_df must be a data frame.", call. = FALSE)
  }
  if (!is.character(new_labels) || is.null(names(new_labels))) {
    stop("new_labels must be a named character vector.", call. = FALSE)
  }

  is_label_map <- all(c("key", "label") %in% names(label_map_df))

  if (is_label_map) {
    # Update the label map data frame
    new_keys <- names(new_labels)
    existing <- new_keys %in% label_map_df$key
    if (any(existing)) {
      for (k in new_keys[existing]) {
        label_map_df$label[label_map_df$key == k] <- new_labels[[k]]
      }
    }
    if (any(!existing)) {
      new_rows <- data.frame(
        key = new_keys[!existing],
        label = unname(new_labels[!existing]),
        stringsAsFactors = FALSE
      )
      missing_cols <- setdiff(names(label_map_df), names(new_rows))
      if (length(missing_cols) > 0) {
        for (col in missing_cols) {
          new_rows[[col]] <- NA
        }
      }
      new_rows <- new_rows[names(label_map_df)]
      label_map_df <- rbind(label_map_df, new_rows)
    }
    return(.refresh_truncation(label_map_df, new_keys))
  }

  # Apply labels directly to the data frame via labelled
  for (nm in names(new_labels)) {
    if (nm %in% names(label_map_df)) {
      labelled::var_label(label_map_df[[nm]]) <- new_labels[[nm]]
    }
  }
  label_map_df
}

## =============================================================================
#' Apply label overrides from a YAML file
#'
#' @description
#' Reads label overrides from a YAML file and applies them to a label map
#' \strong{or} directly to a data frame. This allows study-specific label
#' replacements (e.g., abbreviations, corrections) to be configured
#' externally rather than hard-coded in analysis scripts.
#'
#' The YAML file should contain a simple mapping of variable names to labels.
#' If the file does not exist, the input is returned unchanged --- making
#' it safe to call unconditionally in shared code.
#'
#' When \code{data} is a label map (a data frame with \code{key} and
#' \code{label} columns), the overrides are applied to the map. When
#' \code{data} is any other data frame, labels are applied directly to
#' the data via \code{\link{add_labels}}, which is the preferred
#' data-first workflow.
#'
#' @param data A data frame: either a label map (with \code{key} and
#'   \code{label} columns, as returned by \code{\link{label_map}}), or any
#'   data frame whose columns should be labeled directly.
#' @param overrides_file Path to a YAML file containing label overrides.
#'   Defaults to \code{"labels_overrides.yml"} in the current working directory.
#'
#' @return When given a label map: the updated label map data frame.
#'   When given a data frame: the data frame with labels applied via
#'   \code{labelled::var_label()}.
#'   In both cases, variables not mentioned in the YAML file are left
#'   unchanged.
#'
#' @details
#' The YAML file format is a simple mapping of variable names to labels:
#'
#' \preformatted{
#' age_binned: "Age Group"
#' bsa_ratio: "BSA Ratio"
#' cavv_area: "Common AVV Area"
#' }
#'
#' This design keeps study-specific label customizations in configuration
#' rather than code. Each study gets its own \code{labels_overrides.yml}
#' alongside its \code{config.yml}, and shared helper functions never contain
#' hard-coded replacements.
#'
#' @seealso \code{\link{add_labels}} for programmatic label updates,
#'   \code{\link{label_map}} for extracting labels from data.
#'
#' @export
#'
#' @examples
#' # Create a temporary YAML overrides file
#' tmp <- tempfile(fileext = ".yml")
#' writeLines(c(
#'   "age: 'Patient Age (years)'",
#'   "bsa_ratio: 'Body Surface Area Ratio'"
#' ), tmp)
#'
#' # --- On a label map ---
#' dta <- generate_survival_data(n = 50, seed = 42)
#' lmap <- label_map(dta)
#' lmap <- apply_label_overrides(lmap, overrides_file = tmp)
#' lmap[lmap$key == "age", ]
#'
#' # --- Directly on data (preferred) ---
#' dta <- apply_label_overrides(dta, overrides_file = tmp)
#' labelled::var_label(dta$age)
#'
#' unlink(tmp)
apply_label_overrides <- function(data,
                                  overrides_file = "labels_overrides.yml") {
  if (!is.data.frame(data)) {
    stop("'data' must be a data frame (either a label map or a dataset).",
         call. = FALSE)
  }

  if (!file.exists(overrides_file)) {
    return(data)
  }

  overrides <- yaml::read_yaml(overrides_file)

  if (!is.list(overrides) || length(overrides) == 0) {
    return(data)
  }

  # Convert to named character vector and apply via add_labels
  override_vec <- vapply(overrides, as.character, character(1))
  add_labels(data, override_vec)
}

## =============================================================================
#' Apply label overrides from a YAML file (deprecated)
#'
#' @description
#' \strong{Deprecated.} Use \code{\link{apply_label_overrides}()} instead.
#' \code{clean_labels()} has been renamed for clarity. This function is
#' kept as an alias for backward compatibility.
#'
#' @param label_map_df A data frame (label map or dataset) passed to
#'   \code{\link{apply_label_overrides}}.
#' @param overrides_file Path to a YAML file containing label overrides.
#'   Defaults to \code{"labels_overrides.yml"}.
#'
#' @inherit apply_label_overrides return
#'
#' @export
#'
#' @examples
#' # Use apply_label_overrides() instead
#' tmp <- tempfile(fileext = ".yml")
#' writeLines("age: 'Patient Age (years)'", tmp)
#'
#' library(labelled)
#' dta <- data.frame(age = c(25, 30, 35))
#' var_label(dta$age) <- "Patient Age"
#' lmap <- label_map(dta)
#'
#' lmap <- clean_labels(lmap, overrides_file = tmp)
#' unlink(tmp)
clean_labels <- function(label_map_df,
                         overrides_file = "labels_overrides.yml") {
  .Deprecated(
    "apply_label_overrides",
    package = "hvtiRutilities",
    msg = "clean_labels() is deprecated; use apply_label_overrides() instead."
  )
  apply_label_overrides(label_map_df, overrides_file = overrides_file)
}
