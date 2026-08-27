#' Levels of a column that are not clean integers
#'
#' @description
#' On a mean-imputed column these are the imputed value, which is the signature
#' that imputation happened at all: a genuine 0/1 indicator has no such level.
#'
#' @param x A vector or factor.
#'
#' @return A character vector of the offending levels, possibly empty.
#'
#' @seealso \code{\link{covariate_audit}}
#'
#' @export
#'
#' @examples
#' imputed_levels(c(0, 1, 0.714047, 1))
imputed_levels <- function(x) {
  lv  <- if (is.factor(x)) levels(x) else unique(as.character(x[!is.na(x)]))
  num <- suppressWarnings(as.numeric(lv))
  lv[!is.na(num) & abs(num - round(num)) > 1e-9]
}

#' Audit what would happen to each covariate in a model
#'
#' @description
#' Reports, one row per variable, what a column is and what using it as a model
#' covariate would do to it -- so a job can \strong{report} the decision rather
#' than
#' make it silently.
#'
#' @details
#' \strong{The problem this exists for.} \code{vars.sas} is commonly called as
#' \code{\%vars(missing=1, impute=1)}, which mean-imputes missing values and
#' adds a
#' paired \code{ms_*} missing indicator. So a 0/1 clinical variable arrives
#' carrying
#' three distinct values: 0, 1, and the cohort mean. One real example:
#' \code{hx_htn}'s third value is 0.714047, the prevalence of hypertension, not
#' any
#' patient's hypertension status.
#'
#' In SAS these columns are numeric and enter a model \strong{linearly}: an
#' imputed
#' row contributes the mean, and the \code{ms_*} indicator carries whatever the
#' missingness itself is worth. That is the design the \code{.sas} job
#' specifies.
#'
#' Read into R they arrive as \strong{factors}. Put a factor in a model formula
#' and
#' \code{model.matrix()} builds dummies from it, which makes "this value was
#' imputed"
#' its own category with its own coefficient. \strong{That is a different model,
#' with
#' a different parameter count, and nothing in the output says so.} Multi-level
#' counts have the same problem for a different reason: a \code{surg_num} with
#' levels
#' 1, 2, 3, 4 is a number of previous operations, not four unordered categories.
#'
#' \code{max_levels} bounds where an imputed value is looked for at all. On a
#' \strong{continuous} covariate every value is its own level and most are
#' non-integers, so an unbounded search returns the whole column.
#'
#' That bound is also an honest statement of the limit. Mean imputation
#' \emph{is}
#' detectable in a discrete column, because the mean is not a value the column
#' can legitimately take. In a continuous column it is invisible by construction
#' -- an imputed mean looks exactly like a measured value -- and the paired
#' \code{ms_*}
#' indicator is the only record that it happened. So \code{NA} in
#' \code{noninteger_levels} means \strong{"not knowable here"}, not "none".
#'
#' @param data A data frame.
#' @param vars Character vector of covariate names.
#' @param max_levels Integer. Columns with more distinct values than this are
#' treated as continuous and their non-integer levels are reported as \code{NA}.
#'
#' @return A data frame with columns \code{variable}, \code{storage},
#'   \code{n_levels},
#' \code{noninteger_levels} and \code{action}. \code{noninteger_levels} reports
#' \code{value (rows)} \strong{per level}: per level rather than as a total
#' because the
#'   total cannot distinguish a mean-imputed binary (one such level, in a
#'   minority of rows) from an inverse transformation whose several non-integer
#' levels are ordinary data. A blank means "no such level"; \code{NA} means "not
#' looked for". \code{action} is what \code{\link{covariates_to_numeric}} would
#' do, and an
#' \code{action} beginning \code{ERROR} marks a variable that must not be
#' fitted.
#'
#' @seealso \code{\link{covariates_to_numeric}}, \code{\link{imputed_levels}}
#'
#' @export
#'
#' @examples
#' d <- data.frame(hx_htn = factor(c("0", "1", "0.714047")),
#'                 age = c(60, 71, 55))
#' covariate_audit(d, c("hx_htn", "age"))
covariate_audit <- function(data, vars, max_levels = 12L) {
  vars <- unique(vars)
  do.call(rbind, lapply(vars, function(v) {
    if (!v %in% names(data)) {
      return(data.frame(variable = v,
                        storage = "absent",
                        n_levels = NA_integer_,
                        noninteger_levels = NA_character_,
                        action = "ERROR: not in the data",
                        stringsAsFactors = FALSE))
    }
    col <- data[[v]]
    lv  <- if (is.factor(col)) {
      levels(col)
    } else {
      unique(as.character(col[!is.na(col)]))
    }
    discrete <- length(lv) <= max_levels
    imp <- if (discrete) imputed_levels(col) else character(0)
    numeric_like <- !any(is.na(suppressWarnings(as.numeric(lv))))
    action <- if (!is.factor(col)) {
      "left as numeric"
    } else if (numeric_like) {
      "factor -> numeric, enters linearly"
    } else {
      "ERROR: factor with non-numeric levels"
    }
    counts <- vapply(imp, function(l) sum(as.character(col) == l, na.rm = TRUE),
                     integer(1))
    noninteger <- if (!discrete) {
      NA_character_
    } else if (!length(imp)) {
      ""
    } else {
      paste(sprintf("%s (%d)", signif(as.numeric(imp), 6), counts),
            collapse = ", ")
    }
    data.frame(variable = v, storage = class(col)[1], n_levels = length(lv),
               noninteger_levels = noninteger, action = action,
               stringsAsFactors = FALSE)
  }))
}

