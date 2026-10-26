test_that("study_setup creates numbered identity state", {
  root <- file.path(withr::local_tempdir(), "new-study")

  status <- study_setup(
    root,
    study = "Example study",
    study_tracker_id = 42L,
    umbrella = "Aorta program",
    owner = "Analyst",
    renv = FALSE
  )

  expect_s3_class(status, "study_status")
  expect_true(all(dir.exists(file.path(
    root,
    c("00_datasets", "10_descriptive", "20_distributions",
      "30_analyses", "40_graphs", "50_documents", "90_estimates")
  ))))

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$study, "Example study")
  expect_identical(cfg$study_tracker_id, 42L)
  expect_identical(cfg$umbrella, "Aorta program")
  expect_identical(cfg$owner, "Analyst")
  expect_null(cfg$built)
  expect_null(cfg$cohort)
  expect_null(cfg$citation)
  expect_match(
    paste(readLines(file.path(root, "_study.yml")), collapse = "\n"),
    "citation"
  )
  expect_error(study_config(root), "register_data")
  expect_equal(normalizePath(study_root(root)), normalizePath(root))
})

test_that("study_setup creates missing environment files", {
  root <- file.path(withr::local_tempdir(), "new-study")

  study_setup(root, "Example study", 42L, renv = FALSE)

  expect_identical(
    readLines(file.path(root, ".Renviron")),
    "RENV_CONFIG_CACHE_SYMLINKS=FALSE"
  )
  ignore <- readLines(file.path(root, ".renvignore"))
  expect_true(".checkpoint/" %in% ignore)
  expect_true(all(c("00_datasets/", "datasets/", "40_graphs/", "graphs/",
                    "90_estimates/", "estimates/", "templates/") %in%
                    ignore))
})

test_that("study_setup adopts a legacy layout without replacing files", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  writeLines("keep me", file.path(root, ".Renviron"))

  study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE)

  expect_identical(readLines(file.path(root, ".Renviron")), "keep me")
  expect_true(all(dir.exists(file.path(
    root,
    c("datasets", "descriptive", "distributions", "analyses", "graphs",
      "documents", "estimates")
  ))))
  expect_false(dir.exists(file.path(root, "30_analyses")))
})

test_that("study_setup adopts an empty root with numbered directories", {
  root <- withr::local_tempdir()

  study_setup(root, "Empty legacy study", 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE)

  expect_true(dir.exists(file.path(root, "00_datasets")))
  expect_false(dir.exists(file.path(root, "datasets")))
})

test_that("study_setup refuses unsafe existing roots without writing", {
  root <- withr::local_tempdir()
  writeLines("existing", file.path(root, "work.R"))

  expect_error(study_setup(root, "Example", 42L, renv = FALSE), "adopt")
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, ".Renviron")))
})

test_that("study_setup refuses a mixed layout without writing", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "datasets"))
  dir.create(file.path(root, "30_analyses"))

  expect_error(study_setup(root, "Example", 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE), "mixed")
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_false(file.exists(file.path(root, ".Renviron")))
})

test_that("study_setup refuses to replace study identity", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example", 42L, renv = FALSE)
  before <- readLines(file.path(root, "_study.yml"))

  expect_error(
    study_setup(root, "Other", 43L, adopt = TRUE, renv = FALSE, cleanup = FALSE),
    "already exists"
  )
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("study_setup resumes matching adoption without replacing identity", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example", 42L, renv = FALSE)
  before <- readLines(file.path(root, "_study.yml"))
  file.remove(file.path(root, ".renvignore"))

  study_setup(root, "Example", 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE)

  expect_identical(readLines(file.path(root, "_study.yml")), before)
  expect_true(file.exists(file.path(root, ".renvignore")))
})

test_that("the replaced study_init API is unavailable", {
  expect_error(
    getExportedValue("hvtiRutilities", "study_init"),
    "not an exported object"
  )
})

