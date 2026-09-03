# catalog_file passthrough to haven::read_sas(). See
# dev/specs/2026-09-02-label-length-and-fallback-design.md sections 2.3 and 5.

# A .sas7bdat stores a format's NAME (YESNOF.), not its values. The
# code-to-text mapping lives in the .sas7bcat catalogue, and without one no
# amount of correct reading produces value labels. No .sas7bcat ships with
# haven or with this package, so these tests prove the argument reaches
# haven::read_sas() and is validated -- not that a real catalogue decodes.
# That claim needs a catalogue from the study corpus and is stated as an
# open item in the design note's section 8.

sas_fixture <- function() {
  path <- system.file("examples", "iris.sas7bdat", package = "haven")
  if (!nzchar(path)) skip("haven's iris.sas7bdat example is not installed")
  path
}

test_that("omitting catalog_file reads exactly as before", {
  d <- read_clinical_data(sas_fixture(), convert_types = FALSE)

  expect_s3_class(d, "data.frame")
  expect_equal(nrow(d), 150)
})

test_that("catalog_file reaches haven::read_sas()", {
  # A file that exists but is not a catalogue: haven's own parse error is the
  # evidence the argument was forwarded. Asserting the happy path is not
  # possible without a real .sas7bcat, but an argument that is silently
  # dropped would read the data and succeed here.
  bogus <- withr::local_tempfile(fileext = ".sas7bcat")
  writeLines("not a catalog", bogus)

  expect_error(
    read_clinical_data(sas_fixture(), convert_types = FALSE,
                       catalog_file = bogus),
    "Failed to parse"
  )
})

test_that("a missing catalogue is named as the catalogue", {
  # Two path arguments now. "does not exist" without saying which file is
  # the failure a caller cannot act on.
  expect_error(
    read_clinical_data(sas_fixture(), convert_types = FALSE,
                       catalog_file = "no-such-file.sas7bcat"),
    "Format catalog not found"
  )
})

test_that("catalog_file must be a single path", {
  expect_error(
    read_clinical_data(sas_fixture(), catalog_file = 42),
    "single file path"
  )
  expect_error(
    read_clinical_data(sas_fixture(), catalog_file = c("a.sas7bcat",
                                                       "b.sas7bcat")),
    "single file path"
  )
})

test_that("a catalogue with a non-SAS data file errors rather than being ignored", {
  # Only read_sas() takes a catalogue. Accepting one alongside a CSV and
  # quietly doing nothing with it would let a caller believe they had value
  # labels when nothing had even looked for them.
  tmp <- withr::local_tempfile(fileext = ".csv")
  write.csv(mtcars, tmp, row.names = FALSE)
  cat_file <- withr::local_tempfile(fileext = ".sas7bcat")
  writeLines("x", cat_file)

  expect_error(
    read_clinical_data(tmp, convert_types = FALSE, catalog_file = cat_file),
    "only applies to \\.sas7bdat"
  )
})

test_that("fetching a catalogue then discarding it warns", {
  # Supplying a catalogue states an intent: the code-to-text mapping is
  # wanted. Converting with use_value_labels at its FALSE default throws that
  # mapping away immediately after going to the trouble of reading it. The
  # generic r_data_types() warning may already be spent for the session, so
  # this names the specific combination and fires every time.
  bogus <- withr::local_tempfile(fileext = ".sas7bcat")
  writeLines("not a catalog", bogus)

  expect_warning(
    try(read_clinical_data(sas_fixture(), convert_types = TRUE,
                           catalog_file = bogus), silent = TRUE),
    "use_value_labels"
  )
})

test_that("naming use_value_labels alongside a catalogue does not warn", {
  bogus <- withr::local_tempfile(fileext = ".sas7bcat")
  writeLines("not a catalog", bogus)

  expect_no_warning(
    try(read_clinical_data(sas_fixture(), convert_types = TRUE,
                           catalog_file = bogus, use_value_labels = TRUE),
        silent = TRUE)
  )
})
