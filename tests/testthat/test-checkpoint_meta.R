test_that("CHECKPOINT.yml hashes files, lists documents and names no denied file", {
  root <- withr::local_tempdir()
  repo <- withr::local_tempdir()
  plant_files(repo, c("a.R", "30_analyses/b.R"))
  plant_files(root, "50_documents/manuscript.docx", text = "submitted")
  sel <- list(files = c("a.R", "30_analyses/b.R"),
              documents = "50_documents/manuscript.docx",
              skipped = data.frame(path = "big.R", bytes = 9e7),
              denied = c(data_folder = 2L, data_extension = 1L,
                         output_extension = 0L, credential = 1L,
                         symlink = 0L))
  entry <- list(type = "checkpoint", checkpoint_id = "id-1", st_id = 1267L,
                kind = "manuscript_submitted", note = NULL,
                git_commit = NULL, tag = "manuscript_submitted-1",
                state = "committing",
                delivery = list(git = "pending", st = "pending"))
  .cp_write_meta(repo, root, entry, sel)
  meta <- yaml::read_yaml(file.path(repo, "CHECKPOINT.yml"))
  expect_equal(meta$tag, "manuscript_submitted-1")
  expect_equal(meta$seq, 1L)
  expect_null(meta$delivery)
  expect_null(meta$state)
  expect_true("note" %in% names(meta))
  expect_equal(meta$files[["a.R"]],
               digest::digest(file.path(repo, "a.R"), algo = "sha256",
                              file = TRUE))
  expect_equal(meta$documents[[1]]$path, "50_documents/manuscript.docx")
  expect_equal(meta$documents[[1]]$sha256,
               digest::digest(file.path(root, "50_documents/manuscript.docx"),
                              algo = "sha256", file = TRUE))
  expect_equal(meta$documents[[1]]$bytes,
               file.size(file.path(root, "50_documents/manuscript.docx")))
  expect_equal(meta$denied$data_folder, 2L)
  expect_equal(meta$denied$credential, 1L)
  expect_equal(meta$skipped[[1]]$path, "big.R")
  expect_false(any(grepl("datasets", names(meta$files))))
  expect_true(nzchar(meta$r_version))
})

test_that("a manifest entry without n_rows is recorded as unchecked", {
  root <- withr::local_tempdir()
  plant_files(root, "00_datasets/built.csv")
  sha <- digest::digest(file.path(root, "00_datasets/built.csv"),
                        algo = "sha256", file = TRUE)
  yaml::write_yaml(
    list(datasets = list(list(file = "built.csv", extract_date = "2026-09-01",
                              sha256 = sha, role = "source"))),
    file.path(root, "manifest.yaml")
  )
  res <- .cp_manifest_check(root)
  expect_equal(res$datasets[["built.csv"]], "unchecked")
  expect_identical(res$warnings, character(0))
})

test_that("an entry whose row count cannot be checked is recorded as unchecked", {
  root <- withr::local_tempdir()
  plant_files(root, c("00_datasets/built.parquet", "00_datasets/rows.csv"))
  sha <- function(f) digest::digest(file.path(root, "00_datasets", f),
                                    algo = "sha256", file = TRUE)
  yaml::write_yaml(
    list(datasets = list(
      list(file = "built.parquet", extract_date = "2026-09-01", n_rows = 1L,
           sha256 = sha("built.parquet"), role = "source"),
      list(file = "rows.csv", extract_date = "2026-09-01", n_rows = 0L,
           sha256 = sha("rows.csv"), role = "source")
    )),
    file.path(root, "manifest.yaml")
  )
  res <- .cp_manifest_check(root)
  expect_equal(res$datasets[["built.parquet"]], "unchecked")
  expect_equal(res$datasets[["rows.csv"]], "OK")
})

test_that("a manifest mismatch in the source study warns and is recorded", {
  root <- withr::local_tempdir()
  plant_files(root, "datasets/built.csv")
  yaml::write_yaml(
    list(datasets = list(list(file = "built.csv", extract_date = "2026-09-01",
                              n_rows = 1L, sha256 = strrep("0", 64),
                              role = "source"))),
    file.path(root, "manifest.yaml")
  )
  expect_warning(res <- .cp_manifest_check(root),
                 "manifest verification failed")
  expect_equal(res$datasets[["built.csv"]], "FAIL")
  expect_length(res$warnings, 1L)
  expect_match(res$warnings, "SHA-256 mismatch")
})

test_that("a manifest that cannot be verified warns and records the error", {
  root <- withr::local_tempdir()
  plant_files(root, c("00_datasets/a.csv", "datasets/b.csv"))
  yaml::write_yaml(
    list(datasets = list(list(file = "a.csv", extract_date = "2026-09-01",
                              sha256 = strrep("0", 64), role = "source"))),
    file.path(root, "manifest.yaml")
  )
  expect_warning(res <- .cp_manifest_check(root), "could not be verified")
  expect_match(res$error, "layout is mixed")
})

test_that("no manifest gives NULL", {
  expect_null(.cp_manifest_check(withr::local_tempdir()))
})