test_that("study_setup writes an R project named for the study directory", {
  root <- file.path(tempfile("rproj-"), "bio_example")
  on.exit(unlink(dirname(root), recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj test", study_tracker_id = 1L, renv = FALSE)
  )

  proj <- file.path(root, "bio_example.Rproj")
  expect_true(file.exists(proj))
  expect_identical(readLines(proj, n = 1L), "Version: 1.0")
})

test_that("study_setup leaves an existing R project alone", {
  root <- tempfile("rproj-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj adopt", study_tracker_id = 2L, renv = FALSE)
  )
  unlink(list.files(root, "[.]Rproj$", full.names = TRUE))
  writeLines(
    "Version: 1.0\n\nRestoreWorkspace: Yes",
    file.path(root, "mine.Rproj")
  )

  suppressMessages(
    study_setup(
      root, study = "Rproj adopt", study_tracker_id = 2L, adopt = TRUE, renv = FALSE, cleanup = FALSE
    )
  )

  expect_identical(list.files(root, "[.]Rproj$"), "mine.Rproj")
  expect_identical(
    readLines(file.path(root, "mine.Rproj"))[[3L]],
    "RestoreWorkspace: Yes"
  )
})

test_that("study_setup sees a hidden existing R project", {
  root <- tempfile("rproj-hidden-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(
    study_setup(root, study = "Rproj adopt", study_tracker_id = 3L, renv = FALSE)
  )
  unlink(list.files(root, "[.]Rproj$", full.names = TRUE))
  writeLines(
    "Version: 1.0\n\nRestoreWorkspace: Yes",
    file.path(root, ".hidden.Rproj")
  )

  suppressMessages(
    study_setup(
      root, study = "Rproj adopt", study_tracker_id = 3L, adopt = TRUE, renv = FALSE, cleanup = FALSE
    )
  )

  expect_identical(
    list.files(root, "[.]Rproj$", all.files = TRUE),
    ".hidden.Rproj"
  )
})

test_that("study_setup records a Tracker identity as verified by default", {
  root <- file.path(withr::local_tempdir(), "new-study")

  study_setup(root, "Example study", 42L, renv = FALSE)

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "tracker")
  expect_true(cfg$identity_verified)
})

test_that("study_setup records a manual identity as unverified", {
  root <- file.path(withr::local_tempdir(), "new-study")

  status <- study_setup(root, "Example study", 42L,
                        identity_source = "manual", renv = FALSE)

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "manual")
  expect_false(cfg$identity_verified)
  row <- status$checks[status$checks$item == "_study.yml", ]
  expect_identical(row$status, "UNVERIFIED")
})

test_that("study_setup rejects an unknown identity source without writing", {
  root <- file.path(withr::local_tempdir(), "new-study")

  expect_error(
    study_setup(root, "Example study", 42L, identity_source = "typed", renv = FALSE),
    "identity_source"
  )
  expect_false(dir.exists(root))
})

test_that("adoption keeps an existing identity and its source", {
  root <- file.path(withr::local_tempdir(), "new-study")
  study_setup(root, "Example study", 42L, identity_source = "manual", renv = FALSE)

  study_setup(root, "Example study", 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE)

  cfg <- study_config(root, require_data = FALSE)
  expect_identical(cfg$identity_source, "manual")
  expect_false(cfg$identity_verified)
})

test_that("study_setup rejects an abbreviated identity source", {
  root <- file.path(withr::local_tempdir(), "new-study")

  expect_error(
    study_setup(root, "Example study", 42L, identity_source = "man", renv = FALSE),
    "identity_source"
  )
  expect_false(dir.exists(root))
})

test_that("study_setup sets up the working directory when root is omitted", {
  root <- file.path(withr::local_tempdir(), "here-study")
  dir.create(root)
  withr::local_dir(root)

  suppressMessages(study_setup(study = "Here", study_tracker_id = 42L, renv = FALSE))

  expect_true(file.exists(file.path(root, "_study.yml")))
  expect_true(dir.exists(file.path(root, "00_datasets")))
})

test_that("an omitted root resolves to the enclosing study, not a nested one", {
  root <- file.path(withr::local_tempdir(), "outer")
  suppressMessages(study_setup(root, "Outer", 42L, renv = FALSE))
  withr::local_dir(file.path(root, "30_analyses"))
  local_mocked_bindings(.study_interactive = function() FALSE)

  expect_error(study_setup(study = "Outer", study_tracker_id = 42L, renv = FALSE), "adopt = TRUE")
  expect_false(file.exists(file.path(root, "30_analyses", "_study.yml")))

  suppressMessages(study_setup(study = "Outer", study_tracker_id = 42L, adopt = TRUE, renv = FALSE, cleanup = FALSE))
  expect_false(file.exists(file.path(root, "30_analyses", "_study.yml")))
})

