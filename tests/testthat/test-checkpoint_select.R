allowed <- c(
  "_study.yml", "renv.lock", "renv/activate.R", ".Rprofile", "manifest.yaml",
  ".renvignore", "README.md", "study.Rproj", "_quarto.yml",
  "30_analyses/fit.R", "30_analyses/report.qmd", "30_analyses/old.Rmd",
  "10_descriptive/desc.sas", "30_analyses/run.sh", "30_analyses/q.sql",
  "30_analyses/x.py", "50_documents/refs.bib", "50_documents/paper.qmd"
)
documents <- c(
  "50_documents/manuscript.docx", "50_documents/slides.pptx",
  "50_documents/submitted.pdf", "50_documents/fig1.png",
  "50_documents/fig2.tiff", "50_documents/supplement.xlsx",
  "50_documents/table.csv", "50_documents/notes.txt"
)
denied_folder <- c("00_datasets/built.sas7bdat", "00_datasets/notes.R",
                   "90_estimates/fit.R")
denied_data <- c("30_analyses/cohort.csv", "30_analyses/out.rds",
                 "10_descriptive/desc.lst", "10_descriptive/desc.log")
denied_output <- c("30_analyses/report.html", "30_analyses/report.pdf",
                   "40_graphs/fig.png", "30_analyses/draft.docx")
tooling <- c("renv/library/pkg/R/pkg.R", ".checkpoint/log.yml")
unlisted <- c("30_analyses/notes.txt", "30_analyses/README.md")

test_that("selection keeps exactly the allow-list and never a denied file", {
  root <- withr::local_tempdir()
  plant_files(root, c(allowed, documents, denied_folder, denied_data,
                      denied_output, tooling, unlisted))
  sel <- .cp_select(root, include = "**/*.csv")
  expect_setequal(sel$files, allowed)
  expect_setequal(sel$documents, documents)
  expect_equal(sel$denied[["data_folder"]], 3L)
  expect_equal(sel$denied[["data_extension"]], 4L)
  expect_equal(sel$denied[["output_extension"]], 4L)
  expect_equal(sel$denied[["credential"]], 0L)
  expect_equal(sel$denied[["symlink"]], 0L)
})

test_that("include patterns admit extra files but cannot admit data", {
  root <- withr::local_tempdir()
  plant_files(root, c("30_analyses/notes.txt", "30_analyses/cohort.csv",
                      "00_datasets/extra.txt"))
  sel <- .cp_select(root, include = c("*.txt", "*.csv"))
  expect_equal(sel$files, "30_analyses/notes.txt")
})

test_that("include patterns cannot admit any known data format", {
  root <- withr::local_tempdir()
  ext <- c("rda", "tsv", "sav", "dta", "sas7bcat", "feather", "fst", "qs",
           "sqlite", "db", "zip", "gz", "RDA", "Zip")
  # Distinct stems, so a case-insensitive file system keeps data.rda and
  # data.RDA apart.
  data <- paste0("30_analyses/data", seq_along(ext), ".", ext)
  plant_files(root, c(data, "30_analyses/notes.txt"))
  sel <- .cp_select(root, include = c("*", "**/*", paste0("*.", ext)))
  expect_equal(sel$files, "30_analyses/notes.txt")
  expect_equal(sel$denied[["data_extension"]], length(ext))
})

test_that("legacy folder spellings get the same rules", {
  root <- withr::local_tempdir()
  plant_files(root, c("datasets/built.csv", "estimates/fit.R",
                      "documents/manuscript.docx", "documents/paper.qmd",
                      "analyses/fit.R"))
  sel <- .cp_select(root)
  expect_setequal(sel$files, c("documents/paper.qmd", "analyses/fit.R"))
  expect_equal(sel$documents, "documents/manuscript.docx")
  expect_equal(sel$denied[["data_folder"]], 2L)
})

test_that("credentials are denied anywhere, even in the document folders", {
  root <- withr::local_tempdir()
  creds <- c(".env", ".Renviron", ".netrc", ".git-credentials",
             "30_analyses/tracker.env", "keys/id_rsa", "keys/id_ed25519.pub",
             "certs/server.pem", "certs/api.key", "certs/client.p12",
             "certs/client.pfx", "50_documents/.env")
  plant_files(root, c(creds, "30_analyses/fit.R"))
  sel <- .cp_select(root, include = c("*.env", "*.pem", "id_*", ".*"))
  expect_equal(sel$files, "30_analyses/fit.R")
  expect_length(sel$documents, 0L)
  expect_equal(sel$denied[["credential"]], 12L)
})

