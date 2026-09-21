# Builds a disposable study tree for tests: <dir>/_study.yml plus
# <dir>/datasets/<built>. The fixture data retains event and time columns for
# analyses that need them, but dataset registration is endpoint-neutral.
#
# `omit` drops keys from the written YAML, which is how the missing-key errors
# are exercised.

make_study_fixture <- function(dir,
                               built        = "built_test.sas7bdat",
                               n            = 20L,
                               n_events     = 8L,
                               event        = "dead",
                               time         = "iv_dead",
                               write_data   = TRUE,
                               omit         = character(0)) {
  dir.create(file.path(dir, "datasets"), recursive = TRUE, showWarnings = FALSE)

  cfg <- list(
    study      = "Test study for hvtiRutilities",
    population = "Fixture, n=20",
    built      = built,
    citation   = "No citation; fixture."
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
    d[[event]] <- c(rep(1L, n_events), rep(0L, n - n_events))
    d[[time]]  <- as.numeric(seq_len(n))
    suppressWarnings(haven::write_sas(d, file.path(dir, "datasets", built)))
  }

  dir
}

make_registered_study <- function(dir, ancillary = FALSE) {
  root <- file.path(dir, "study")
  study_setup(root, "Registered fixture", 42L)
  data_dir <- study_dir("datasets", root)

  write.csv(
    data.frame(dead = c(1L, 0L, 0L), iv_dead = 1:3),
    file.path(data_dir, "built.csv"),
    row.names = FALSE
  )
  register_data(root, "built.csv")

  write.csv(
    data.frame(dead = c(1L, 0L), iv_dead = 1:2),
    file.path(data_dir, "complete.csv"),
    row.names = FALSE
  )
  register_data(
    root,
    "complete.csv",
    dataset = "complete_cases",
    role = "named"
  )

  if (ancillary) {
    write.csv(
      data.frame(id = 1:2, measure = c(3.1, 4.2)),
      file.path(data_dir, "imaging.csv"),
      row.names = FALSE
    )
    register_data(
      root,
      "imaging.csv",
      dataset = "imaging",
      role = "named"
    )
  }

  root
}