test_that("an omitted root outside any study still refuses a folder with files", {
  root <- file.path(withr::local_tempdir(), "busy")
  dir.create(root)
  writeLines("x", file.path(root, "notes.txt"))
  withr::local_dir(root)

  expect_error(study_setup(study = "Busy", study_tracker_id = 42L, renv = FALSE), "adopt = TRUE")
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("a malformed _study.yml above the working directory is not taken as no study", {
  root <- file.path(withr::local_tempdir(), "broken")
  dir.create(file.path(root, "sub"), recursive = TRUE)
  writeLines("study: [unclosed", file.path(root, "_study.yml"))
  withr::local_dir(file.path(root, "sub"))

  expect_error(study_setup(study = "Broken", study_tracker_id = 42L, renv = FALSE), "Parser error")
  expect_false(file.exists(file.path(root, "sub", "_study.yml")))
})

test_that("study_setup asks before adopting an existing study when interactive", {
  root <- file.path(withr::local_tempdir(), "asked")
  suppressMessages(study_setup(root, "Asked", 42L, renv = FALSE))
  file.remove(file.path(root, ".renvignore"))
  before <- readLines(file.path(root, "_study.yml"))
  asked <- character(0)
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) {
      asked <<- c(asked, root)
      TRUE
    }
  )

  suppressMessages(study_setup(root, "Asked", 42L, renv = FALSE, cleanup = FALSE))

  expect_length(asked, 1L)
  expect_true(file.exists(file.path(root, ".renvignore")))
  expect_identical(readLines(file.path(root, "_study.yml")), before)
})

test_that("declining the adopt prompt stops without writing", {
  root <- file.path(withr::local_tempdir(), "declined")
  suppressMessages(study_setup(root, "Declined", 42L, renv = FALSE))
  file.remove(file.path(root, ".renvignore"))
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) FALSE
  )

  expect_error(study_setup(root, "Declined", 42L, renv = FALSE), "adopt = TRUE")
  expect_false(file.exists(file.path(root, ".renvignore")))
})

test_that("study_setup does not ask when the existing study has another Tracker ID", {
  root <- file.path(withr::local_tempdir(), "other-id")
  suppressMessages(study_setup(root, "Other", 42L, renv = FALSE))
  local_mocked_bindings(
    .study_interactive = function() TRUE,
    .study_ask_adopt = function(root) stop("should not ask")
  )

  expect_error(study_setup(root, "Other", 43L, renv = FALSE), "already exists for Study Tracker ID 42")
})

test_that("study_setup does not ask when not interactive", {
  root <- file.path(withr::local_tempdir(), "batch")
  suppressMessages(study_setup(root, "Batch", 42L, renv = FALSE))
  local_mocked_bindings(
    .study_interactive = function() FALSE,
    .study_ask_adopt = function(root) stop("should not ask")
  )

  expect_error(study_setup(root, "Batch", 42L, renv = FALSE), "adopt = TRUE")
})

# cleanup = TRUE --------------------------------------------------------------

local_corpus <- function(env = parent.frame()) {
  withr::local_tempdir(.local_envir = env)
}

write_file <- function(root, rel, text = "x") {
  path <- file.path(root, rel)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(text, path)
  path
}

test_that("cleanup deletes tp.* files and binder.summaries.doc anywhere in the study", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  tp <- c("tp.root.sas", "analyses/tp.hz.sas", "analyses/deep/er/tp.lg.R",
          "graphs/templates/old_rplots/tp.plot.R")
  for (rel in tp) write_file(root, rel)
  # A run tp.* program is deleted too; its outputs are not tp.* and stay.
  for (ext in c("sas", "lst", "log")) write_file(root, paste0("analyses/tp.run.", ext))
  write_file(root, "documents/binder.summaries.doc")
  keep <- write_file(root, "analyses/analysis.sas", "keep")

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                        template_dir = local_corpus(), renv = FALSE)

  expect_false(any(file.exists(file.path(root, tp))))
  expect_false(file.exists(file.path(root, "analyses/tp.run.sas")))
  expect_false(file.exists(file.path(root, "analyses/tp.run.lst")))
  expect_false(file.exists(file.path(root, "documents/binder.summaries.doc")))
  expect_identical(readLines(keep), "keep")
  cleaned <- attr(status, "cleanup")
  expect_setequal(cleaned$deleted, c(tp, "analyses/tp.run.sas", "analyses/tp.run.lst",
                                     "analyses/tp.run.log", "documents/binder.summaries.doc"))
})