#' Apply what covariate_audit() reports
#'
#' @description
#' Factors whose levels are all numeric become numeric, so they enter a model
#' linearly the way the SAS job specifies.
#'
#' A factor with a genuinely non-numeric level is \strong{left alone} and will
#' be
#' dummy-coded -- the right outcome for a real categorical, and the wrong one
#' for
#' a mean-imputed binary. \code{\link{covariate_audit}}'s \code{action} column
#' is where a
#' reader sees which of the two happened; check it before reading any
#' coefficient.
#'
#' @param data A data frame.
#' @param vars Character vector of covariate names.
#'
#' @return \code{data}, with the convertible columns coerced to numeric.
#'
#' @seealso \code{\link{covariate_audit}}
#'
#' @export
#'
#' @examples
#' d <- data.frame(hx_htn = factor(c("0", "1", "0.714047")))
#' str(covariates_to_numeric(d, "hx_htn"))
covariates_to_numeric <- function(data, vars) {
  for (v in intersect(unique(vars), names(data))) {
    col <- data[[v]]
    if (!is.factor(col)) next
    lv <- levels(col)
    if (any(is.na(suppressWarnings(as.numeric(lv))))) next
    data[[v]] <- as.numeric(as.character(col))
  }
  data
}

#' Candidate pairs carrying the same information under unrelated names
#'
#' @description
#' \strong{What this catches that pruning cannot.} \code{\link{concept_map}}
#' groups
#' \emph{transformations}, by stripping a known affix and finding the parent.
#' Two
#' candidates that are numerically the same information but share no affix
#' relationship are invisible to it.
#'
#' \code{male} and \code{female} are the case that got through a real screen:
#' exact
#' complements, both offered, and 101 of 500 replicates selected \strong{both}.
#' With
#' a free \code{log_mu} a design holding both is singular, so those replicates
#' were
#' fitting a rank-deficient model and nothing in the output said so.
#'
#' @details
#' \strong{Run it on the pool actually screened, after pruning.} On an unpruned
#' pool
#' every \code{ln_x} correlates with its own \code{x} at ~1 and the report is a
#' wall of
#' expected pairs. After pruning, anything flagged is something pruning could
#' not catch, which is exactly the set a human needs to look at.
#'
#' \code{complement} separates the two cases a reader treats differently: an
#' exact
#' complement (\code{x + y == 1}) is a coding duplicate and one of the pair
#' should
#' simply not be a candidate, while a high correlation between genuinely
#' different measurements is a judgement call about what the model can identify.
#'
#' @param data A data frame holding the candidate columns.
#' @param pool Character vector of candidate names.
#' @param threshold Absolute correlation at or above which a pair is reported.
#'
#' @return A data frame with columns \code{var1}, \code{var2}, \code{r} and
#'   \code{complement},
#' ordered by decreasing \code{abs(r)}. Empty when the pool is clean, so the
#' caller
#'   decides whether to warn, fail, or print it.
#'
#' @seealso \code{\link{concept_map}}, \code{\link{prune_to_one_form}}
#'
#' @export
#'
#' @examples
#' d <- data.frame(male = c(1, 0, 1, 0), female = c(0, 1, 0, 1),
#'                 age = c(60, 71, 55, 68))
#' pool_collinear_pairs(d, c("male", "female", "age"))
pool_collinear_pairs <- function(data, pool, threshold = 0.99) {
  empty <- data.frame(var1 = character(0), var2 = character(0),
                      r = numeric(0), complement = logical(0),
                      stringsAsFactors = FALSE)

  vars <- intersect(unique(pool), names(data))
  if (length(vars) < 2L) return(empty)
  vars <- vars[vapply(data[vars], is.numeric, logical(1))]
  # A constant column has no correlation to report and would give NA.
  vars <- vars[vapply(data[vars], function(x) {
    length(unique(x[!is.na(x)])) > 1L
  }, logical(1))]
  if (length(vars) < 2L) return(empty)

  m <- suppressWarnings(stats::cor(data[vars], use = "pairwise.complete.obs"))
  hits <- which(abs(m) >= threshold & upper.tri(m), arr.ind = TRUE)
  if (!nrow(hits)) return(empty)

  out <- do.call(rbind, lapply(seq_len(nrow(hits)), function(i) {
    a <- vars[hits[i, "row"]]
    b <- vars[hits[i, "col"]]
    x <- data[[a]]
    y <- data[[b]]
    ok <- !is.na(x) & !is.na(y)
    data.frame(var1 = a, var2 = b,
               r = unname(m[hits[i, "row"], hits[i, "col"]]),
               complement = all(x[ok] + y[ok] == 1),
               stringsAsFactors = FALSE)
  }))
  out[order(-abs(out$r), out$var1, out$var2), ]
}
