#' Affix conventions for grouping a SAS candidate pool into concepts
#'
#' @description
#' Defaults for \code{\link{concept_of}}, \code{\link{concept_map}} and friends,
#' describing the
#' naming conventions a legacy \code{vars.sas} uses: \code{ln_} (log),
#' \code{in_} (inverse),
#' \code{in2} (inverse squared) and a trailing \code{2} (squared).
#'
#' \code{POOL_PLAIN_SUFFIX} is the suffix untransformed measurements carry
#' (\code{crcl_pr}, \code{bun_pr}, \code{hct_pr}). \code{POOL_MIN_STEM} guards
#' the prefix rule: two
#' characters would match half a pool by accident.
#'
#' These are \strong{defaults, not constants} -- pass your study's own
#' conventions
#' through the \code{affixes}, \code{plain_suffix} and \code{min_stem} arguments
#' where they
#' differ, rather than editing a copy of this package.
#'
#' @format Character vectors, and an integer for \code{POOL_MIN_STEM}.
#' @rdname pool_conventions
#' @export
POOL_AFFIXES <- c("^ln_", "^in2", "^in_", "2$")

#' @rdname pool_conventions
#' @export
POOL_PLAIN_SUFFIX <- "_pr"

#' @rdname pool_conventions
#' @export
POOL_MIN_STEM <- 3L

# TRUE when a name is itself a derived form. Used to keep the prefix rule from
# electing a sibling (`effi2`) as the concept its own siblings group under.
.pool_is_derived <- function(x, affixes) {
  any(vapply(affixes, function(a) grepl(a, x), logical(1)))
}

#' The concept a candidate variable belongs to
#'
#' @description
#' A SAS candidate pool offers every transformation of a variable as a separate
#' candidate: \code{age}, \code{ln_age}, \code{in_age}, \code{age2} and
#' \code{agee} all compete. A
#' stepwise screen then spends its steps on them, and a per-variable selection
#' frequency reports each form separately. On one real screen five forms of age
#' each cleared 80\% while the retained set collapsed to four distinct clinical
#' concepts -- and the paper the job comes from reports \strong{concepts}.
#'
#' @details
#' \strong{The rule is deliberately conservative.} A variable joins a concept
#' only
#' when stripping one known affix yields a name that is \emph{itself} in the
#' pool (or
#' that name plus \code{plain_suffix}). So \code{zexp2} groups under \code{zexp}
#' because \code{zexp}
#' is a candidate, and \code{ln_crcl} groups under \code{crcl_pr} because that
#' is the
#' plain form present. A name whose stem is absent stays its own concept:
#' \code{agee} does not join \code{age}, because no rule strips a trailing
#' \code{e}.
#'
#' Grouping too little costs some pruning. Grouping too much \strong{silently
#' merges
#' two clinical concepts and discards a real candidate}, which is the error
#' that cannot be seen in the output. The rule errs the safe way, and callers
#' are expected to report the map so a human can check it.
#'
#' \strong{Two mechanisms are needed, and only one can be mechanical.}
#' \code{vars.sas}
#' truncates the stem when it names a derivative, so stripping the affix yields
#' a name absent by exact match:
#'
#' \itemize{
#' \item \emph{Truncation} -- \code{effi} is a \strong{prefix} of \code{effic},
#' so it can be found.
#'   Handled automatically, but only when the stem prefixes exactly one pool
#'   member that is not itself a derived form, and only when the stem is at
#'   least \code{min_stem} characters. Ambiguity declines to group rather than
#'   guessing.
#' \item \emph{Contraction} -- \code{arin} is not a prefix of \code{area_int}
#' and no rule can find
#'   it. Declare it via \code{aliases}, so the judgement is recorded in the job
#'   rather than inferred by the function.
#' }
#'
#' Left ungrouped on a real screen, \code{effic} at 86.4\% and \code{ln_effi} at
#' 60.8\% were
#' both reported as retained risk factors at r = 0.9988, and \code{in_arin} at
#' 70.6\%
#' hid a concept whose union across its forms was 86.4\%.
#'
#' @section A permanent compatibility layer, not a temporary shim:
#' Stem truncation exists because SAS capped variable names at 8 characters. A
#' modern builder has no such cap and a pool built that way needs none of this,
#' because \code{ln_efficiency} strips cleanly to \code{efficiency}.
#'
#' But the two regimes coexist indefinitely: reproducing a legacy SAS job in R
#' is routine work, not a migration with an end date, so truncated pools keep
#' arriving from \code{built*.sas7bdat} extracts for as long as old jobs are
#' re-run.
#' \strong{Do not delete the prefix rule or the alias table when a new builder
#' ships.} They are how a legacy pool is read. The right expectation is that
#' new datasets simply never need them.
#'
#' @param v Character scalar: the variable name.
#' @param pool Character vector: the candidate pool \code{v} belongs to.
#' @param affixes Character vector of regular expressions for the study's
#'   transformation affixes. See \code{\link{POOL_AFFIXES}}.
#' @param plain_suffix Suffix carried by untransformed measurements.
#' @param aliases Named character vector, \code{c(variable = concept)},
#'   declaring groupings no affix rule can reach. An alias on the variable
#'   itself wins
#'   over every rule: it is the study saying so directly.
#' @param min_stem Minimum stem length before the prefix rule is tried.
#'
#' @return A character scalar: the concept, or \code{v} itself when no rule
#'   applies.
#'
#' @seealso \code{\link{concept_map}}, \code{\link{prune_to_one_form}},
#'   \code{\link{selection_crowding}}
#'
#' @export
#'
#' @examples
#' pool <- c("age", "ln_age", "age2", "agee")
#' vapply(pool, concept_of, character(1), pool = pool)
concept_of <- function(v, pool,
                       affixes = POOL_AFFIXES,
                       plain_suffix = POOL_PLAIN_SUFFIX,
                       aliases = character(0),
                       min_stem = POOL_MIN_STEM) {
  # An alias on the variable itself wins over every rule: it is the study
  # saying so directly, for forms no affix rule can reach.
  if (v %in% names(aliases)) return(unname(aliases[[v]]))

  for (a in affixes) {
    if (!grepl(a, v)) next
    stem <- sub(a, "", v)
    if (!nzchar(stem)) next
    if (stem %in% pool) return(stem)
    withpr <- paste0(stem, plain_suffix)
    if (withpr %in% pool) return(withpr)
    if (stem %in% names(aliases)) return(unname(aliases[[stem]]))

    # Truncated stem. Candidates are pool members this stem prefixes, minus
    # the variable itself and minus anything that is a derived form, so a
    # sibling cannot be elected the concept.
    if (nchar(stem) >= min_stem) {
      cand <- pool[startsWith(pool, stem) & pool != v]
      if (length(cand)) {
        cand <- cand[!vapply(cand, .pool_is_derived, logical(1),
                             affixes = affixes)]
      }
      if (length(cand) == 1L) return(cand)
    }
  }
  v
}