test_that("cleanup removes templates and old_RF_templates folders left empty", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  write_file(root, "analyses/templates/tp.a.sas")
  write_file(root, "analyses/templates/archive/tp.b.sas")
  write_file(root, "analyses/templates/Thumbs.db")
  write_file(root, "analyses/old_RF_templates/tp.rfsrc.survival.R")
  write_file(root, "analyses/old_RF_templates - Copy/tp.rfsrc.binary.R")
  write_file(root, "graphs/templates/tp.c.R")
  keep <- write_file(root, "graphs/templates/my_plot.R", "keep")

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                        template_dir = local_corpus(), renv = FALSE)

  expect_false(dir.exists(file.path(root, "analyses/templates")))
  expect_false(dir.exists(file.path(root, "analyses/old_RF_templates")))
  expect_false(dir.exists(file.path(root, "analyses/old_RF_templates - Copy")))
  expect_true(dir.exists(file.path(root, "analyses")))
  # A folder still holding study work stays; only its tp.* files go.
  expect_identical(readLines(keep), "keep")
  expect_false(file.exists(file.path(root, "graphs/templates/tp.c.R")))
  expect_setequal(attr(status, "cleanup")$removed_dirs,
                  c("analyses/templates/archive", "analyses/templates",
                    "analyses/old_RF_templates", "analyses/old_RF_templates - Copy"))
})

test_that("cleanup removes any folder it empties, whatever its name", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "graphs"))
  write_file(root, "graphs/templates/tp.BRIER_multiphasehazard.R")
  write_file(root, "graphs/templates/Old-Rplots/tp.plot.R")
  write_file(root, "graphs/templates/tp_ggplot/tp.gg.R")
  write_file(root, "analyses/work/tp.copy.R")
  keep <- write_file(root, "analyses/work/model.R", "keep")
  dir.create(file.path(root, "analyses", "empty_mine"))
  write_file(root, "documents/binder.summaries.doc")

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                        template_dir = local_corpus(), renv = FALSE)

  expect_false(dir.exists(file.path(root, "graphs/templates")))
  expect_true(dir.exists(file.path(root, "graphs")))
  # A study folder emptied by the cleanup stays; so does an empty folder the
  # cleanup did not empty, and a folder still holding work.
  expect_true(dir.exists(file.path(root, "documents")))
  expect_true(dir.exists(file.path(root, "analyses/empty_mine")))
  expect_identical(readLines(keep), "keep")
  expect_setequal(attr(status, "cleanup")$removed_dirs,
                  c("graphs/templates/Old-Rplots", "graphs/templates/tp_ggplot",
                    "graphs/templates"))
})

test_that("cleanup leaves renv, .git, .checkpoint and symlinked folders alone", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  protected <- c("renv/library/pkg/tp.x.R", ".git/tp.y", ".checkpoint/repo/tp.z.sas",
                 "analyses/nested/.git/tp.w")
  for (rel in protected) write_file(root, rel)
  outside <- withr::local_tempdir()
  outside_tp <- write_file(outside, "tp.outside.sas")
  skip_on_os("windows")
  file.symlink(outside, file.path(root, "analyses", "linked"))

  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
              template_dir = local_corpus(), renv = FALSE)

  expect_true(all(file.exists(file.path(root, protected))))
  expect_true(file.exists(outside_tp))
})

test_that("cleanup stops loudly when a file cannot be deleted", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  write_file(root, "analyses/tp.hz.sas")
  local_mocked_bindings(.study_unlink = function(paths, recursive = FALSE) invisible(NULL))

  expect_error(
    study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                template_dir = local_corpus(), renv = FALSE),
    "could not delete 1 .*analyses/tp.hz.sas"
  )
})

test_that("cleanup must be TRUE or FALSE", {
  root <- file.path(withr::local_tempdir(), "new-study")
  expect_error(study_setup(root, "Example", 42L, cleanup = NA, renv = FALSE), "cleanup must be TRUE or FALSE")
  expect_false(dir.exists(root))
})

# renv = TRUE -----------------------------------------------------------------

write_renv_start <- function(root) {
  dir.create(file.path(root, "renv"), showWarnings = FALSE)
  writeLines("# activate", file.path(root, "renv", "activate.R"))
  writeLines('source("renv/activate.R")', file.path(root, ".Rprofile"))
}

write_lock <- function(root) {
  writeLines('{"R": {"Version": "4.6.0"}, "Packages": {}}', file.path(root, "renv.lock"))
}

snapshot_expr <- function(root) {
  project <- deparse(normalizePath(root, winslash = "/"))
  paste0("renv::load(", project, "); renv::settings$use.cache(FALSE, project = ", project,
         "); renv::settings$snapshot.type('explicit', project = ", project,
         "); renv::snapshot(project = ", project, ", prompt = FALSE)")
}

