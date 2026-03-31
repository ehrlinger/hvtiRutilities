## =============================================================================
#' Build a lookup map of data labels
#'
#' @description
#' Extracts variable labels from a labeled dataset and returns them as a
#' data frame with variable names (keys) and their corresponding labels.
#' This is particularly useful when working with SAS datasets that include
#' variable labels, or any dataset labeled with the \code{labelled} package.
#'
#' A warning is issued when more than 50\% of columns lack descriptive labels
#' (i.e., the label is identical to the variable name). This typically indicates
#' the data was imported from a source without labels (e.g., plain CSV) and
#' labels should be supplied via \code{\link{add_labels}} or a
#' \code{labels_overrides.yml} file (see \code{\link{apply_label_overrides}}).
#'
#' @param data A data frame, tibble, or similar object with variable labels
#'   (typically created using the \code{labelled} package or imported from SAS).
#'
#' @return A data frame with two columns:
#' \describe{
#'   \item{key}{Character vector of variable names from the input dataset}
#'   \item{label}{Character vector of variable labels. For unlabeled variables,
#'     the variable name is used as the label (due to \code{null_action = "fill"})}
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
label_map <- function(data) {
  result <- data.frame(
    key = names(data),
    label = data |>
      labelled::var_label(
        unlist = TRUE,
        null_action = "fill"
      ),
    stringsAsFactors = FALSE
  )

  # Warn when most columns lack real labels (key == label)
  if (nrow(result) > 0) {
    n_missing <- sum(result$key == result$label)
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
    return(label_map_df)
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
