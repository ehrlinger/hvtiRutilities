# Builds a disposable study tree for tests: <dir>/_study.yml plus
# <dir>/datasets/<built>. The dataset's cohort counts are constructed to match
# the manifest, so assert_cohort() passes by default and a test that wants a
# failure perturbs one or the other deliberately.
#
# `omit` drops keys from the written YAML, which is how the missing-key errors
# are exercised. Nested keys use dotted form: "cohort.n_events".

make_study_fixture <- function(dir,
                               built        = "built_test.sas7bdat",
                               n            = 20L,
                               n_events     = 8L,
                               cohort_event = "dead",
                               cohort_time  = "iv_dead",
                               write_data   = TRUE,
                               omit         = character(0)) {
  dir.create(file.path(dir, "datasets"), recursive = TRUE, showWarnings = FALSE)

  cfg <- list(
    study      = "Test study for hvtiRutilities",
    population = "Fixture, n=20",
    built      = built,
    citation   = "No citation; fixture.",
    cohort     = list(
      n          = n,
      n_events   = n_events,
      n_censored = n - n_events,
      event      = cohort_event,
      time       = cohort_time
    )
  )

  for (k in omit) {
    parts <- strsplit(k, ".", fixed = TRUE)[[1]]
    if (length(parts) == 1L) {
      cfg[[parts]] <- NULL
    } else {
      cfg[[parts[1]]][[parts[2]]] <- NULL
    }
  }

  yaml::write_yaml(cfg, file.path(dir, "_study.yml"))

  if (write_data) {
    d <- data.frame(
      id = seq_len(n),
      x  = as.numeric(seq_len(n))
    )
    # Event indicator: exactly n_events ones. The time column carries no NAs,
    # matching the real built080426 (see read_built.R's cohort note).
    d[[cohort_event]] <- c(rep(1L, n_events), rep(0L, n - n_events))
    d[[cohort_time]]  <- as.numeric(seq_len(n))
    suppressWarnings(haven::write_sas(d, file.path(dir, "datasets", built)))
  }

  dir
}