fake_rscript <- function(calls, init_ok = TRUE, snapshot_ok = TRUE) {
  force(calls)
  function(expr, root, ...) {
    calls$exprs <- c(calls$exprs, expr)
    if (grepl("renv::init", expr, fixed = TRUE)) {
      if (!init_ok) return(list(status = 1L, output = "init exploded"))
      write_renv_start(root)
    } else {
      if (!snapshot_ok) return(list(status = 1L, output = "snapshot exploded"))
      write_lock(root)
    }
    list(status = 0L, output = "")
  }
}

test_that("renv = TRUE initializes a bare environment and snapshots it after cleanup", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  write_file(root, "analyses/tp.hz.R")
  calls <- new.env()
  seen_tp <- NULL
  local_mocked_bindings(.study_rscript = function(expr, root, ...) {
    seen_tp <<- c(seen_tp, file.exists(file.path(root, "analyses/tp.hz.R")))
    fake_rscript(calls)(expr, root)
  })

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE, renv = TRUE,
                        template_dir = local_corpus())

  expect_identical(calls$exprs, c("renv::init(bare = TRUE, restart = FALSE)",
                                  snapshot_expr(root)))
  expect_false(any(seen_tp))
  expect_identical(attr(status, "renv"), "initialized")
  expect_true(file.exists(file.path(root, "renv.lock")))
})

test_that("renv = TRUE declares the study before initializing it", {
  root <- withr::local_tempdir()
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))
  study_setup(root, "New study", 42L, adopt = TRUE, cleanup = FALSE, renv = TRUE)
  expect_true(file.exists(file.path(root, "DESCRIPTION")))
  expect_identical(unname(read.dcf(file.path(root, "DESCRIPTION"))[1L, "Type"]), "Project")
})

test_that(".renvignore covers template copies outside templates/", {
  expect_true(all(c("tp.*", "old_RF_templates*/") %in% .study_renvignore()))
})

test_that("renv = TRUE keeps a complete environment and resumes an interrupted one", {
  root <- withr::local_tempdir()
  write_renv_start(root)
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE)
  expect_identical(calls$exprs, snapshot_expr(root))
  expect_identical(attr(status, "renv"), "initialized")

  calls$exprs <- NULL
  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE)
  expect_null(calls$exprs)
  expect_identical(attr(status, "renv"), "retained")
})

test_that("renv = TRUE stops on any other partial environment without running R", {
  root <- withr::local_tempdir()
  write_lock(root)
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))

  expect_error(
    study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE),
    "partial renv environment; sound: renv.lock; missing or invalid: renv, .Rprofile"
  )
  expect_null(calls$exprs)
})

test_that("renv = TRUE reports a failed init or snapshot", {
  root <- withr::local_tempdir()
  local_mocked_bindings(.study_rscript = fake_rscript(new.env(), init_ok = FALSE))
  expect_error(study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE),
               "renv initialization failed: init exploded")

  root <- withr::local_tempdir()
  local_mocked_bindings(.study_rscript = fake_rscript(new.env(), snapshot_ok = FALSE))
  expect_error(study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE),
               "renv snapshot failed: snapshot exploded")
})

legacy_study <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "analyses"))
  write_file(root, "analyses/tp.hz.R")
  root
}

test_that("cleanup follows adopt when not given", {
  root <- legacy_study()
  local_mocked_bindings(.study_rscript = fake_rscript(new.env()))
  study_setup(root, "Legacy study", 42L, adopt = TRUE, template_dir = local_corpus())
  expect_false(file.exists(file.path(root, "analyses/tp.hz.R")))
})

test_that("cleanup = FALSE overrides adopt", {
  root <- legacy_study()
  local_mocked_bindings(.study_rscript = fake_rscript(new.env()))
  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = FALSE)
  expect_true(file.exists(file.path(root, "analyses/tp.hz.R")))
})

test_that("an adopt accepted at the prompt cleans up too", {
  root <- legacy_study()
  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = FALSE, renv = FALSE)
  write_file(root, "analyses/tp.hz.R")   # a template copy arriving after the first setup
  local_mocked_bindings(.study_interactive = function() TRUE,
                        .study_ask_adopt = function(root) TRUE,
                        .study_rscript = fake_rscript(new.env()))
  study_setup(root, "Legacy study", 42L, template_dir = local_corpus())
  expect_false(file.exists(file.path(root, "analyses/tp.hz.R")))
})