#' Map a candidate pool to concepts
#'
#' @description
#' One row per candidate: which concept it belongs to, and whether it is that
#' concept's representative. Returned rather than applied, so a caller can put
#' the map in its report \strong{before} anything is discarded.
#'
#' @details
#' \code{prefer} overrides which form represents a concept, as \code{c(concept =
#' variable)}. \strong{The default is a modelling assumption, not a neutral
#' choice:}
#' keeping the plain form asserts the effect is linear in it. Measured on one
#' study, \code{ln_crcl} selected in 43.8\% of replicates against 18.0\% for
#' \code{crcl_pr}, so defaulting to the plain form would have \emph{lowered} a
#' genuine
#' risk factor's frequency. Override where the study has a view; the map goes
#' into the report either way, so the choice is visible rather than implied.
#'
#' @param pool Character vector of candidate names.
#' @param prefer Named character vector \code{c(concept = variable)}.
#' @param aliases Named character vector, as for \code{\link{concept_of}}.
#' @param ... Passed to \code{\link{concept_of}}.
#'
#' @return A data frame with columns \code{variable}, \code{concept} and
#'   \code{representative}, ordered by concept with the representative first.
#'
#' @seealso \code{\link{concept_of}}, \code{\link{prune_to_one_form}}
#'
#' @export
#'
#' @examples
#' concept_map(c("age", "ln_age", "age2", "agee"))
concept_map <- function(pool, prefer = character(0),
                        aliases = character(0), ...) {
  pool <- unique(pool)

  # An alias pointing outside the pool would silently group nothing, or group
  # under a name the screen never sees. Refuse, naming the offender.
  bad <- setdiff(unname(aliases), pool)
  if (length(bad)) {
    stop("concept_map(): aliases point at ", paste(bad, collapse = ", "),
         ", which are not in the pool. An alias must name a candidate the ",
         "screen will actually be offered.", call. = FALSE)
  }

  con  <- vapply(pool, concept_of, character(1), pool = pool,
                 aliases = aliases, ...)
  out  <- data.frame(variable = pool, concept = unname(con),
                     row.names = NULL, stringsAsFactors = FALSE)

  # A preference naming a variable that is not in its own concept group would
  # silently keep nothing, or keep a member of a different concept. Refuse.
  for (k in names(prefer)) {
    grp <- out$variable[out$concept == k]
    if (!length(grp)) {
      stop("concept_map(): prefer names concept '", k,
           "', which no candidate belongs to.", call. = FALSE)
    }
    if (!prefer[[k]] %in% grp) {
      stop("concept_map(): prefer asks to keep '", prefer[[k]],
           "' for concept '", k, "', but that concept contains only: ",
           paste(grp, collapse = ", "), ".", call. = FALSE)
    }
  }

  rep_of <- ifelse(out$concept %in% names(prefer),
                   unname(prefer[out$concept]), out$concept)
  out$representative <- out$variable == rep_of
  out[order(out$concept, !out$representative, out$variable), ]
}