test_that("symbolic links are denied and never followed", {
  testthat::skip_on_os("windows")
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  plant_files(outside, c("secret.R", "dir/inner.R"))
  plant_files(root, "30_analyses/fit.R")
  file.symlink(file.path(outside, "secret.R"),
               file.path(root, "30_analyses", "linked.R"))
  file.symlink(file.path(outside, "dir"),
               file.path(root, "30_analyses", "linkdir"))
  sel <- .cp_select(root, include = "**/*.R")
  expect_equal(sel$files, "30_analyses/fit.R")
  expect_equal(sel$denied[["symlink"]], 2L)
})

# A directory link: a symlink, or on Windows a junction when symlinks need a
# privilege the session lacks. NULL when neither can be made.
make_dir_link <- function(target, link) {
  ok <- suppressWarnings(file.symlink(target, link))
  # Sys.junction() exists only in Windows builds of R, so it is looked up.
  junction <- get0("Sys.junction", envir = baseenv(), mode = "function")
  if (!isTRUE(ok) && !is.null(junction)) {
    ok <- suppressWarnings(junction(target, link))
  }
  if (isTRUE(ok) && dir.exists(link)) link else NULL
}

test_that("a file reached through a directory link to outside the root is denied", {
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  plant_files(outside, "inner.R")
  plant_files(root, "30_analyses/fit.R")
  link <- make_dir_link(outside, file.path(root, "30_analyses", "linkdir"))
  if (is.null(link)) testthat::skip("could not create a directory link")
  sel <- .cp_select(root, include = "**/*.R")
  expect_equal(sel$files, "30_analyses/fit.R")
  expect_equal(sel$denied[["symlink"]], 1L)
})

test_that("a link is denied even where Sys.readlink() cannot see it", {
  # On Windows Sys.readlink() returns "" for links and junctions; the
  # resolved-path comparison must catch them on its own.
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  plant_files(outside, c("inner.R", "secret.R"))
  plant_files(root, "30_analyses/fit.R")
  link <- make_dir_link(outside, file.path(root, "30_analyses", "linkdir"))
  if (is.null(link)) testthat::skip("could not create a directory link")
  testthat::local_mocked_bindings(.cp_readlink = function(path) rep("", length(path)))
  sel <- .cp_select(root, include = "**/*.R")
  expect_equal(sel$files, "30_analyses/fit.R")
  expect_equal(sel$denied[["symlink"]], 2L)
})

test_that("ordinary nested files and names with spaces are not taken for links", {
  root <- withr::local_tempdir()
  files <- c("30_analyses/fit.R", "30_analyses/sub model/deep dir/fit two.R",
             "10_descriptive/a b/desc.sas", "renv.lock")
  plant_files(root, files)
  sel <- .cp_select(root)
  expect_setequal(sel$files, files)
  expect_equal(sel$denied[["symlink"]], 0L)
})

test_that("files over the size cap are skipped and reported", {
  root <- withr::local_tempdir()
  plant_files(root, "30_analyses/big.R", text = strrep("x", 200))
  plant_files(root, "30_analyses/small.R")
  sel <- .cp_select(root, max_bytes = 100)
  expect_equal(sel$files, "30_analyses/small.R")
  expect_equal(sel$skipped$path, "30_analyses/big.R")
})

test_that("credentials and folder names are denied case-insensitively", {
  root <- withr::local_tempdir()
  plant_files(root, c("keys/ID_RSA", "50_documents/.ENV", "30_analyses/Tracker.env",
                      "00_Datasets/built.R", "Documents/paper.docx"))
  sel <- .cp_select(root, include = c("*", ".*", "**/*"))
  expect_false(any(c("keys/ID_RSA", "50_documents/.ENV", "30_analyses/Tracker.env",
                     "00_Datasets/built.R") %in% sel$files))
  expect_equal(sel$denied[["credential"]], 3L)
  expect_equal(sel$denied[["data_folder"]], 1L)
  expect_equal(sel$documents, "Documents/paper.docx")
})