test_that("an implied cleanup with no template corpus stops before writing", {
  root <- legacy_study()
  expect_error(study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = FALSE,
                           template_dir = file.path(tempdir(), "no-such-corpus")),
               "template corpus not found")
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("renv is on by default", {
  root <- withr::local_tempdir()
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))
  study_setup(root, "New study", 42L, adopt = TRUE, cleanup = FALSE)
  expect_true(any(grepl("renv::init", calls$exprs, fixed = TRUE)))
})

test_that("the renv child process does not inherit a disabled autoloader", {
  # A machine-level RENV_CONFIG_AUTOLOADER_ENABLED=FALSE stops renv::init()
  # from writing the study's .Rprofile; the study's infrastructure must not
  # depend on the caller's machine settings.
  withr::local_envvar(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
  result <- .study_rscript('cat(Sys.getenv("RENV_CONFIG_AUTOLOADER_ENABLED", "unset"))',
                           withr::local_tempdir(), "--vanilla")
  expect_identical(result$status, 0L)
  expect_identical(result$output, "unset")
})

test_that("cleanup deletes files whose name and content match the template corpus", {
  corpus <- withr::local_tempdir()
  write_file(corpus, "documents/methods-boosting.docx", "boosting methods")
  write_file(corpus, "analyses/templates/references.bib", "@article{template}")
  write_file(corpus, "graphs/templates/tp_ggplot/multipanel_barplot.pdf", "pdf bytes")
  write_file(corpus, ".renvignore", "templates/")
  write_file(corpus, ".git/config", "[core]")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  write_file(root, "documents/methods-boosting.docx", "boosting methods")
  write_file(root, "analyses/references.bib", "@article{template}")
  own_bib <- write_file(root, "documents/references.bib", "@article{our_paper}")
  write_file(root, "graphs/templates/tp_ggplot/multipanel_barplot.pdf", "pdf bytes")
  edited <- write_file(root, "documents/stat_refs.docx", "ours")
  write_file(root, "config", "[core]")

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                        template_dir = corpus, renv = FALSE)

  expect_setequal(attr(status, "cleanup")$deleted,
                  c("documents/methods-boosting.docx", "analyses/references.bib",
                    "graphs/templates/tp_ggplot/multipanel_barplot.pdf"))
  # Same name, different content: the study's own file stays.
  expect_identical(readLines(own_bib), "@article{our_paper}")
  expect_true(file.exists(edited))
  # The corpus's .git is not template material, and setup's own .renvignore stays.
  expect_true(file.exists(file.path(root, "config")))
  expect_true(file.exists(file.path(root, ".renvignore")))
  expect_false(dir.exists(file.path(root, "graphs/templates")))
})

test_that("cleanup keeps a .renvignore or .gitignore identical to the corpus copy", {
  corpus <- withr::local_tempdir()
  write_file(corpus, ".renvignore", "templates/")
  write_file(corpus, ".gitignore", "*.log")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  write_file(root, ".renvignore", "templates/")
  write_file(root, ".gitignore", "*.log")

  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE, template_dir = corpus, renv = FALSE)

  expect_true(all(file.exists(file.path(root, c(".renvignore", ".gitignore")))))
})

test_that("cleanup stops when the template corpus cannot be found", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  tp <- write_file(root, "analyses/tp.hz.sas")
  missing <- file.path(withr::local_tempdir(), "nowhere")

  expect_error(
    study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE, template_dir = missing, renv = FALSE),
    "template corpus not found"
  )
  expect_true(file.exists(tp))
  expect_false(file.exists(file.path(root, "_study.yml")))
})


# Review of #211 ------------------------------------------------------------

test_that("cleanup refuses a template_dir that overlaps the study, before writing", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  data <- write_file(root, "datasets/dataset.csv", "a,b")
  inside <- file.path(root, "documents", "corpus")
  dir.create(inside, recursive = TRUE)

  for (corpus in c(root, inside, dirname(root))) {
    expect_error(
      study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE, template_dir = corpus, renv = FALSE),
      "overlap"
    )
  }
  expect_true(file.exists(data))
  expect_false(file.exists(file.path(root, "_study.yml")))
})

test_that("cleanup refuses an overlapping corpus for a root that does not exist yet", {
  corpus <- withr::local_tempdir()
  root <- file.path(corpus, "new", "study")
  expect_error(
    study_setup(root, "New study", 42L, cleanup = TRUE, template_dir = corpus, renv = FALSE),
    "overlap"
  )
  expect_false(dir.exists(root))
})

