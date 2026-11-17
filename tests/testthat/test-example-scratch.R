# Examples that write files must use a directory of their own, made with
# tempfile(), and remove only that. tempdir() is shared by the whole R session,
# so an example that writes to, or recursively deletes, a fixed name under it
# can destroy a user's scratch files (review of #305).

.example_rd <- function(topic) {
  man <- testthat::test_path("..", "..", "man")
  db <- if (dir.exists(man)) tools::Rd_db(dir = dirname(man)) else tools::Rd_db("hvtiRutilities")
  db[[paste0(topic, ".Rd")]]
}

test_that("file-writing examples leave existing tempdir() contents alone", {
  topics <- c("sas_triage", "write_macro_manifest", "write_collision_report", "study_declare")
  # The fixed names earlier versions of these examples used, plus a loose file.
  fixed <- file.path(tempdir(), c("macros", "declare-example"))
  for (d in fixed) dir.create(d, showWarnings = FALSE)
  sentinels <- c(file.path(fixed, "hello.sas"), file.path(fixed, "sentinel.txt"),
                 file.path(tempdir(), "sentinel-example.txt"))
  for (f in sentinels) writeLines("user scratch", f)
  on.exit(unlink(c(fixed, sentinels), recursive = TRUE), add = TRUE)

  for (topic in topics) {
    rd <- .example_rd(topic)
    skip_if(is.null(rd), paste("no Rd for", topic))
    before <- list.files(tempdir())
    ex <- tempfile(fileext = ".R")
    tools::Rd2ex(rd, ex)
    utils::capture.output(suppressMessages(source(ex, local = new.env())))
    unlink(ex)
    expect_true(all(file.exists(sentinels)), label = paste(topic, "keeps existing files"))
    expect_identical(readLines(sentinels[1]), "user scratch", label = paste(topic, "does not overwrite"))
    expect_setequal(list.files(tempdir()), before)
  }
})
