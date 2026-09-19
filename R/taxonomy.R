#' Analysis prefix taxonomy
#'
#' The prefix system inherited from the original CORR analysis binder. The
#' prefix encodes both the type of analysis and the folder the job belongs in.
#'
#' This is data rather than documentation on purpose. The same table lived in a
#' README and drifted from the files it described; as a function it is checked
#' by the test suite against the templates actually present.
#'
#' \strong{Folder names are load-bearing. Row order is not, folder order
#' included, as of 2026-09-03.}
#'
#' A template directory and a numbered study directory are both spelled
#' \code{<NN>_<folder>}, as in \code{20_distributions}; a legacy study keeps
#' the bare name, as in \code{distributions}, and \code{\link{study_dir}}
#' resolves either. The name after the digits, or the bare name, must be a
#' \code{folder} in this table. \code{hvtiRtemplates} tests
#' that every template directory names one, so renaming or removing a folder
#' that holds a template turns its CI red. The digits are \emph{assigned}, not
#' derived from this table. They are hardcoded in \code{\link{study_dir}}'s
#' layout map here and in the template directory names there, and
#' \code{estimates} is \code{90} though it is the table's fifth folder, because
#' it holds saved output rather than jobs. Reordering rows, or folders, changes
#' nothing downstream.
#'
#' \emph{Adding or renaming} a folder is not free on the study side.
#' \code{\link{study_dir}} knows only the folders in its own layout map, and no
#' test compares that map's names with \code{unique(hvti_taxonomy()$folder)},
#' so a folder added here and not there is one \code{study_dir()} refuses as
#' unknown.
#'
#' Templates carry no ordinal. They were once named \code{<NN>.<MM>-<prefix>},
#' with \code{NN} taken from this table's folder order through a hardcoded map
#' in \code{hvtiRtemplates}; the ordinal and that map were both retired on
#' 2026-09-03 (\code{hvtiRtemplates:dev/specs/2026-09-03-template-identity-design.md}).
#' A template is now \code{<prefix>[-<qualifier>].qmd}, and the catalog that
#' lists them is \code{hvtiRtemplates}' own \code{inst/extdata/templates.json}.
#'
#' History, kept because it is why the digits are assigned: moving \code{hs}
#' out of \code{analyses} in 1.1.6 shifted \code{bh} from sixth to fifth while
#' its shipped filename stayed \code{04.06}, and nothing caught it. \code{bh}
#' was renumbered \code{04.05}. Identity derived from a row position breaks when
#' an upstream row moves. A job named \code{04.06-bh}, from \code{hvtiRtemplates}
#' before its 1.1.0, is the same template as \code{04.05-bh}.
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
#' \strong{\code{si} and \code{mi} are two prefixes, not one, and that is the
#' point.} 223 studies call single mean imputation, 326 call multiple
#' imputation, and 18 call both. They are different methods with different
#' inferential properties, and 18 studies running both means one prefix could
#' not label them unambiguously. \code{mi} is safe here only because it is
#' \emph{paired}: standing alone it reads as multiple imputation to a
#' statistician, so using it for the single-imputation job would misname
#' exactly the thing the split exists to distinguish.
#'
#' \strong{Neither replaces \code{vars}, whose description still says
#' "imputations" on purpose.} \code{vars} is the job that enhances a dataset
#' with temporary variables, imputations and propensity terms together --
#' porting \code{vars.sas} found mean imputation across 394 variables inside
#' it. \code{si} and \code{mi} name jobs whose \emph{whole purpose} is
#' imputation. A job that imputes as one step among several is \code{vars};
#' a job that exists to impute is \code{si} or \code{mi}.
#'
#' \code{folder} names two different things. For most rows it is the analysis
#' type's home folder, matched to a job prefix. One row, \code{estimates}, is an
#' artifact kind rather than a job type: it holds serialized fits and cached
#' results written by one job and read by a later one in the same set, and no
#' analysis produces it directly. That row's \code{prefix} is \code{NA}, not a
#' string, because there is no prefix to assign it.
#'
#' \strong{The random forest family splits on the OUTCOME axis, not the
#' package axis.} \code{rfs}, \code{rfc} and \code{rfr} name the survival,
#' classification and regression outcomes, which is the split
#' \code{bh}/\code{bl}/\code{bc}/\code{bn}/\code{bq}/\code{br} and
#' \code{pm}/\code{rm}/\code{cm} already use. It is a rename of a distinction
#' the corpus draws already, not a new one imposed: the jobs carry the outcome
#' in field two today, as \code{tp.rfsrc.survival.R} and its siblings.
#'
#' \strong{\code{rf} and \code{rfsrc} are retained as legacy umbrella rows.}
#' They named the same set as each other, on the package axis, and neither is
#' templated. They stay in the table so a census can still resolve the corpus
#' that uses them, which is not small: \code{rfsrc} measures 131 studies and
#' 2,295 jobs, more than \code{rf} (47), \code{rfs} (25) and \code{rfc} (19)
#' combined, twice over. Deleting the rows was rejected on two grounds.
#' \code{\link{hvti_prefix_folds}} cannot express the demotion, because a fold
#' is one-to-one and \code{rfsrc} spans all three outcomes, so there is no
#' single prefix to fold it into. And an absent prefix reads to the census as
#' one nobody documented, which is the opposite of what a superseded name
#' means. Demoted here means \emph{never templated}, and since 2026-09-18 it is
#' machine-readable as well as worded: the \code{umbrella} column is \code{TRUE}
#' on exactly these two rows, so a consumer can exempt them without
#' hard-coding a list. The two rows keep
#' distinct descriptions so a census hit on a legacy job can still say which
#' spelling it used.
#'
#' \strong{The demotion is recorded here, and only here.} Until 2026-09-19
#' \code{hvtiR}'s job catalog also marked \code{rf} and \code{rfsrc} with a
#' \code{retire} disposition, which coincided with this demotion by decision.
#' That catalog has moved to \code{hvtiRtemplates} as its template catalog,
#' read by \code{hvtiRtemplates::template_catalog()}, where every row is a
#' template owed in that package. It has no \code{retire} disposition, and
#' \code{rf} and \code{rfsrc} have no row at all; its guard that every
#' taxonomy prefix has a catalog row exempts them by reading the
#' \code{umbrella} column above. \code{hvtiR::jobs()} was removed in
#' \code{hvtiR} 1.2.0.
#'
#' \strong{\code{sid} and \code{vt} are filed under \code{analyses} with the
#' rest of the family}, and compose on the \code{rf*} jobs rather than
#' replacing them. The \code{rfc}/\code{rfs} folder contradiction is
#' deliberately NOT settled here: the taxonomy says \code{analyses} while the
#' SAS library files them under \code{graphs} and \code{documents}, and the
#' 2026-08-27 census found the same contradiction corpus-wide for
#' \code{ac}/\code{hz}. It is a systemic open question with its own spec owed,
#' and the ML batch is not blocked waiting on it. See
#' \code{hvtiRtemplates:dev/specs/2026-09-17-ml-family-roadmap-design.md}.
#'
#' @return A data frame with columns \code{prefix}, \code{name}, \code{folder},
#'   \code{description} and \code{umbrella}. \code{prefix} is \code{NA} for the
#'   one row that names an artifact kind rather than an analysis type.
#'   \code{umbrella} is logical: \code{TRUE} for the legacy umbrella prefixes
#'   \code{rf} and \code{rfsrc}, for which no template is owed; \code{FALSE} for
#'   every other prefix; \code{NA} for the artifact row.
#' @export
#' @examples
#' head(hvti_taxonomy())
hvti_taxonomy <- function() {
  tx <- rbind.data.frame(
    c("bd",    "Build",                     "datasets",      "assembles raw sources into the analytic dataset"),
    c("vars",  "Variables",                 "datasets",      "macro enhancing the dataset with temp vars, imputations, propensity"),
    c("dt",    "Data check",                "datasets",      "initial QC of the build dataset"),
    c("si",    "Single imputation",         "datasets",      "mean imputation of missing covariates; one completed dataset"),
    c("mi",    "Multiple imputation",       "datasets",      "m completed datasets for pooled analysis; not a variant of si"),
    c("dc",    "Descriptive",               "descriptive",   "Table 1s, covariate summaries, balance tables"),
    c("lg",    "Logit trends",              "descriptive",   "variable transformation and linearity checks"),
    c("rg",    "Regression trends",         "descriptive",   "trend checks for continuous and polytomous outcomes"),
    c("ac",    "Actuarial",                 "distributions", "Kaplan-Meier / non-parametric life table"),
    c("hz",    "Hazard fit",                "distributions", "fits the underlying hazard distribution"),
    c("cd",    "Cumulative distribution",   "distributions", "cumulative distribution plots; follow-up summaries"),
    c("nd",    "Non-linear distributions",  "distributions", "distribution estimates stratified by group"),
    c("hm",    "Hazard model",              "analyses",      "risk factor analysis; builds on the HZ fit"),
    c("mm",    "Mixed model",               "analyses",      "continuous repeated-measures longitudinal analysis"),
    c("gm",    "Generalized model",         "analyses",      "repeated-measures ordinal / count models"),
    c("lm",    "Logistic model",            "analyses",      "logistic regression; propensity score development"),
    c("bh",    "Bootstrap hazard",          "analyses",      "bootstrap variable selection or fixed-set hazard models"),
    c("bl",    "Bootstrap logistic",        "analyses",      "bootstrap variable selection or fixed-set logistic models"),
    c("bc",    "Bootstrap Cox",             "analyses",      "bootstrap variable selection or fixed-set Cox models"),
    c("bn",    "Bootstrap non-linear",      "analyses",      "bootstrap confidence intervals for non-linear estimates"),
    c("bq",    "Bootstrap quantile",        "analyses",      "quantile regression with bagging"),
    c("br",    "Bootstrap regression",      "analyses",      "linear regression with bagging"),
    c("nm",    "Non-linear model",          "analyses",      "non-linear regression models"),
    c("rf",    "Random forest (umbrella)",  "analyses",      "legacy umbrella, generic spelling; superseded by rfs/rfc/rfr"),
    c("rm",    "Regression model",          "analyses",      "linear regression with balancing score"),
    c("cm",    "Cox matching",              "analyses",      "Cox PH with propensity matching / IPTW"),
    c("ls",    "Life table / STS",          "analyses",      "STS observed-versus-predicted analyses"),
    c(NA_character_, "Estimates", "estimates", "model fits and cached results; written by one job, read by later ones in the set"),
    c("hp",    "Hazard plot",               "graphs",        "overlays actuarial and predicted survival; patient-specific curves"),
    c("hs",    "Hazard setup",              "graphs",        "patient-level survival predictions from the HM model"),
    c("mp",    "Mixed model plot",          "graphs",        "individual and population-level trends from MM"),
    c("lp",    "Logistic plot",             "graphs",        "ordinal or binary logistic model results"),
    c("np",    "Non-linear plot",           "graphs",        "non-linear distribution figures"),
    c("dp",    "Descriptive plot",          "graphs",        "bar, scatter, spaghetti, sankey, bubble plots"),
    c("fp",    "Forest plot",               "graphs",        "odds ratio or hazard ratio forest plots"),
    c("gp",    "Generalized model plot",    "graphs",        "depicts generalized / longitudinal model results"),
    c("cp",    "Cumulative probability plot", "graphs",      "cumulative probability figures"),
    c("ce",    "Competing events",          "graphs",        "competing risks / multistate figures"),
    c("rp",    "Regression plot",           "graphs",        "regression and balance figures"),
    c("ar",    "Analysis report",           "documents",     "the written analysis report"),
    c("rfsrc", "randomForestSRC (umbrella)", "analyses",     "legacy umbrella, package spelling; superseded by rfs/rfc/rfr"),
    c("rfc",   "Random forest classifier",  "analyses",      "random forest, classification outcome"),
    c("rfs",   "Random forest survival",    "analyses",      "random forest, survival outcome"),
    c("rfr",   "Random forest regression",  "analyses",      "random forest, regression outcome"),
    c("sid",   "Random forest clustering",  "analyses",      "unsupervised sidClustering forest with PAM over K"),
    c("vt",    "Virtual twins",             "analyses",      "per-arm forests, swapped-arm prediction, RMST difference"),
    c("nb",    "Boosting",                  "analyses",      "boosting models (Boostmtree, BoostMLR)"),
    stringsAsFactors = FALSE
  )
  names(tx) <- c("prefix", "name", "folder", "description")
  # `umbrella` is derived here rather than written as a fifth field in every
  # row above: it is TRUE on exactly two rows, and widening all the aligned
  # rows to carry it would bury the two that matter. NA for the artifact row,
  # which has no prefix to demote.
  tx$umbrella <- ifelse(is.na(tx$prefix), NA, tx$prefix %in% c("rf", "rfsrc"))
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

#' Legacy prefixes folded into a taxonomy prefix
#'
#' @description
#' A legacy prefix that names the same job as a prefix in
#' \code{\link{hvti_taxonomy}}, so a census counts its files under that
#' prefix. \code{pm} folds into \code{lm}: a review of the job catalog on
#' 2026-09-11 found that the propensity work filed as \code{pm} belongs with
#' the logistic models in \code{lm}.
#'
#' @details
#' The map is stored, never derived. A fold is a judgement about what a legacy
#' name means, and a rule that inferred it from spelling would also fold names
#' that merely look alike. Every name is absent from \code{hvti_taxonomy()}
#' and every value is present in it; the tests pin both.
#'
#' @return A named character vector, \code{c(legacy = prefix)}.
#' @seealso \code{\link{job_files}}, which applies it.
#' @export
#' @examples
#' hvti_prefix_folds()
hvti_prefix_folds <- function() {
  c(pm = "lm")
}