test_that("cleanup never enters .checkpoint or renv folders at any depth", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  protected <- c("analyses/nested/.checkpoint/repo/tp.a.sas",
                 "analyses/nested/renv/library/pkg/tp.b.R")
  for (rel in protected) write_file(root, rel)

  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
              template_dir = local_corpus(), renv = FALSE)

  expect_true(all(file.exists(file.path(root, protected))))
})

test_that("cleanup keeps a folder holding a skipped symlink or an untouched empty folder", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  outside <- withr::local_tempdir()
  write_file(root, "analyses/work/tp.a.R")
  file.symlink(outside, file.path(root, "analyses", "work", "link"))
  write_file(root, "analyses/other/tp.b.R")
  dir.create(file.path(root, "analyses", "other", "mine"))

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE,
                        template_dir = local_corpus(), renv = FALSE)

  expect_true(nzchar(Sys.readlink(file.path(root, "analyses", "work", "link"))))
  expect_true(dir.exists(file.path(root, "analyses", "other", "mine")))
  expect_length(attr(status, "cleanup")$removed_dirs, 0L)
})

test_that("a nested .git in the corpus is not template material", {
  corpus <- withr::local_tempdir()
  write_file(corpus, "graphs/templates/.git/config", "[core]")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "analyses"))
  config <- write_file(root, "analyses/config", "[core]")

  study_setup(root, "Legacy study", 42L, adopt = TRUE, cleanup = TRUE, template_dir = corpus, renv = FALSE)

  expect_true(file.exists(config))
})

test_that("renv = TRUE does not mistake mere paths for a complete environment", {
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))
  cases <- list(
    renv_file = function(root) {
      writeLines("", file.path(root, "renv"))
      writeLines('source("renv/activate.R")', file.path(root, ".Rprofile"))
      write_lock(root)
    },
    empty_lock = function(root) {
      write_renv_start(root)
      file.create(file.path(root, "renv.lock"))
    },
    unrelated_profile = function(root) {
      dir.create(file.path(root, "renv"))
      writeLines("# activate", file.path(root, "renv", "activate.R"))
      writeLines("options(digits = 4)", file.path(root, ".Rprofile"))
      write_lock(root)
    }
  )
  for (case in names(cases)) {
    root <- withr::local_tempdir()
    cases[[case]](root)
    expect_error(study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE),
                 "partial renv environment", info = case)
  }
  expect_null(calls$exprs)
})

# Shaped like the custom .Rprofile of an adopted study: path-independent,
# because knitr starts R in the book folder, and refusing renv under the wrong
# R minor version. It activates renv through a built path, never the literal.
custom_rprofile <- function(activate) {
  c(
    "local({",
    "  root <- normalizePath(getwd())",
    "  while (!file.exists(file.path(root, \"renv.lock\"))) {",
    "    parent <- dirname(root)",
    "    if (identical(parent, root)) return(invisible())",
    "    root <- parent",
    "  }",
    "  # The study library is built for one R minor version; refuse any other.",
    "  have <- paste(R.version$major, sub(\"[.].*\", \"\", R.version$minor), sep = \".\")",
    "  if (!identical(have, \"4.5\")) {",
    "    warning(\"renv not activated: the library is built for R 4.5\", call. = FALSE)",
    "    return(invisible())",
    "  }",
    activate,
    "})"
  )
}

test_that("a .Rprofile is sound when it sources activate.R by a literal or a built path", {
  sound <- list(
    built = custom_rprofile('  Sys.setenv(RENV_PROJECT = root); source(file.path(root, "renv", "activate.R"))'),
    literal = 'source("renv/activate.R")',
    variable = c('activate <- file.path("renv", "activate.R")', "source(activate)"),
    pasted = 'source(paste0(getwd(), "/renv/activate.R"))'
  )
  unsound <- list(
    no_activation = custom_rprofile("  Sys.setenv(RENV_PROJECT = root)"),
    commented = c('# source("renv/activate.R")', "options(digits = 4)"),
    commented_built = custom_rprofile('  #  source(file.path(root, "renv", "activate.R"))')
  )
  for (case in c(names(sound), names(unsound))) {
    root <- withr::local_tempdir()
    write_renv_start(root)
    writeLines(c(sound, unsound)[[case]], file.path(root, ".Rprofile"))
    expect_identical(.study_renv_parts(root)[[".Rprofile"]], case %in% names(sound), info = case)
  }
})