#' Prune a candidate pool to one form per concept
#'
#' @param pool Character vector of candidate names.
#' @param ... Passed to \code{\link{concept_map}}.
#'
#' @return The kept names, in the pool's original order, so the scope handed to
#'   a screen stays stable across runs.
#'
#' @seealso \code{\link{concept_map}}, \code{\link{pool_collinear_pairs}}
#'
#' @export
#'
#' @examples
#' prune_to_one_form(c("age", "ln_age", "age2", "bsa"))
prune_to_one_form <- function(pool, ...) {
  m <- concept_map(pool, ...)
  keep <- m$variable[m$representative]
  pool[pool %in% keep]
}

#' Concepts represented more than once among selected covariates
#'
#' @description
#' \code{\link{concept_map}} and \code{\link{prune_to_one_form}} act on a
#' candidate pool \strong{before}
#' a screen. This is the after-the-fact view, and it is the only one available
#' for a job run without pruning -- which is the case for any faithful
#' reproduction of a SAS \code{\%macro model}, since SAS had no notion of a
#' concept.
#'
#' @details
#' \strong{Why it is worth reporting.} A step budget is shared: \code{max_steps}
#' caps
#' total steps across both phases. So a slot spent on a second form of a concept
#' already in the model is a slot no other variable could have. When the
#' selection also stopped \emph{on} the cap, the two facts together say the
#' model is
#' not merely budget-limited but budget-limited \strong{by redundancy} -- and
#' neither
#' fact is visible in a coefficient table.
#'
#' Grouping is \code{\link{concept_map}}'s, so it is conservative by
#' construction.
#' Under-grouping only understates crowding; over-grouping would assert two
#' clinical concepts are one. This errs the safe way, and the result is a
#' \strong{floor}: a concept nobody listed is still counted as separate
#' variables.
#'
#' \code{selected} is phase-qualified, as \code{setdiff(names(coef(sel)),
#' names(coef(base)))} returns it: \code{"late.age"}, \code{"early.zexp2"}.
#' Phases are
#' counted separately -- one form of age in each phase is two slots but not a
#' crowded concept.
#'
#' @param selected Character vector of phase-qualified selected parameter names.
#' @param aliases Named character vector, as for \code{\link{concept_of}}.
#'   Only those
#'   whose target was selected in a given phase are forwarded, because
#' \code{\link{concept_map}} refuses an alias pointing outside its pool -- right
#' for a
#'   \emph{candidate} pool, wrong here, where a parent form may legitimately be
#'   absent (\code{in_arin} can be selected while \code{area_int} is not).
#' @param ... Passed to \code{\link{concept_map}}.
#'
#' @return A data frame with columns \code{phase}, \code{concept},
#'   \code{n_forms} and \code{forms},
#' ordered by phase then decreasing \code{n_forms}. Empty when nothing is
#' crowded.
#'
#' @seealso \code{\link{concept_map}}, \code{\link{prune_to_one_form}}
#'
#' @export
#'
#' @examples
#' selection_crowding(c("early.age", "early.ln_age", "late.bsa"))
selection_crowding <- function(selected, aliases = character(0), ...) {
  empty <- data.frame(phase = character(0), concept = character(0),
                      n_forms = integer(0), forms = character(0),
                      stringsAsFactors = FALSE)
  if (!length(selected)) return(empty)

  ph  <- sub("[.].*$", "", selected)
  var <- sub("^[^.]*[.]", "", selected)

  out <- do.call(rbind, lapply(unique(ph), function(p) {
    v  <- var[ph == p]
    al <- aliases[unname(aliases) %in% v]
    cm <- concept_map(v, aliases = al, ...)
    cm <- cm[cm$concept %in% cm$concept[duplicated(cm$concept)], , drop = FALSE]
    if (!nrow(cm)) return(NULL)
    do.call(rbind, lapply(split(cm, cm$concept), function(x) {
      data.frame(phase   = p,
                 concept = x$concept[1],
                 n_forms = nrow(x),
                 forms   = paste(sort(x$variable), collapse = ", "),
                 stringsAsFactors = FALSE)
    }))
  }))

  if (is.null(out)) return(empty)
  rownames(out) <- NULL
  out[order(out$phase, -out$n_forms), ]
}
