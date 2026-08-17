# Study initialization. The pressure to record provenance belongs at a study's
# birth, not at its close: by the time a paper is accepted it is years too late
# to ask for a dataset checksum. This writes the two files that make every
# later record true.
#
# No cohort count is ever supplied by a caller. A number a human types is a
# number that can disagree with the data -- the failure this whole design
# exists to remove -- so the counts are read off the dataset.

#' Initialize a study for reproducible analysis
#'
#' @description
#' Writes a study's \code{_study.yml} identity manifest and seeds a
#' \code{manifest.yaml} pinning the built dataset's SHA-256, so that a result
#' filed years later can name what produced it.
#'
#' The cohort counts are \strong{derived} from the dataset rather than accepted
#' as arguments. Only the study's identity — its title, its dataset filename,
#' and the columns that define the event and the follow-up time — has to be
#' supplied, because none of that can be inferred.
#'
#' \code{renv} is not touched. A missing \code{renv.lock} is reported as an
#' open item by \code{\link{study_status}}; creating one is
#' \code{renv::init()}'s job, and it restarts the R session.
#'
#' @param root Character. The study root to initialize. Must exist and be
#'   writable, and must not already contain a \code{_study.yml}.
#' @param study Character(1). The study title, recorded verbatim.
#' @param built Character(1). Filename of the built dataset within
#'   \code{<root>/datasets}, \strong{with} its extension — the reader
#'   dispatches on it.
#' @param event Character(1). Name of the event-indicator column.
#' @param time Character(1). Name of the follow-up-time column.
#' @param population Character(1) or \code{NULL}. Free-text description of the
#'   cohort. Optional.
#' @param source Character(1) or \code{NULL}. Free-text description of where
#'   the dataset came from, passed to \code{\link{update_manifest}}.
#' @param extract_date Character, \code{Date}, or \code{NULL}. The date the
#'   data were pulled. When \code{NULL} the dataset file's modification date is
#'   used, because recording today's date for a dataset built years ago would
#'   write a false fact into the manifest.
#'
#' @return An object of class \code{"study_status"}, returned visibly, so the
#'   remaining open items are shown at the console.
#'
#' @seealso \code{\link{study_status}}, \code{\link{study_config}},
#'   \code{\link{update_manifest}}
#'
#' @export
#'
#' @examples
#' root <- file.path(tempdir(), "study-init-example")
#' dir.create(file.path(root, "datasets"), recursive = TRUE,
#'            showWarnings = FALSE)
#' write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
#'           file.path(root, "datasets", "example.csv"), row.names = FALSE)
#' st <- study_init(root, study = "Example", built = "example.csv",
#'                  event = "dead", time = "iv_dead")
#' study_config(root)$cohort$n
#' unlink(root, recursive = TRUE)
study_init <- function(root, study, built, event, time,
                       population   = NULL,
                       source       = NULL,
                       extract_date = NULL) {
  root <- normalizePath(root, mustWork = TRUE)

  yml <- file.path(root, "_study.yml")
  if (file.exists(yml)) {
    stop("study_init(): ", yml, " already exists. Edit it rather than ",
         "re-initialising: overwriting a study's identity would invalidate ",
         "every provenance sidecar that recorded its checksum.",
         call. = FALSE)
  }

  if (file.access(root, mode = 2L) != 0L) {
    stop("study_init(): the study root is not writable: ", root,
         call. = FALSE)
  }

  if (!nzchar(tools::file_ext(built))) {
    stop("study_init(): built = '", built, "' has no file extension. Give ",
         "the dataset filename in full; the reader dispatches on the ",
         "extension.", call. = FALSE)
  }

  # A synthetic config. study_config() cannot be used here -- it reads the
  # _study.yml this function is about to write -- but neither read_built() nor
  # cohort_counts() needs a validated one: the first uses $root and $built,
  # the second $cohort$event and $cohort$time.
  cfg <- list(root   = root,
              built  = built,
              cohort = list(event = event, time = time))

  p <- built_path(cfg)
  if (!file.exists(p)) {
    stop("study_init(): the built dataset is missing: ", p,
         "\nExpected <study root>/datasets/<built>.", call. = FALSE)
  }

  d  <- read_built(cfg)
  cc <- cohort_counts(d, cfg)  # errors, naming the column, if either is absent

  if (is.null(extract_date)) {
    extract_date <- as.Date(file.info(p)$mtime)
  }

  yaml::write_yaml(
    list(
      study      = study,
      population = population,
      built      = built,
      citation   = NULL,
      cohort     = list(n          = cc$n,
                        n_events   = cc$n_events,
                        n_censored = cc$n_censored,
                        event      = event,
                        time       = time)
    ),
    yml
  )

  # n_rows is passed explicitly: .auto_count_rows() refuses .sas7bdat unless
  # options(manifest.allow_heavy_rowcount = TRUE), and the frame has already
  # been read, so a second full read would be wasted work.
  update_manifest(file          = p,
                  manifest_path = file.path(root, "manifest.yaml"),
                  extract_date  = extract_date,
                  n_rows        = nrow(d),
                  source        = source)

  study_status(root)
}
