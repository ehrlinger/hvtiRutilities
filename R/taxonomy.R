#' Analysis prefix taxonomy
#'
#' The prefix system inherited from the original CORR analysis binder. The
#' prefix encodes both the type of analysis and the folder the job belongs in.
#'
#' This is data rather than documentation on purpose. The same table lived in a
#' README and drifted from the files it described; as a function it is checked
#' by the test suite against the templates actually present.
#'
#' \strong{Both folder order and row order within a folder are still
#' load-bearing. Coordinate any change with \code{hvtiRtemplates}.}
#'
#' A template's ordinal takes its major from a hardcoded folder map, so adding
#' or reordering a \emph{folder} renumbers templates.
#'
#' The minor is subtler than it was. It is no longer \emph{derived} from row
#' position: as of \code{hvtiRtemplates} v1.0.15 it is assigned once, recorded
#' in \code{dev/specs/artifacts/2026-08-29-template-roadmap.json} and never
#' recomputed, because an ordinal is an identity rather than a position. But
#' that package's \code{tests/testthat/test-taxonomy.R} still \emph{asserts}
#' that within-folder ordinal order matches the row order here, so reordering
#' rows turns its CI red even though no number is recomputed. The two guards
#' disagree; until that test is retired, treat row order as fixed.
#'
#' The check compares only prefixes that have a template on disk, so inserting
#' a row for an untemplated prefix is safe. What is not safe is changing the
#' relative order of two \emph{templated} prefixes in one folder.
#'
#' Why this is worth the caution: the coupling has already failed once, in this
#' package's direction. Moving \code{hs} out of \code{analyses} in 1.1.6 shifted
#' \code{bh} from sixth to fifth while its shipped filename stayed
#' \code{04.06}, and nothing caught it -- the ledger checks verify format,
#' folder-major and uniqueness, never position. \code{bh} was renumbered to
#' \code{04.05} and \code{04.06} retired rather than freed, because it shipped.
#'
#' \strong{\code{hs} is filed under \code{graphs}, which reads oddly for a job
#' named "setup".} It was moved there from \code{analyses} on 2026-08-29 on the
#' corpus rather than on the name: all ten \code{tp.hs.*} templates in the SAS
#' library and ten of the eleven R \code{hs} jobs in \code{/studies} sit in
#' \code{graphs/}. It computes patient-level predictions that the plotting jobs
#' beside it consume, in the \code{setup} / \code{uses_setup} pairing the
#' corpus uses throughout. See
#' \code{hvtiRtemplates:dev/specs/2026-08-29-hs-template-design.md}.
#'
#' \code{folder} names two different things. For most rows it is the analysis
#' type's home folder, matched to a job prefix. One row, \code{estimates}, is an
#' artifact kind rather than a job type: it holds serialized fits and cached
#' results written by one job and read by a later one in the same set, and no
#' analysis produces it directly. That row's \code{prefix} is \code{NA}, not a
#' string, because there is no prefix to assign it.
#'
#' @return A data frame with columns \code{prefix}, \code{name}, \code{folder},
#'   \code{description}. \code{prefix} is \code{NA} for the one row that names
#'   an artifact kind rather than an analysis type.
#' @export
#' @examples
#' head(hvti_taxonomy())
hvti_taxonomy <- function() {
  tx <- rbind.data.frame(
    c("bd",    "Build",                     "datasets",      "assembles raw sources into the analytic dataset"),
    c("vars",  "Variables",                 "datasets",      "macro enhancing the dataset with temp vars, imputations, propensity"),
    c("dt",    "Data check",                "datasets",      "initial QC of the build dataset"),
    c("dc",    "Descriptive",               "descriptive",   "Table 1s, covariate summaries, balance tables"),
    c("lg",    "Logit trends",              "descriptive",   "variable transformation and linearity checks"),
    c("rg",    "Regression trends",         "descriptive",   "trend checks for continuous and polytomous outcomes"),
    c("ac",    "Actuarial",                 "distributions", "Kaplan-Meier / non-parametric life table"),
    c("hz",    "Hazard fit",                "distributions", "fits the underlying hazard distribution"),
    c("cd",    "Cumulative distribution",   "distributions", "cumulative distribution plots; follow-up summaries"),
    c("nd",    "Nonparametric distributions", "distributions", "distribution estimates stratified by group"),
    c("hm",    "Hazard model",              "analyses",      "risk factor analysis; builds on the HZ fit"),
    c("mm",    "Mixed model",               "analyses",      "continuous repeated-measures longitudinal analysis"),
    c("gm",    "Generalized model",         "analyses",      "repeated-measures ordinal / count models"),
    c("lm",    "Logistic model",            "analyses",      "logistic regression; propensity score development"),
    c("bh",    "Bootstrap hazard",          "analyses",      "bootstrap variable selection or fixed-set hazard models"),
    c("bl",    "Bootstrap logistic",        "analyses",      "bootstrap variable selection or fixed-set logistic models"),
    c("bc",    "Bootstrap Cox",             "analyses",      "bootstrap variable selection or fixed-set Cox models"),
    c("bn",    "Bootstrap nonparametric",   "analyses",      "bootstrap confidence intervals for nonparametric estimates"),
    c("bq",    "Bootstrap quantile",        "analyses",      "quantile regression with bagging"),
    c("br",    "Bootstrap regression",      "analyses",      "linear regression with bagging"),
    c("nm",    "Nonparametric model",       "analyses",      "nonparametric regression models"),
    c("rf",    "Random forest",             "analyses",      "random forest and randomForestSRC models"),
    c("pm",    "Propensity model",          "analyses",      "count outcome with balancing score"),
    c("rm",    "Regression model",          "analyses",      "linear regression with balancing score"),
    c("cm",    "Cox matching",              "analyses",      "Cox PH with propensity matching / IPTW"),
    c("ls",    "Life table / STS",          "analyses",      "STS observed-versus-predicted analyses"),
    c(NA_character_, "Estimates", "estimates", "model fits and cached results; written by one job, read by later ones in the set"),
    c("hp",    "Hazard plot",               "graphs",        "overlays actuarial and predicted survival; patient-specific curves"),
    c("hs",    "Hazard setup",              "graphs",        "patient-level survival predictions from the HM model"),
    c("mp",    "Mixed model plot",          "graphs",        "individual and population-level trends from MM"),
    c("lp",    "Logistic plot",             "graphs",        "ordinal or binary logistic model results"),
    c("np",    "Nonparametric plot",        "graphs",        "nonparametric distribution figures"),
    c("dp",    "Descriptive plot",          "graphs",        "bar, scatter, spaghetti, sankey, bubble plots"),
    c("fp",    "Forest plot",               "graphs",        "odds ratio or hazard ratio forest plots"),
    c("gp",    "Generalized model plot",    "graphs",        "depicts generalized / longitudinal model results"),
    c("cp",    "Cumulative probability plot", "graphs",      "cumulative probability figures"),
    c("ce",    "Competing events",          "graphs",        "competing risks / multistate figures"),
    c("rp",    "Regression plot",           "graphs",        "regression and balance figures"),
    c("ar",    "Analysis report",           "documents",     "the written analysis report"),
    c("rfsrc", "Random forest (SRC)",       "analyses",      "randomForestSRC survival, regression and classification models"),
    c("rfc",   "Random forest classifier",  "analyses",      "random forest classification reporting"),
    c("rfs",   "Random forest survival",    "analyses",      "random forest survival analysis reporting"),
    c("nb",    "Notebook",                  "analyses",      "boosting notebooks (Boostmtree, BoostMLR)"),
    stringsAsFactors = FALSE
  )
  names(tx) <- c("prefix", "name", "folder", "description")
  tx
}

#' Second fields that are not analysis prefixes
#'
#' Some file names lead with a utility name rather than an analysis prefix —
#' \code{plots}, \code{PPTs}. They are listed here so the test suite can tell "not a
#' prefix" apart from "a prefix nobody documented". Without this distinction
#' the taxonomy either fills with non-prefixes or stops catching real
#' omissions.
#'
#' @return A character vector.
#' @export
#' @examples
#' hvti_non_prefixes()
hvti_non_prefixes <- function() {
  c("plots", "ppt", "PPTs", "test", "pp", "ref", "refs")
}