test_that("renv = TRUE retains a study whose .Rprofile activates renv through a built path", {
  calls <- new.env()
  local_mocked_bindings(.study_rscript = fake_rscript(calls))
  root <- withr::local_tempdir()
  write_renv_start(root)
  writeLines(custom_rprofile('  Sys.setenv(RENV_PROJECT = root); source(file.path(root, "renv", "activate.R"))'),
             file.path(root, ".Rprofile"))
  write_lock(root)
  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE)
  expect_identical(attr(status, "renv"), "retained")
  expect_null(calls$exprs)
})

test_that("the real renv snapshot records the study's own library, not the caller's", {
  skip_on_cran()
  skip_if_not_installed("renv")
  skip_if_not_installed("digest")
  # A caller whose startup skips profiles hands the child no .Rprofile; the
  # snapshot must still run in the study's project library, where digest is
  # not installed, so the lockfile must not record it.
  withr::local_envvar(R_PROFILE_USER = "", R_ENVIRON_USER = "")
  root <- withr::local_tempdir()
  write_file(root, "analyses/model.R", "library(digest)")

  status <- study_setup(root, "Legacy study", 42L, adopt = TRUE, renv = TRUE, cleanup = FALSE)

  expect_identical(attr(status, "renv"), "initialized")
  lock <- jsonlite::read_json(file.path(root, "renv.lock"))
  expect_false("digest" %in% names(lock$Packages))
  expect_true(all(.study_renv_parts(root)))
  expect_match(paste(readLines(file.path(root, "renv", "settings.json")), collapse = ""),
               '"snapshot.type": "explicit"', fixed = TRUE)
  expect_match(paste(readLines(file.path(root, "renv", "settings.json")), collapse = ""),
               '"use.cache": false', fixed = TRUE)
})

test_that("renv = TRUE stops before writing when renv is not installed", {
  root <- file.path(withr::local_tempdir(), "new")
  local_mocked_bindings(.renv_installed = function() FALSE)
  expect_error(study_setup(root, "Study", 42L, adopt = TRUE, cleanup = FALSE, renv = TRUE),
               "renv = FALSE")
  expect_false(file.exists(root))
})

test_that("renv = TRUE stops before writing when the root has a package DESCRIPTION", {
  root <- withr::local_tempdir()
  writeLines(c("Package: foo", "Version: 1.0.0"), file.path(root, "DESCRIPTION"))
  expect_error(study_setup(root, "Study", 42L, adopt = TRUE, cleanup = FALSE, renv = TRUE),
               "renv = FALSE")
  expect_false(file.exists(file.path(root, "_study.yml")))
  expect_length(list.dirs(root, recursive = FALSE), 0L)
})

test_that("a retained renv environment skips the renv preflight", {
  root <- withr::local_tempdir()
  write_renv_start(root)
  write_lock(root)
  writeLines(c("Package: foo", "Version: 1.0.0"), file.path(root, "DESCRIPTION"))
  local_mocked_bindings(.renv_installed = function() FALSE)
  status <- study_setup(root, "Study", 42L, adopt = TRUE, cleanup = FALSE, renv = TRUE)
  expect_identical(attr(status, "renv"), "retained")
})

test_that("an existing .renvignore gains the new lines and keeps the user's", {
  root <- withr::local_tempdir()
  writeLines(c("templates/", "mydir/"), file.path(root, ".renvignore"))
  study_setup(root, "Study", 42L, adopt = TRUE, cleanup = FALSE, renv = FALSE)
  got <- readLines(file.path(root, ".renvignore"))
  expect_identical(got[1:2], c("templates/", "mydir/"))
  expect_setequal(got, union(c("templates/", "mydir/"), .study_renvignore()))
  expect_false(anyDuplicated(got) > 0L)
})

test_that("appending to a file with no trailing newline starts a new line", {
  f <- withr::local_tempfile()
  cat("templates/\nmydir/", file = f)
  .study_append_lines_missing(c("templates/", "a/", "b/"), f)
  expect_identical(readLines(f), c("templates/", "mydir/", "a/", "b/"))
  expect_identical(readBin(f, "raw", file.size(f))[file.size(f)], as.raw(10L))
})

test_that("two successive appends leave clean lines", {
  f <- withr::local_tempfile()
  cat("x", file = f)
  .study_append_lines_missing("a/", f)
  .study_append_lines_missing(c("a/", "b/"), f)
  expect_identical(readLines(f), c("x", "a/", "b/"))
})
